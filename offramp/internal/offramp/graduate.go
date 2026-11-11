// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package offramp

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strings"

	"github.com/google/cel-go/cel"
	"github.com/google/cel-go/ext"
	"github.com/highfivelabs/catalog/tools/convert"
	"sigs.k8s.io/yaml"
)

// Graduating a module call: where the catalog has a chart that ports the
// module the call uses, the call's arguments are the chart's values
// unchanged (catalogtool convert reads them from the root module's HCL).
// The chart is rendered with them, and the render is compared, resource by
// resource, with the Config Connector objects converted from the state.
// Only a call whose render matches graduates to an Instance of the chart;
// any other call keeps its frozen Package (the design, "Day two").

// GraduateOptions say where the root module and the catalog are.
type GraduateOptions struct {
	// Catalog is the catalog repository's root (upstream/modules.yaml, charts/).
	Catalog string
	// Root is the Terraform root module's directory.
	Root string
	// Tfvars are the values of its variables.
	Tfvars []string
	// ModulesJSON is .terraform/modules/modules.json (default: under Root,
	// when there); it names each call's source and version as resolved.
	ModulesJSON string
	// Namespace is the namespace the charts are rendered for.
	Namespace string
}

// Graduated is one module call and what became of it.
type Graduated struct {
	Call      string // the Terraform label
	Component string // the Bundt component name
	Chart     *convert.Chart
	// Inputs and Values are catalogtool convert's (the Template component's
	// inputs and the Instance's values); Import is what the import adds.
	Inputs, Values convert.Ordered
	Import         convert.Ordered
	// Effective are the values the chart was rendered with, every
	// ${components...} expression resolved.
	Effective map[string]any
	// Rendered is the chart's render; Normalized the same with references
	// resolved to the resources' names, as the state names them.
	Rendered, Normalized []map[string]any
	// State are the objects converted from the state for this call.
	State []map[string]any
	// Outputs are the chart's outputs, evaluated over the render with each
	// object's status taken from the state.
	Outputs     map[string]any
	Differences []Difference
	Err         string
}

// OK says the call graduates: the render matches the state.
func (g *Graduated) OK() bool { return g.Err == "" && len(g.Differences) == 0 }

// Graduation is the result for a root module.
type Graduation struct {
	Convert *convert.Result
	// Calls by Terraform label; a call with no chart is absent.
	Calls map[string]*Graduated
	Order []string
}

// Graduate converts the root module's calls to chart values and checks
// each chart's render against the objects converted from the state.
func Graduate(res *Result, st *State, opt GraduateOptions) (*Graduation, error) {
	repo, err := convert.OpenRepo(opt.Catalog)
	if err != nil {
		return nil, err
	}
	co := convert.Options{Repo: repo, Tfvars: opt.Tfvars}
	mj := opt.ModulesJSON
	if mj == "" {
		if p := filepath.Join(opt.Root, ".terraform", "modules", "modules.json"); fileExists(p) {
			mj = p
		}
	}
	if mj != "" {
		if co.Sources, err = convert.ReadModulesJSON(mj); err != nil {
			return nil, err
		}
	}
	cres, err := convert.Convert(opt.Root, co)
	if err != nil && cres == nil {
		return nil, err
	}
	g := &Graduation{Convert: cres, Calls: map[string]*Graduated{}}
	if cres == nil {
		return g, nil
	}
	attrs := map[string]map[string]any{}
	for _, in := range st.Instances() {
		attrs[in.Address] = in.Attrs
	}
	byComponent := map[string][]*Object{}
	for _, o := range res.Objects {
		byComponent[componentName(o.Call)] = append(byComponent[componentName(o.Call)], o)
	}
	labelOf := map[string]string{}
	for _, o := range res.Objects {
		labelOf[componentName(o.Call)] = o.Call
	}
	outputs := map[string]map[string]any{}
	for _, c := range order(cres.Components) {
		gr := &Graduated{Component: c.Name, Chart: c.Chart, Inputs: c.Inputs, Values: c.Values, Call: labelOf[c.Name]}
		if gr.Call == "" {
			gr.Call = strings.ReplaceAll(c.Name, "-", "_")
		}
		g.Calls[gr.Call] = gr
		g.Order = append(g.Order, gr.Call)
		objs := byComponent[c.Name]
		for _, o := range objs {
			gr.State = append(gr.State, o.Obj)
		}
		if _, ok := c.Chart.Values["deletion_policy"]; ok {
			gr.Import = append(gr.Import, convert.Pair{Key: "deletion_policy", Value: "ABANDON"})
		}
		vals := map[string]any{}
		for _, p := range append(append(append(convert.Ordered{}, c.Inputs...), c.Values...), gr.Import...) {
			vals[p.Key] = p.Value
		}
		eff, err := resolveExpressions(vals, outputs)
		if err != nil {
			gr.Err = err.Error()
			continue
		}
		gr.Effective = eff.(map[string]any)
		rendered, err := renderChart(filepath.Join(opt.Catalog, c.Chart.Dir), c.Name, opt.Namespace, gr.Effective)
		if err != nil {
			gr.Err = err.Error()
			continue
		}
		// Resources the cloud names (a folder's number): the chart names the
		// existing one through resource_ids, from the state.
		if ids := serverAssigned(rendered, objs); len(ids) > 0 {
			if _, ok := c.Chart.Values["resource_ids"]; ok {
				gr.Import = append(gr.Import, convert.Pair{Key: "resource_ids", Value: ids})
				gr.Effective["resource_ids"] = ids
				if rendered, err = renderChart(filepath.Join(opt.Catalog, c.Chart.Dir), c.Name, opt.Namespace, gr.Effective); err != nil {
					gr.Err = err.Error()
					continue
				}
			}
		}
		gr.Rendered = rendered
		match := matchObjects(rendered, objs, attrs)
		gr.Normalized = normalize(rendered, match, attrs)
		gr.Differences = Compare(gr.Normalized, gr.State)
		gr.Outputs = evalOutputs(filepath.Join(opt.Catalog, c.Chart.Dir), c.Chart.Values, gr.Effective, rendered, match, attrs)
		outputs[c.Name] = gr.Outputs
	}
	return g, nil
}

func fileExists(p string) bool { _, err := os.Stat(p); return err == nil }

// order puts the components so each comes after those its values read.
func order(cs []*convert.Component) []*convert.Component {
	byName := map[string]*convert.Component{}
	for _, c := range cs {
		byName[c.Name] = c
	}
	var out []*convert.Component
	done := map[string]bool{}
	var visit func(c *convert.Component, depth int)
	visit = func(c *convert.Component, depth int) {
		if done[c.Name] || depth > len(cs) {
			return
		}
		var deps []string
		deps = append(deps, c.DependsOn...)
		for _, p := range append(append(convert.Ordered{}, c.Inputs...), c.Values...) {
			deps = append(deps, refsIn(p.Value)...)
		}
		for _, d := range deps {
			if dc := byName[d]; dc != nil {
				visit(dc, depth+1)
			}
		}
		if !done[c.Name] {
			done[c.Name] = true
			out = append(out, c)
		}
	}
	for _, c := range cs {
		visit(c, 0)
	}
	return out
}

var compRef = regexp.MustCompile(`components\.([a-z0-9-]+)\.outputs`)

func refsIn(v any) []string {
	var out []string
	switch x := v.(type) {
	case string:
		for _, m := range compRef.FindAllStringSubmatch(x, -1) {
			out = append(out, m[1])
		}
	case []any:
		for _, e := range x {
			out = append(out, refsIn(e)...)
		}
	case map[string]any:
		for _, e := range x {
			out = append(out, refsIn(e)...)
		}
	}
	return out
}

var exprRE = regexp.MustCompile(`\$\{([^}]+)\}`)

// resolveExpressions evaluates the ${...} expressions of a component's
// values with the outputs of the components already graduated, as Bundt
// evaluates them when it plans.
func resolveExpressions(v any, outputs map[string]map[string]any) (any, error) {
	switch x := v.(type) {
	case string:
		if !strings.Contains(x, "${") {
			return x, nil
		}
		if m := exprRE.FindStringSubmatch(x); m != nil && m[0] == x {
			return evalExpr(m[1], outputs)
		}
		var firstErr error
		out := exprRE.ReplaceAllStringFunc(x, func(s string) string {
			r, err := evalExpr(s[2:len(s)-1], outputs)
			if err != nil && firstErr == nil {
				firstErr = err
			}
			return fmt.Sprint(r)
		})
		return out, firstErr
	case []any:
		out := make([]any, len(x))
		for i, e := range x {
			r, err := resolveExpressions(e, outputs)
			if err != nil {
				return nil, err
			}
			out[i] = r
		}
		return out, nil
	case map[string]any:
		out := map[string]any{}
		for k, e := range x {
			r, err := resolveExpressions(e, outputs)
			if err != nil {
				return nil, err
			}
			out[k] = r
		}
		return out, nil
	}
	return v, nil
}

func evalExpr(expr string, outputs map[string]map[string]any) (any, error) {
	// A component's name may hold a hyphen, which CEL's member selection
	// does not take: components.platform-ci is components['platform-ci'].
	expr = regexp.MustCompile(`components\.([a-z0-9-]+)\.`).ReplaceAllString(expr, "components['$1'].")
	env, err := cel.NewEnv(cel.Variable("components", cel.MapType(cel.StringType, cel.DynType)), ext.Strings(), ext.Lists())
	if err != nil {
		return nil, err
	}
	ast, iss := env.Compile(expr)
	if iss.Err() != nil {
		return nil, fmt.Errorf("${%s}: %v", expr, iss.Err())
	}
	prg, err := env.Program(ast)
	if err != nil {
		return nil, err
	}
	comps := map[string]any{}
	for n, o := range outputs {
		comps[n] = map[string]any{"outputs": o}
	}
	val, _, err := prg.Eval(map[string]any{"components": comps})
	if err != nil {
		return nil, fmt.Errorf("${%s}: %v (an output the producer's render and state cannot give)", expr, err)
	}
	return val.ConvertToNative(anyType)
}

// renderChart is `helm template`, the way Bundt renders a helm Package.
func renderChart(dir, release, ns string, values map[string]any) ([]map[string]any, error) {
	if ns == "" {
		ns = "default"
	}
	data, err := yaml.Marshal(values)
	if err != nil {
		return nil, err
	}
	f, err := os.CreateTemp("", "offramp-values-*.yaml")
	if err != nil {
		return nil, err
	}
	defer os.Remove(f.Name())
	if _, err := f.Write(data); err != nil {
		return nil, err
	}
	f.Close()
	cmd := exec.Command("helm", "template", release, dir, "--namespace", ns, "-f", f.Name())
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("helm template %s: %s", filepath.Base(dir), strings.Join(strings.Fields(stderr.String()), " "))
	}
	var out []map[string]any
	for _, doc := range strings.Split(stdout.String(), "\n---") {
		var m map[string]any
		if err := yaml.Unmarshal([]byte(doc), &m); err != nil {
			return nil, err
		}
		if len(m) > 0 && m["kind"] != nil {
			out = append(out, m)
		}
	}
	return out, nil
}

// serverAssigned matches rendered objects with no resource ID (the cloud
// names them: a folder, a hierarchical firewall policy) to the state's by
// kind and their caller-given name, and gives their resource IDs by the
// rendered object's hfl.dev/id.
func serverAssigned(rendered []map[string]any, objs []*Object) map[string]any {
	ids := map[string]any{}
	for _, r := range rendered {
		if str(dig(r, "spec", "resourceID")) != "" {
			continue
		}
		if s := byGivenName(r, objs); s != nil {
			if id := str(dig(s.Obj, "spec", "resourceID")); id != "" {
				ids[str(dig(r, "metadata", "annotations", AnnID))] = id
			}
		}
	}
	return ids
}

// givenNames are the fields that hold the caller's name for a resource
// whose ID the cloud assigns.
var givenNames = []string{"displayName", "shortName"}

func byGivenName(r map[string]any, objs []*Object) *Object {
	for _, f := range givenNames {
		v := str(dig(r, "spec", f))
		if v == "" {
			continue
		}
		for _, o := range objs {
			if o.Kind == str(r["kind"]) && str(dig(o.Obj, "spec", f)) == v {
				return o
			}
		}
	}
	return nil
}

// matchObjects pairs each rendered object (by metadata.name) with the
// state's object for the same resource.
func matchObjects(rendered []map[string]any, objs []*Object, attrs map[string]map[string]any) map[string]*Object {
	match := map[string]*Object{}
	key := func(kind, name string) string { return kind + "/" + name }
	// Resources first, by identity (kind, where and resource ID).
	byID := map[string]*Object{}
	for _, o := range objs {
		byID[Identity(o.Obj)] = o
	}
	for _, r := range rendered {
		k := str(r["kind"])
		if strings.HasPrefix(k, "IAM") {
			continue
		}
		if o := byID[Identity(r)]; o != nil {
			match[key(k, str(dig(r, "metadata", "name")))] = o
		} else if o := byGivenName(r, objs); o != nil {
			match[key(k, str(dig(r, "metadata", "name")))] = o
		}
	}
	return match
}

// canonical is how the state refers to a resource: its self link or ID.
func canonical(o *Object, attrs map[string]map[string]any) string {
	a := attrs[o.Source]
	for _, f := range []string{"self_link", "id", "name"} {
		if s := str(a[f]); s != "" {
			return s
		}
	}
	return str(dig(o.Obj, "spec", "resourceID"))
}

// normalize rewrites a render's references between its own objects ({name:
// x}) as the state writes them ({external: <self link or ID>}), and a
// member taken from a service account reference as the member, so the
// render and the state can be compared field by field.
func normalize(rendered []map[string]any, match map[string]*Object, attrs map[string]map[string]any) []map[string]any {
	byName := map[string]*Object{}
	for k, o := range match {
		byName[k[strings.Index(k, "/")+1:]] = o
		byName[k] = o
	}
	var out []map[string]any
	for _, r := range rendered {
		c := deepCopy(r).(map[string]any)
		spec, _ := c["spec"].(map[string]any)
		if spec != nil {
			if mf, ok := spec["memberFrom"].(map[string]any); ok {
				if sa, ok := mf["serviceAccountRef"].(map[string]any); ok {
					if o := byName["IAMServiceAccount/"+str(sa["name"])]; o != nil {
						spec["member"] = "serviceAccount:" + str(attrs[o.Source]["email"])
						delete(spec, "memberFrom")
					}
				}
			}
			rewriteRefs(spec, func(kind, name string) (string, bool) {
				o := byName[kind+"/"+name]
				if o == nil && kind == "" {
					o = byName[name]
				}
				if o == nil {
					return "", false
				}
				return canonical(o, attrs), true
			})
		}
		out = append(out, c)
	}
	return out
}

func rewriteRefs(v any, resolve func(kind, name string) (string, bool)) {
	switch x := v.(type) {
	case map[string]any:
		for k, e := range x {
			m, ok := e.(map[string]any)
			if ok && (strings.HasSuffix(k, "Ref") || k == "resourceRef") {
				if n := str(m["name"]); n != "" && m["external"] == nil {
					if ext, ok := resolve(str(m["kind"]), n); ok {
						delete(m, "name")
						delete(m, "namespace")
						m["external"] = ext
					}
				}
				continue
			}
			rewriteRefs(e, resolve)
		}
	case []any:
		for _, e := range x {
			rewriteRefs(e, resolve)
		}
	}
}

func deepCopy(v any) any {
	switch x := v.(type) {
	case map[string]any:
		out := map[string]any{}
		for k, e := range x {
			out[k] = deepCopy(e)
		}
		return out
	case []any:
		out := make([]any, len(x))
		for i, e := range x {
			out[i] = deepCopy(e)
		}
		return out
	}
	return v
}

// evalOutputs evaluates the chart's Package outputs (bare CEL over
// resources and inputs, the catalog's docs/design.md, "Outputs") over the
// render, each object's status taken from its state counterpart: for
// Config Connector's Terraform-based kinds the status fields are the
// resource's computed attributes, named in lower camel case. An output that
// cannot be evaluated is left out.
func evalOutputs(dir string, defaults, values map[string]any, rendered []map[string]any, match map[string]*Object, attrs map[string]map[string]any) map[string]any {
	b, err := os.ReadFile(filepath.Join(dir, "package.yaml"))
	if err != nil {
		return nil
	}
	var pkg struct {
		Spec struct {
			Outputs map[string]string `json:"outputs"`
		} `json:"spec"`
	}
	if err := yaml.Unmarshal(b, &pkg); err != nil {
		return nil
	}
	resources := map[string]any{}
	for _, r := range rendered {
		c := deepCopy(r).(map[string]any)
		if o := match[str(r["kind"])+"/"+str(dig(r, "metadata", "name"))]; o != nil {
			status := map[string]any{}
			for k, v := range attrs[o.Source] {
				status[camel(k)] = v
			}
			c["status"] = status
		}
		if id := str(dig(r, "metadata", "annotations", AnnID)); id != "" {
			resources[id] = c
		}
	}
	inputs := mergeValues(deepCopy(defaults).(map[string]any), deepCopy(values).(map[string]any))
	env, err := cel.NewEnv(
		cel.Variable("resources", cel.MapType(cel.StringType, cel.DynType)),
		cel.Variable("inputs", cel.MapType(cel.StringType, cel.DynType)),
		ext.Strings(), ext.Lists(), ext.Encoders(), ext.TwoVarComprehensions(),
	)
	if err != nil {
		return nil
	}
	out := map[string]any{}
	names := make([]string, 0, len(pkg.Spec.Outputs))
	for n := range pkg.Spec.Outputs {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		ast, iss := env.Compile(pkg.Spec.Outputs[n])
		if iss.Err() != nil {
			continue
		}
		prg, err := env.Program(ast)
		if err != nil {
			continue
		}
		v, _, err := prg.Eval(map[string]any{"resources": resources, "inputs": inputs})
		if err != nil {
			continue
		}
		if nv, err := v.ConvertToNative(anyType); err == nil {
			out[n] = nv
		}
	}
	return out
}

func mergeValues(base, override map[string]any) map[string]any {
	for k, v := range override {
		bm, bok := base[k].(map[string]any)
		om, ook := v.(map[string]any)
		if bok && ook {
			base[k] = mergeValues(bm, om)
		} else {
			base[k] = v
		}
	}
	return base
}

var anyType = reflect.TypeOf((*any)(nil)).Elem()
