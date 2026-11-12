// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package offramp

import (
	"fmt"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclsyntax"
	"github.com/hashicorp/hcl/v2/hclwrite"
	"github.com/highfivelabs/catalog/tools/convert"
	"github.com/zclconf/go-cty/cty"
)

// Converting a Terragrunt estate. Each unit is a Terraform root module with
// its own state, and its source is one of two things:
//
//   - an open-source module the catalog tracks (case "module"): the module
//     is the root of the unit's state, and the unit is converted like a
//     module call of that module, its inputs the call's arguments. It
//     graduates to the module's chart when the render matches the state.
//   - the team's own root module (case "wrapper"): a local directory, or a
//     remote one given with --source-map, that calls open-source modules
//     and may declare resources of its own. The offramp descends into it:
//     each module call inside is converted against its chart as in a plain
//     Terraform root, with the unit's inputs as the root's variables; the
//     wrapper's own resources stay a frozen Package, each listed as an
//     unmapped finding.
//
// The estate becomes one Template, components named for the units (a
// wrapper's calls as <unit>-<call>). A dependency block's output becomes a
// reference to the producing component's output, and Terragrunt's order
// between units becomes dependsOn.

// EstateOptions say where the catalog, the states and the modules are.
type EstateOptions struct {
	Catalog   string
	Namespace string
	// States are the units' states by the unit's path relative to the
	// estate; StateDir holds <unit path>/terraform.tfstate for the rest.
	States   map[string]string
	StateDir string
	// ModulesJSON are terraform init's modules.json for wrapper units, by
	// unit path (default: .terraform/modules/modules.json in the wrapper's
	// directory, when there).
	ModulesJSON map[string]string
	TG          TerragruntOptions
	Convert     Options
}

// EstateUnit is what became of one unit.
type EstateUnit struct {
	*TGUnit
	// Case is module, wrapper, or unknown (the source is neither a module
	// the catalog tracks nor a directory the offramp can read).
	Case string
	// Module is the catalog's module id (case module); ModuleDir the
	// wrapper's directory (case wrapper).
	Module, ModuleDir string
	StatePath         string
	Components        []string
	// outputs are a wrapper's outputs: each the component output it
	// passes on (component, CEL path), or why it is not one.
	outputs map[string]wrapperOutput
}

type wrapperOutput struct {
	component, path, why string
}

// Estate is the converted estate.
type Estate struct {
	Units      []*EstateUnit
	Result     *Result
	Graduation *Graduation
	// DependsOn are the dependencies between units, by component.
	DependsOn map[string][]string
}

// ConvertEstate converts every unit's state and checks each module call
// against its chart.
func ConvertEstate(units []*TGUnit, k *KCC, opt EstateOptions) (*Estate, error) {
	repo, err := convert.OpenRepo(opt.Catalog)
	if err != nil {
		return nil, err
	}
	e := &Estate{Result: &Result{}, Graduation: &Graduation{Calls: map[string]*Graduated{}, Convert: &convert.Result{}}, DependsOn: map[string][]string{}}
	byDir := map[string]*EstateUnit{}
	for _, u := range units {
		eu := &EstateUnit{TGUnit: u}
		e.Units = append(e.Units, eu)
		byDir[u.Dir] = eu
	}
	ordered, cyc := orderUnits(e.Units, byDir)
	if len(cyc) > 0 {
		e.Result.Findings = append(e.Result.Findings, Finding{Source: strings.Join(cyc, ", "), Type: "dependency", Class: "note", Reason: "these units depend on each other in a cycle; they are converted in path order"})
	}
	outputs := map[string]map[string]any{}
	for _, u := range ordered {
		e.convertUnit(u, byDir, repo, k, opt, outputs)
		e.Result.Findings = append(e.Result.Findings, u.Findings...)
	}
	uniqueNames(e.Result.Objects)
	return e, nil
}

// orderUnits puts each unit after those it depends on.
func orderUnits(units []*EstateUnit, byDir map[string]*EstateUnit) ([]*EstateUnit, []string) {
	var out []*EstateUnit
	state := map[*EstateUnit]int{}
	var cyc []string
	var visit func(u *EstateUnit)
	visit = func(u *EstateUnit) {
		if state[u] == 2 {
			return
		}
		if state[u] == 1 {
			cyc = append(cyc, u.Rel)
			return
		}
		state[u] = 1
		for _, d := range u.depDirs() {
			if p := byDir[d]; p != nil {
				visit(p)
			}
		}
		state[u] = 2
		out = append(out, u)
	}
	for _, u := range units {
		visit(u)
	}
	return out, cyc
}

func (u *EstateUnit) depDirs() []string {
	var ds []string
	for _, d := range u.Dependencies {
		ds = append(ds, d.Dir)
	}
	return append(ds, u.DependsOn...)
}

func (u *EstateUnit) finding(class, typ, format string, a ...any) {
	u.Findings = append(u.Findings, Finding{Source: u.Rel, Type: typ, Class: class, Reason: fmt.Sprintf(format, a...)})
}

func (e *Estate) convertUnit(u *EstateUnit, byDir map[string]*EstateUnit, repo *convert.Repo, k *KCC, opt EstateOptions, outputs map[string]map[string]any) {
	if u.Skip {
		u.Case = "skipped"
		u.finding("note", "skip", "skip = true: Terragrunt does not run this unit, so the offramp does not convert it")
		return
	}
	// What the unit runs.
	src, version := normalizeSource(u.Source)
	var mod *convertModule
	switch {
	case u.Source == "":
		u.Case, u.ModuleDir = "wrapper", u.Dir
	case isLocalSource(u.Source):
		u.Case, u.ModuleDir = "wrapper", localSource(u.Dir, u.Source)
	default:
		m, _, _, err := repo.ResolveCall(src)
		switch {
		case err == nil:
			u.Case, u.Module = "module", m.ID
			mod = &convertModule{source: src, version: version, chart: m.Chart}
		case mappedSource(u.Source, opt.TG.SourceMap) != "":
			u.Case, u.ModuleDir = "wrapper", mappedSource(u.Source, opt.TG.SourceMap)
		default:
			u.Case = "unknown"
			u.finding("gap", "terraform.source", "%v; and it is not a directory the offramp can read: if it is the team's own module, map it to a checkout with --source-map %s=DIR. The unit's resources stay one frozen Package", err, strings.SplitN(strings.TrimPrefix(u.Source, "git::"), "//", 2)[0])
		}
	}
	if u.ModuleDir != "" {
		if _, err := os.Stat(u.ModuleDir); err != nil {
			u.finding("gap", "terraform.source", "the module directory %s is not there: %v", u.ModuleDir, err)
			u.Case = "unknown"
		} else {
			u.outputs = wrapperOutputs(u.ModuleDir, u.Label)
		}
	}

	// Dependency outputs become the producing components' outputs.
	inputs := e.resolveInputs(u, byDir)
	for _, d := range u.depDirs() {
		p := byDir[d]
		if p == nil {
			u.finding("note", "dependency", "depends on %s, which is not in the estate: no dependsOn for it", d)
			continue
		}
		for _, c := range p.Components {
			e.addDeps(u, c)
		}
	}

	// The state.
	sp := opt.States[u.Rel]
	if sp == "" && opt.StateDir != "" {
		if p := filepath.Join(opt.StateDir, filepath.FromSlash(u.Rel), "terraform.tfstate"); fileExists(p) {
			sp = p
		}
	}
	if sp == "" {
		where := "where its remote_state says"
		if u.RemoteState != nil && u.RemoteState.Location != "" {
			where = u.RemoteState.Location + " (remote_state in " + u.RemoteState.From + ")"
		}
		u.finding("gap", "state", "no state for this unit: it lives at %s. Pull it (`terragrunt state pull` in the unit, or copy the object) and pass it with --states", where)
		return
	}
	u.StatePath = sp
	st, err := ReadState(sp)
	if err != nil {
		u.finding("gap", "state", "%v", err)
		return
	}
	ures := ConvertState(st, k, opt.Convert)
	gopt := GraduateOptions{Catalog: opt.Catalog, Namespace: opt.Namespace}

	var g *Graduation
	switch u.Case {
	case "module":
		for _, o := range ures.Objects {
			o.Call = u.Label
		}
		uniqueNames(ures.Objects)
		g = e.graduateModule(u, mod, inputs, repo, ures, st, gopt, outputs)
	case "wrapper":
		g = e.graduateWrapper(u, inputs, repo, ures, st, opt, gopt, outputs)
	default:
		for _, o := range ures.Objects {
			o.Call = u.Label
		}
		uniqueNames(ures.Objects)
	}
	if g != nil {
		for _, call := range g.Order {
			e.Graduation.Calls[call] = g.Calls[call]
			e.Graduation.Order = append(e.Graduation.Order, call)
		}
	}

	// Addresses are the unit's: unit:address, so two units' resources
	// never mix, and the hand-off knows which state to remove them from.
	seen := map[string]bool{}
	for _, o := range ures.Objects {
		o.Source = u.Rel + ":" + o.Source
		for i, d := range o.Deps {
			o.Deps[i] = u.Rel + ":" + d
		}
		o.Obj["metadata"].(map[string]any)["annotations"].(map[string]any)[AnnAddress] = o.Source
		c := componentName(o.Call)
		if !seen[c] {
			seen[c] = true
			u.Components = append(u.Components, c)
		}
	}
	sort.Strings(u.Components)
	for _, f := range ures.Findings {
		f.Source = u.Rel + ":" + f.Source
		u.Findings = append(u.Findings, f)
	}
	e.Result.Objects = append(e.Result.Objects, ures.Objects...)
}

func (e *Estate) addDeps(u *EstateUnit, producer string) {
	for _, c := range u.ownComponents() {
		if c == producer || contains(e.DependsOn[c], producer) {
			continue
		}
		e.DependsOn[c] = append(e.DependsOn[c], producer)
	}
}

// ownComponents are the components a unit will make: its label, and for
// a wrapper one per module call.
func (u *EstateUnit) ownComponents() []string {
	out := []string{componentName(u.Label)}
	if u.Case == "wrapper" && u.ModuleDir != "" {
		for _, l := range moduleLabels(u.ModuleDir) {
			out = append(out, componentName(u.Label+"-"+l))
		}
	}
	return out
}

func contains(s []string, v string) bool {
	for _, x := range s {
		if x == v {
			return true
		}
	}
	return false
}

// resolveInputs replaces each dependency marker with the producing
// component's output expression; an input whose dependency cannot be
// resolved is left out, with a finding.
func (e *Estate) resolveInputs(u *EstateUnit, byDir map[string]*EstateUnit) map[string]cty.Value {
	deps := map[string]*TGDependency{}
	for _, d := range u.Dependencies {
		deps[d.Name] = d
	}
	out := map[string]cty.Value{}
	for _, k := range sortedCtyKeys(u.Inputs) {
		var why string
		v, err := cty.Transform(u.Inputs[k], func(p cty.Path, v cty.Value) (cty.Value, error) {
			if v.Type() != cty.String || v.IsNull() || !v.IsKnown() || !strings.Contains(v.AsString(), depMark) {
				return v, nil
			}
			s := v.AsString()
			var b strings.Builder
			for {
				i := strings.Index(s, depMark)
				if i < 0 {
					b.WriteString(s)
					break
				}
				j := strings.Index(s[i+1:], depMark)
				if j < 0 {
					return v, fmt.Errorf("a dependency output was changed by a function")
				}
				b.WriteString(s[:i])
				m := s[i+1 : i+1+j]
				parts := strings.SplitN(m, "\x1f", 2)
				expr, w := e.outputRef(deps[parts[0]], parts[0], parts[1], byDir)
				if w != "" {
					why = w
					return v, fmt.Errorf("%s", w)
				}
				b.WriteString("${" + expr + "}")
				s = s[i+1+j+1:]
			}
			return cty.StringVal(b.String()), nil
		})
		if err != nil {
			if why == "" {
				why = err.Error()
			}
			u.finding("unevaluated", "inputs."+k, "dependency output: %s. The input is left out", why)
			continue
		}
		out[k] = v
	}
	return out
}

// outputRef is the expression for dependency <name>'s output <path>.
func (e *Estate) outputRef(d *TGDependency, name, p string, byDir map[string]*EstateUnit) (string, string) {
	if d == nil {
		return "", fmt.Sprintf("dependency.%s is not declared", name)
	}
	prod := byDir[d.Dir]
	if prod == nil {
		return "", fmt.Sprintf("dependency.%s (%s) is not a unit of the estate", name, d.Dir)
	}
	switch prod.Case {
	case "module":
		return "components." + componentName(prod.Label) + ".outputs." + p, ""
	case "wrapper":
		first, rest := p, ""
		if i := strings.IndexAny(p, ".["); i >= 0 {
			first, rest = p[:i], p[i:]
		}
		o, ok := prod.outputs[first]
		switch {
		case !ok:
			return "", fmt.Sprintf("%s's module has no output %q", prod.Rel, first)
		case o.why != "":
			return "", fmt.Sprintf("dependency.%s.outputs.%s: %s", name, first, o.why)
		}
		return "components." + o.component + ".outputs." + o.path + rest, ""
	}
	return "", fmt.Sprintf("dependency.%s: %s is not converted (%s), so it has no outputs", name, prod.Rel, prod.Case)
}

// wrapperOutputs reads a wrapper's output blocks: an output that passes on
// a module call's output (module.x.y...) is that component's output.
func wrapperOutputs(dir, label string) map[string]wrapperOutput {
	out := map[string]wrapperOutput{}
	files, _ := filepath.Glob(filepath.Join(dir, "*.tf"))
	for _, f := range files {
		src, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		pf, d := hclsyntax.ParseConfig(src, f, hcl.InitialPos)
		if d.HasErrors() {
			continue
		}
		for _, b := range pf.Body.(*hclsyntax.Body).Blocks {
			if b.Type != "output" || len(b.Labels) != 1 {
				continue
			}
			a := b.Body.Attributes["value"]
			if a == nil {
				continue
			}
			text := strings.Join(strings.Fields(string(src[a.Expr.Range().Start.Byte:a.Expr.Range().End.Byte])), " ")
			st, ok := a.Expr.(*hclsyntax.ScopeTraversalExpr)
			if !ok || st.Traversal.RootName() != "module" || len(st.Traversal) < 3 {
				out[b.Labels[0]] = wrapperOutput{why: fmt.Sprintf("the wrapper's output is `%s`, not a module call's output, so no component gives it", text)}
				continue
			}
			call, ok1 := st.Traversal[1].(hcl.TraverseAttr)
			name, ok2 := st.Traversal[2].(hcl.TraverseAttr)
			if !ok1 || !ok2 {
				out[b.Labels[0]] = wrapperOutput{why: fmt.Sprintf("the wrapper's output is `%s`: a counted or looped call's output", text)}
				continue
			}
			var steps []string
			for _, s := range st.Traversal[3:] {
				switch x := s.(type) {
				case hcl.TraverseAttr:
					steps = append(steps, x.Name)
				case hcl.TraverseIndex:
					if x.Key.Type() == cty.String {
						steps = append(steps, x.Key.AsString())
					}
				}
			}
			out[b.Labels[0]] = wrapperOutput{component: componentName(label + "-" + call.Name), path: celPath(append([]string{name.Name}, steps...))}
		}
	}
	return out
}

func moduleLabels(dir string) []string {
	var out []string
	files, _ := filepath.Glob(filepath.Join(dir, "*.tf"))
	for _, f := range files {
		src, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		pf, d := hclsyntax.ParseConfig(src, f, hcl.InitialPos)
		if d.HasErrors() {
			continue
		}
		for _, b := range pf.Body.(*hclsyntax.Body).Blocks {
			if b.Type == "module" && len(b.Labels) == 1 {
				out = append(out, b.Labels[0])
			}
		}
	}
	return out
}

func variableNames(dir string) map[string]bool {
	out := map[string]bool{}
	files, _ := filepath.Glob(filepath.Join(dir, "*.tf"))
	for _, f := range files {
		src, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		pf, d := hclsyntax.ParseConfig(src, f, hcl.InitialPos)
		if d.HasErrors() {
			continue
		}
		for _, b := range pf.Body.(*hclsyntax.Body).Blocks {
			if b.Type == "variable" && len(b.Labels) == 1 {
				out[b.Labels[0]] = true
			}
		}
	}
	return out
}

type convertModule struct {
	source, version, chart string
}

// graduateModule converts a unit whose source is an open-source module as
// one call of it: a root module of one module block, its arguments the
// unit's inputs.
func (e *Estate) graduateModule(u *EstateUnit, mod *convertModule, inputs map[string]cty.Value, repo *convert.Repo, ures *Result, st *State, gopt GraduateOptions, outputs map[string]map[string]any) *Graduation {
	if mod.chart == "" {
		u.finding("gap", "terraform.source", "%s has no chart yet: nothing in the catalog ports it; the unit's resources stay one frozen Package", u.Module)
		return nil
	}
	ch, err := repo.ChartByName(path.Base(mod.chart))
	if err != nil {
		u.finding("gap", "terraform.source", "%v", err)
		return nil
	}
	f := hclwrite.NewEmptyFile()
	b := f.Body().AppendNewBlock("module", []string{u.Label}).Body()
	b.SetAttributeValue("source", cty.StringVal(mod.source))
	if mod.version != "" {
		b.SetAttributeValue("version", cty.StringVal(mod.version))
	}
	for _, k := range sortedCtyKeys(inputs) {
		if _, ok := ch.Values[k]; !ok {
			u.finding("note", "inputs."+k, "%s is not a variable of %s (the %s chart ports every one): Terraform ignores an input the module does not declare (from %s)", k, u.Module, ch.Name, u.InputFrom[k])
			continue
		}
		b.SetAttributeValue(k, inputs[k])
	}
	dir, err := os.MkdirTemp("", "offramp-unit-")
	if err != nil {
		u.finding("gap", "convert", "%v", err)
		return nil
	}
	defer os.RemoveAll(dir)
	if err := os.WriteFile(filepath.Join(dir, "main.tf"), f.Bytes(), 0o644); err != nil {
		u.finding("gap", "convert", "%v", err)
		return nil
	}
	cres, err := convert.Convert(dir, convert.Options{Repo: repo, AllowAlpha: true, Name: u.Label})
	if cres == nil {
		u.finding("gap", "convert", "%v", err)
		return nil
	}
	g := graduateConverted(cres, ures, st, gopt, outputs)
	for _, gr := range g.Calls {
		gr.Origin = u.Rel + " (" + u.Source + ")"
	}
	e.addMessages(u, cres, nil)
	return g
}

// graduateWrapper descends into a wrapper: its module calls are converted
// as in a Terraform root, with the unit's inputs as its variables.
func (e *Estate) graduateWrapper(u *EstateUnit, inputs map[string]cty.Value, repo *convert.Repo, ures *Result, st *State, opt EstateOptions, gopt GraduateOptions, outputs map[string]map[string]any) *Graduation {
	declared := variableNames(u.ModuleDir)
	f := hclwrite.NewEmptyFile()
	for _, k := range sortedCtyKeys(inputs) {
		if !declared[k] {
			u.finding("note", "inputs."+k, "the module %s does not declare %s: Terraform ignores it (from %s)", u.relDir(), k, u.InputFrom[k])
			continue
		}
		f.Body().SetAttributeValue(k, inputs[k])
	}
	tv, err := os.CreateTemp("", "offramp-unit-*.tfvars")
	if err != nil {
		u.finding("gap", "convert", "%v", err)
		return nil
	}
	defer os.Remove(tv.Name())
	if _, err := tv.Write(f.Bytes()); err != nil {
		u.finding("gap", "convert", "%v", err)
		return nil
	}
	tv.Close()

	// The calls' objects are components <unit>-<call>; the wrapper's own
	// resources are the component <unit>, each one a finding.
	for _, o := range ures.Objects {
		if o.Call == "" {
			o.Call = u.Label
			u.Findings = append(u.Findings, Finding{Source: u.Rel + ":" + o.Source, Type: o.TFType, Class: "unmapped",
				Reason: fmt.Sprintf("declared by the unit's own module (%s), not by a module call: no chart maps it, so it stays in the frozen Package of component %s", u.relDir(), componentName(u.Label))})
			continue
		}
		o.Call = u.Label + "-" + o.Call
	}
	uniqueNames(ures.Objects)

	co := convert.Options{Repo: repo, Tfvars: []string{tv.Name()}, AllowAlpha: true, Name: u.Label}
	mj := opt.ModulesJSON[u.Rel]
	if mj == "" {
		if p := filepath.Join(u.ModuleDir, ".terraform", "modules", "modules.json"); fileExists(p) {
			mj = p
		}
	}
	if mj != "" {
		if co.Sources, err = convert.ReadModulesJSON(mj); err != nil {
			u.finding("note", "modules.json", "%v", err)
		}
	}
	cres, err := convert.Convert(u.ModuleDir, co)
	if cres == nil {
		u.finding("gap", "convert", "%v", err)
		return nil
	}
	orig := append([]convert.Message(nil), cres.Messages...)
	// Rename the calls' components, their references to each other, and
	// where the converter's messages point.
	rename := map[string]string{}
	for _, c := range cres.Components {
		rename[c.Name] = componentName(u.Label + "-" + c.Name)
	}
	for _, c := range cres.Components {
		c.Name = rename[c.Name]
		for i, d := range c.DependsOn {
			if n, ok := rename[d]; ok {
				c.DependsOn[i] = n
			}
		}
		for _, o := range []convert.Ordered{c.Inputs, c.Values} {
			for i := range o {
				o[i].Value = renameRefs(o[i].Value, rename)
			}
		}
	}
	for i, m := range cres.Messages {
		if strings.HasPrefix(m.Where, "module.") {
			rest := strings.TrimPrefix(m.Where, "module.")
			call, tail := rest, ""
			if j := strings.Index(rest, "."); j >= 0 {
				call, tail = rest[:j], rest[j:]
			}
			cres.Messages[i].Where = "module." + u.Label + "-" + call + tail
		}
	}
	g := graduateConverted(cres, ures, st, gopt, outputs)
	for _, gr := range g.Calls {
		gr.Origin = u.Rel + ": module." + strings.TrimPrefix(gr.Call, u.Label+"-") + " (" + u.relDir() + ")"
	}
	e.addMessages(u, cres, orig)
	return g
}

// relDir is the wrapper's directory as people read it.
func (u *EstateUnit) relDir() string {
	if r, err := filepath.Rel(u.Dir, u.ModuleDir); err == nil {
		return filepath.ToSlash(r)
	}
	return u.ModuleDir
}

func (e *Estate) addMessages(u *EstateUnit, cres *convert.Result, orig []convert.Message) {
	ms := cres.Messages
	if orig != nil {
		ms = orig
	}
	for _, m := range ms {
		m.Where = u.Rel + ": " + m.Where
		e.Graduation.Convert.Messages = append(e.Graduation.Convert.Messages, m)
	}
	e.Graduation.Convert.Components = append(e.Graduation.Convert.Components, cres.Components...)
}

var refRE = regexp.MustCompile(`components\.([a-z0-9-]+)\.outputs`)

func renameRefs(v any, rename map[string]string) any {
	switch x := v.(type) {
	case string:
		return refRE.ReplaceAllStringFunc(x, func(s string) string {
			n := refRE.FindStringSubmatch(s)[1]
			if r, ok := rename[n]; ok {
				return "components." + r + ".outputs"
			}
			return s
		})
	case []any:
		for i := range x {
			x[i] = renameRefs(x[i], rename)
		}
	case map[string]any:
		for k := range x {
			x[k] = renameRefs(x[k], rename)
		}
	}
	return v
}

func sortedCtyKeys(m map[string]cty.Value) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

var tfrSource = regexp.MustCompile(`^tfr://([^/]*)/(.+?)(?:\?version=([^&]+))?$`)

// normalizeSource writes a Terragrunt source as a Terraform module source
// and version: tfr:///ns/name/provider//sub?version=v is the registry's
// ns/name/provider//sub at v.
func normalizeSource(s string) (string, string) {
	if m := tfrSource.FindStringSubmatch(s); m != nil {
		src := m[2]
		if m[1] != "" && m[1] != "registry.terraform.io" {
			src = m[1] + "/" + src
		}
		return src, m[3]
	}
	return s, ""
}

func isLocalSource(s string) bool {
	if strings.HasPrefix(s, "file://") {
		return true
	}
	if strings.Contains(s, "::") || strings.HasPrefix(s, "tfr:") {
		return false
	}
	return strings.HasPrefix(s, "/") || strings.HasPrefix(s, "./") || strings.HasPrefix(s, "../") || s == "." || s == ".."
}

// localSource resolves a local source against the unit; Terragrunt's
// double slash (dir//sub) names the module inside what it copies.
func localSource(unitDir, s string) string {
	s = strings.TrimPrefix(s, "file://")
	s = strings.SplitN(s, "?", 2)[0]
	s = strings.Replace(s, "//", "/", 1)
	if !filepath.IsAbs(s) {
		s = filepath.Join(unitDir, s)
	}
	return filepath.Clean(s)
}

// mappedSource applies --source-map: the part of the source before the
// double slash, if mapped, is the local directory; the part after it the
// module's directory inside.
func mappedSource(s string, m map[string]string) string {
	t := strings.TrimPrefix(s, "git::")
	start := 0
	if j := strings.Index(t, "://"); j >= 0 {
		start = j + 3
	}
	base, sub := t, ""
	if i := strings.Index(t[start:], "//"); i >= 0 {
		base, sub = t[:start+i], t[start+i+2:]
	}
	base = strings.SplitN(base, "?", 2)[0]
	sub = strings.SplitN(sub, "?", 2)[0]
	for _, cand := range []string{base, "git::" + base, strings.TrimSuffix(base, ".git")} {
		if d, ok := m[cand]; ok {
			return filepath.Join(d, sub)
		}
	}
	return ""
}

// UnitsReport is the report's section on the units: what each runs, where
// its state lives, and what Terragrunt does that the offramp did not.
func UnitsReport(e *Estate) string {
	var s strings.Builder
	s.WriteString("## Terragrunt units\n\n")
	s.WriteString("| Unit | Source | Case | Components | State read | Remote state | Generated files |\n| --- | --- | --- | --- | --- | --- | --- |\n")
	for _, u := range e.Units {
		var gens []string
		for _, g := range u.Generates {
			gens = append(gens, fmt.Sprintf("`%s` (%s, %s)", g.Path, g.Name, g.From))
		}
		rs := "none"
		if u.RemoteState != nil {
			rs = fmt.Sprintf("%s: `%s` (%s)", u.RemoteState.Backend, u.RemoteState.Location, u.RemoteState.From)
		}
		cs := strings.Join(u.Components, ", ")
		c := u.Case
		switch u.Case {
		case "module":
			c = "module " + u.Module
		case "wrapper":
			c = "wrapper " + u.relDir()
		}
		fmt.Fprintf(&s, "| `%s` | `%s` | %s | %s | `%s` | %s | %s |\n", u.Rel, u.Source, c, cs, u.StatePath, rs, strings.Join(gens, ", "))
	}
	s.WriteString("\nGenerated files are listed, not written or run: the provider and backend they configure are the Environment's and the state's location above.\n")
	return s.String()
}
