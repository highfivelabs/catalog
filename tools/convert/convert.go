// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package convert

import (
	"bytes"
	"encoding/json"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclsyntax"
	"github.com/highfivelabs/catalog/tools/upstream"
	"github.com/santhosh-tekuri/jsonschema/v6"
	"github.com/zclconf/go-cty/cty"
	"github.com/zclconf/go-cty/cty/function"
	"github.com/zclconf/go-cty/cty/function/stdlib"
	"gopkg.in/yaml.v3"
)

// Message levels.
const (
	// Gap: something in the Terraform cannot be carried; the message says why.
	Gap = "gap"
	// Invalid: what was carried breaks the chart's values.schema.json.
	Invalid = "invalid"
	// Note: carried, but worth knowing.
	Note = "note"
)

// Message is one thing the converter has to say.
type Message struct {
	Level string
	Where string // module.bucket.rpo
	Text  string
}

func (m Message) String() string {
	return fmt.Sprintf("%s: %s: %s", m.Level, m.Where, m.Text)
}

// Options for Convert.
type Options struct {
	Repo *Repo
	// Tfvars are tfvars files whose values stand for var.<name>.
	Tfvars []string
	// Name is the Template's (and the Stack's) name; default: the name of the file's directory.
	Name            string
	Team, Env       string // the Stack's team and the Instance's environment; defaults my-team and dev
	TemplateVersion string // default 1.0.0
}

// Pair is one entry of an ordered map.
type Pair struct {
	Key   string
	Value any
}

// Ordered is a map that keeps its order (the order of the arguments in the
// Terraform file).
type Ordered []Pair

// Component is one converted module block.
type Component struct {
	Name      string
	Chart     *Chart
	Inputs    Ordered // the Template component's inputs
	Values    Ordered // the Instance's values for it
	DependsOn []string
}

// Result is a conversion.
type Result struct {
	TemplateName string
	Components   []*Component
	Messages     []Message
	// Documents is the Template, the Stack and the Instance as one YAML stream.
	Documents string
}

// Gaps reports whether anything could not be carried or fails the schema.
func (r *Result) Gaps() bool {
	for _, m := range r.Messages {
		if m.Level != Note {
			return true
		}
	}
	return false
}

var marker = regexp.MustCompile("\x01module\\.([^.\x01]+)\\.([^\x01]+)\x01")

var funcs = map[string]function.Function{
	"abs": stdlib.AbsoluteFunc, "ceil": stdlib.CeilFunc, "chomp": stdlib.ChompFunc, "coalesce": stdlib.CoalesceFunc,
	"coalescelist": stdlib.CoalesceListFunc, "compact": stdlib.CompactFunc, "concat": stdlib.ConcatFunc,
	"contains": stdlib.ContainsFunc, "distinct": stdlib.DistinctFunc, "element": stdlib.ElementFunc,
	"flatten": stdlib.FlattenFunc, "floor": stdlib.FloorFunc, "format": stdlib.FormatFunc,
	"formatlist": stdlib.FormatListFunc, "indent": stdlib.IndentFunc, "join": stdlib.JoinFunc,
	"jsonencode": stdlib.JSONEncodeFunc, "keys": stdlib.KeysFunc, "length": stdlib.LengthFunc,
	"lookup": stdlib.LookupFunc, "lower": stdlib.LowerFunc, "max": stdlib.MaxFunc, "merge": stdlib.MergeFunc,
	"min": stdlib.MinFunc, "regex": stdlib.RegexFunc, "replace": stdlib.ReplaceFunc, "reverse": stdlib.ReverseListFunc,
	"setunion": stdlib.SetUnionFunc, "slice": stdlib.SliceFunc, "sort": stdlib.SortFunc, "split": stdlib.SplitFunc,
	"substr": stdlib.SubstrFunc, "title": stdlib.TitleFunc, "tobool": stdlib.MakeToFunc(cty.Bool),
	"tolist": stdlib.MakeToFunc(cty.List(cty.DynamicPseudoType)), "tomap": stdlib.MakeToFunc(cty.Map(cty.DynamicPseudoType)),
	"tonumber": stdlib.MakeToFunc(cty.Number), "toset": stdlib.MakeToFunc(cty.Set(cty.DynamicPseudoType)),
	"tostring": stdlib.MakeToFunc(cty.String), "trim": stdlib.TrimFunc, "trimprefix": stdlib.TrimPrefixFunc,
	"trimspace": stdlib.TrimSpaceFunc, "trimsuffix": stdlib.TrimSuffixFunc, "upper": stdlib.UpperFunc,
	"values": stdlib.ValuesFunc, "zipmap": stdlib.ZipmapFunc,
}

type moduleBlock struct {
	label string
	block *hclsyntax.Block
	chart *Chart
}

// Convert reads a Terraform file (module blocks, with any variable and
// locals blocks) and converts each module block that ports to a chart.
func Convert(file string, o Options) (*Result, error) {
	if o.Team == "" {
		o.Team = "my-team"
	}
	if o.Env == "" {
		o.Env = "dev"
	}
	if o.TemplateVersion == "" {
		o.TemplateVersion = "1.0.0"
	}
	src, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}
	f, diags := hclsyntax.ParseConfig(src, file, hcl.InitialPos)
	if diags.HasErrors() {
		return nil, fmt.Errorf("%s", diags.Error())
	}
	body := f.Body.(*hclsyntax.Body)
	res := &Result{}
	msg := func(level, where, format string, a ...any) {
		res.Messages = append(res.Messages, Message{level, where, fmt.Sprintf(format, a...)})
	}

	// Variables and tfvars.
	vars := map[string]cty.Value{}
	declared := map[string]bool{}
	for _, b := range body.Blocks {
		if b.Type != "variable" || len(b.Labels) != 1 {
			continue
		}
		declared[b.Labels[0]] = true
		if a, ok := b.Body.Attributes["default"]; ok {
			if v, d := a.Expr.Value(nil); !d.HasErrors() {
				vars[b.Labels[0]] = v
			}
		}
	}
	for _, tf := range o.Tfvars {
		vals, err := readTfvars(tf)
		if err != nil {
			return nil, err
		}
		for k, v := range vals {
			vars[k] = v
			if !declared[k] {
				msg(Note, "var."+k, "%s sets %s, which %s does not declare", filepath.Base(tf), k, filepath.Base(file))
			}
		}
	}
	locals, localVar := evalLocals(body, vars)

	// Module blocks and their charts.
	var mods []*moduleBlock
	byLabel := map[string]*moduleBlock{}
	for _, b := range body.Blocks {
		if b.Type != "module" || len(b.Labels) != 1 {
			continue
		}
		label := b.Labels[0]
		mb := &moduleBlock{label: label, block: b}
		srcAttr, ok := b.Body.Attributes["source"]
		if !ok {
			msg(Gap, "module."+label, "no source argument")
			continue
		}
		sv, d := srcAttr.Expr.Value(nil)
		if d.HasErrors() || sv.Type() != cty.String {
			msg(Gap, "module."+label, "source must be a literal string")
			continue
		}
		m, ref, err := o.Repo.Resolve(sv.AsString())
		if err != nil {
			msg(Gap, "module."+label, "%v", err)
			continue
		}
		if m.Chart == "" {
			msg(Gap, "module."+label, "%s (%s) has no chart yet: nothing in the catalog ports it (docs/coverage/modules.csv has its status)", m.ID, m.Version)
			continue
		}
		mb.chart, err = o.Repo.loadChart(m)
		if err != nil {
			return nil, err
		}
		if ref != "" && ref != m.Version {
			msg(Note, "module."+label, "the source pins %s; the chart was ported from %s (upstream.yaml): changes between the two are not in the chart", ref, m.Version)
		}
		if !validName(label) {
			msg(Note, "module."+label, "a component name is an RFC 1123 label: using %q", dns(label))
		}
		mods = append(mods, mb)
		byLabel[label] = mb
	}
	if len(mods) == 0 {
		return res, fmt.Errorf("%s: no module block ports to a chart (messages above)", file)
	}
	// The Template is named for the Terraform root module's directory.
	res.TemplateName = o.Name
	if res.TemplateName == "" {
		if abs, err := filepath.Abs(file); err == nil {
			res.TemplateName = dns(filepath.Base(filepath.Dir(abs)))
		}
		if !validName(res.TemplateName) {
			res.TemplateName = dns(mods[0].label)
		}
	}

	for _, mb := range mods {
		c := &Component{Name: dns(mb.label), Chart: mb.chart}
		res.Components = append(res.Components, c)
		where := "module." + mb.label
		attrs := sortedAttrs(mb.block.Body.Attributes)
		for _, a := range attrs {
			name := a.Name
			w := where + "." + name
			switch name {
			case "source":
				continue
			case "version":
				msg(Note, w, "the version argument selects a registry release: the chart is ported from %s", mb.chart.Module.Version)
				continue
			case "providers":
				msg(Note, w, "dropped: the cloud account comes from the Environment and Target a component lands in, not from a provider argument")
				continue
			case "count", "for_each":
				msg(Gap, w, "Bundt components are not looped: make one component (or one Instance) for each item; the Template has no %s", name)
				continue
			case "depends_on":
				for _, t := range a.Expr.Variables() {
					if len(t) >= 2 && t.RootName() == "module" {
						if at, ok := t[1].(hcl.TraverseAttr); ok && byLabel[at.Name] != nil {
							c.DependsOn = append(c.DependsOn, dns(at.Name))
							continue
						}
					}
					msg(Gap, w, "depends_on %s: only another converted module block can be a dependsOn", traversalString(t))
				}
				continue
			}
			ref, ok := resolveRefs(a, vars, locals, localVar, byLabel, w, msg)
			if !ok {
				continue
			}
			val, d := a.Expr.Value(evalContext(vars, locals, byLabel))
			if d.HasErrors() {
				msg(Gap, w, "cannot evaluate: %s", firstDiag(d))
				continue
			}
			goVal, err := toGo(val)
			if err != nil {
				msg(Gap, w, "cannot carry the value: %v", err)
				continue
			}
			goVal = expandMarkers(goVal)
			if _, ok := mb.chart.Values[name]; !ok {
				msg(Gap, w, "%s is not a variable of the %s chart (%s at %s)", name, mb.chart.Name, mb.chart.Module.ID, mb.chart.Module.Version)
				continue
			}
			if r, refused := mb.chart.Refused[name]; refused {
				if !checkRefused(r, goVal, w, allowAlpha(c, mb.chart, attrs, vars, locals, byLabel), msg) {
					continue
				}
			}
			if ref.usesVar {
				c.Values = append(c.Values, Pair{name, goVal})
			} else {
				c.Inputs = append(c.Inputs, Pair{name, goVal})
			}
		}
		validate(c, msg, where)
	}
	res.Documents = render(res, o)
	return res, nil
}

// refs describes what an argument's expression refers to.
type refs struct{ usesVar bool }

// resolveRefs checks every reference an argument makes; it reports the ones
// that cannot be carried and returns false.
func resolveRefs(a *hclsyntax.Attribute, vars, locals map[string]cty.Value, localVar map[string]bool, byLabel map[string]*moduleBlock, where string, msg func(level, where, format string, a ...any)) (refs, bool) {
	var r refs
	ok := true
	for _, t := range a.Expr.Variables() {
		switch t.RootName() {
		case "var":
			r.usesVar = true
			if len(t) < 2 {
				continue
			}
			name := t[1].(hcl.TraverseAttr).Name
			if _, have := vars[name]; !have {
				msg(Gap, where, "var.%s has no value: pass the tfvars file (--tfvars) or give the variable a default", name)
				ok = false
			}
		case "local":
			if len(t) >= 2 {
				name := t[1].(hcl.TraverseAttr).Name
				if _, have := locals[name]; !have {
					msg(Gap, where, "local.%s could not be evaluated (it depends on something outside this file)", name)
					ok = false
				}
			}
			// A local that uses var makes the argument per-environment too.
			if len(t) >= 2 {
				r.usesVar = r.usesVar || localVar[t[1].(hcl.TraverseAttr).Name]
			}
		case "module":
			if len(t) < 3 {
				msg(Gap, where, "module output reference %s is incomplete", traversalString(t))
				ok = false
				continue
			}
			label := t[1].(hcl.TraverseAttr).Name
			out, isAttr := t[2].(hcl.TraverseAttr)
			target := byLabel[label]
			switch {
			case target == nil:
				msg(Gap, where, "%s: module %q is not a module block of this file that ports to a chart, so it is not a component", traversalString(t), label)
				ok = false
			case !isAttr || !contains(target.chart.Outputs, out.Name):
				msg(Gap, where, "%s: the %s chart provides the outputs %s (fabric's whole-object outputs are not outputs)", traversalString(t), target.chart.Name, strings.Join(target.chart.Outputs, ", "))
				ok = false
			case len(t) > 3:
				msg(Gap, where, "%s: indexing into a module output cannot be written as a component output expression", traversalString(t))
				ok = false
			}
		default:
			msg(Gap, where, "references %s, which has no equivalent in a Bundt document (a resource, a data source or path.*): write its value, or take it from another component's outputs", traversalString(t))
			ok = false
		}
	}
	return r, ok
}

func contains(s []string, v string) bool {
	for _, x := range s {
		if x == v {
			return true
		}
	}
	return false
}

func traversalString(t hcl.Traversal) string {
	var b strings.Builder
	for i, s := range t {
		switch s := s.(type) {
		case hcl.TraverseRoot:
			b.WriteString(s.Name)
		case hcl.TraverseAttr:
			b.WriteString("." + s.Name)
		case hcl.TraverseIndex:
			if s.Key.Type() == cty.String {
				fmt.Fprintf(&b, "[%q]", s.Key.AsString())
			} else {
				b.WriteString("[…]")
			}
		default:
			if i > 0 {
				b.WriteString("[…]")
			}
		}
	}
	return b.String()
}

func firstDiag(d hcl.Diagnostics) string {
	for _, x := range d {
		if x.Severity == hcl.DiagError {
			s := x.Summary
			if x.Detail != "" {
				s += ": " + x.Detail
			}
			return s
		}
	}
	return d.Error()
}

func sortedAttrs(m hclsyntax.Attributes) []*hclsyntax.Attribute {
	var out []*hclsyntax.Attribute
	for _, a := range m {
		out = append(out, a)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].SrcRange.Start.Byte < out[j].SrcRange.Start.Byte })
	return out
}

func evalContext(vars, locals map[string]cty.Value, byLabel map[string]*moduleBlock) *hcl.EvalContext {
	mods := map[string]cty.Value{}
	for label, mb := range byLabel {
		outs := map[string]cty.Value{}
		for _, o := range mb.chart.Outputs {
			outs[o] = cty.StringVal("\x01module." + dns(label) + "." + o + "\x01")
		}
		mods[label] = cty.ObjectVal(outs)
	}
	return &hcl.EvalContext{
		Variables: map[string]cty.Value{"var": objectOf(vars), "local": objectOf(locals), "module": objectOf(mods)},
		Functions: funcs,
	}
}

func objectOf(m map[string]cty.Value) cty.Value {
	if len(m) == 0 {
		return cty.EmptyObjectVal
	}
	return cty.ObjectVal(m)
}

// evalLocals evaluates every locals attribute that can be evaluated from
// variables and other locals. The second result says which of them depend
// on a variable (so an argument using them is per-environment).
func evalLocals(body *hclsyntax.Body, vars map[string]cty.Value) (map[string]cty.Value, map[string]bool) {
	locals := map[string]cty.Value{}
	usesVar := map[string]bool{}
	pending := map[string]*hclsyntax.Attribute{}
	for _, b := range body.Blocks {
		if b.Type == "locals" {
			for n, a := range b.Body.Attributes {
				pending[n] = a
			}
		}
	}
	for progress := true; progress && len(pending) > 0; {
		progress = false
		names := make([]string, 0, len(pending))
		for n := range pending {
			names = append(names, n)
		}
		sort.Strings(names)
		for _, n := range names {
			a := pending[n]
			ctx := &hcl.EvalContext{Variables: map[string]cty.Value{"var": objectOf(vars), "local": objectOf(locals)}, Functions: funcs}
			if v, d := a.Expr.Value(ctx); !d.HasErrors() {
				locals[n] = v
				for _, t := range a.Expr.Variables() {
					switch t.RootName() {
					case "var":
						usesVar[n] = true
					case "local":
						if len(t) >= 2 && usesVar[t[1].(hcl.TraverseAttr).Name] {
							usesVar[n] = true
						}
					}
				}
				delete(pending, n)
				progress = true
			}
		}
	}
	return locals, usesVar
}

func readTfvars(path string) (map[string]cty.Value, error) {
	src, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	f, diags := hclsyntax.ParseConfig(src, path, hcl.InitialPos)
	if diags.HasErrors() {
		return nil, fmt.Errorf("%s", diags.Error())
	}
	out := map[string]cty.Value{}
	for n, a := range f.Body.(*hclsyntax.Body).Attributes {
		v, d := a.Expr.Value(&hcl.EvalContext{Functions: funcs})
		if d.HasErrors() {
			return nil, fmt.Errorf("%s: %s: %s", path, n, firstDiag(d))
		}
		out[n] = v
	}
	return out, nil
}

// ConvertTfvars converts a tfvars file for one chart into the values that
// chart takes (a values file, which is a Template component's inputs or an
// Instance's values), checking each against the chart.
func ConvertTfvars(file, chartName string, o Options) (*Result, error) {
	ch, err := o.Repo.ChartByName(chartName)
	if err != nil {
		return nil, err
	}
	src, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}
	f, diags := hclsyntax.ParseConfig(src, file, hcl.InitialPos)
	if diags.HasErrors() {
		return nil, fmt.Errorf("%s", diags.Error())
	}
	res := &Result{TemplateName: chartName}
	msg := func(level, where, format string, a ...any) {
		res.Messages = append(res.Messages, Message{level, where, fmt.Sprintf(format, a...)})
	}
	c := &Component{Name: chartName, Chart: ch}
	for _, a := range sortedAttrs(f.Body.(*hclsyntax.Body).Attributes) {
		w := a.Name
		v, d := a.Expr.Value(&hcl.EvalContext{Functions: funcs})
		if d.HasErrors() {
			msg(Gap, w, "cannot evaluate: %s", firstDiag(d))
			continue
		}
		goVal, err := toGo(v)
		if err != nil {
			msg(Gap, w, "cannot carry the value: %v", err)
			continue
		}
		if _, ok := ch.Values[a.Name]; !ok {
			msg(Gap, w, "%s is not a variable of the %s chart (%s at %s)", a.Name, ch.Name, ch.Module.ID, ch.Module.Version)
			continue
		}
		if r, refused := ch.Refused[a.Name]; refused {
			if !checkRefused(r, goVal, w, tfvarsAllowAlpha(f.Body.(*hclsyntax.Body)), msg) {
				continue
			}
		}
		c.Inputs = append(c.Inputs, Pair{a.Name, goVal})
	}
	validate(c, msg, chartName)
	res.Components = []*Component{c}
	var b bytes.Buffer
	enc := yaml.NewEncoder(&b)
	enc.SetIndent(2)
	if err := enc.Encode(orderedNode(c.Inputs)); err != nil {
		return nil, err
	}
	res.Documents = b.String()
	return res, nil
}

// toGo converts a value to JSON-compatible Go values.
func toGo(v cty.Value) (any, error) {
	if !v.IsWhollyKnown() {
		return nil, fmt.Errorf("the value is not known")
	}
	if v.IsNull() {
		return nil, nil
	}
	t := v.Type()
	switch {
	case t == cty.String:
		return v.AsString(), nil
	case t == cty.Bool:
		return v.True(), nil
	case t == cty.Number:
		bf := v.AsBigFloat()
		if bf.IsInt() {
			i, acc := bf.Int64()
			if acc == big.Exact {
				return i, nil
			}
		}
		f, _ := bf.Float64()
		return f, nil
	case t.IsListType() || t.IsSetType() || t.IsTupleType():
		out := []any{}
		for it := v.ElementIterator(); it.Next(); {
			_, e := it.Element()
			g, err := toGo(e)
			if err != nil {
				return nil, err
			}
			out = append(out, g)
		}
		return out, nil
	case t.IsMapType() || t.IsObjectType():
		out := map[string]any{}
		for it := v.ElementIterator(); it.Next(); {
			k, e := it.Element()
			key := k.AsString()
			if marker.MatchString(key) {
				return nil, fmt.Errorf("a map key holds a module output: Bundt never evaluates a map's keys, so a key cannot be a ${...} expression (write the value, or use an additive binding whose principal is a value)")
			}
			g, err := toGo(e)
			if err != nil {
				return nil, err
			}
			out[key] = g
		}
		return out, nil
	}
	return nil, fmt.Errorf("a value of type %s", t.FriendlyName())
}

// expandMarkers writes module outputs as Bundt expressions.
func expandMarkers(v any) any {
	switch x := v.(type) {
	case string:
		return marker.ReplaceAllString(x, "${components.$1.outputs.$2}")
	case []any:
		for i := range x {
			x[i] = expandMarkers(x[i])
		}
		return x
	case map[string]any:
		for k, e := range x {
			x[k] = expandMarkers(e)
		}
		return x
	}
	return v
}

// isEmpty is Helm's notion of empty: the chart's refusals fire on any other value.
func isEmpty(v any) bool {
	switch x := v.(type) {
	case nil:
		return true
	case string:
		return x == ""
	case bool:
		return !x
	case int64:
		return x == 0
	case float64:
		return x == 0
	case []any:
		return len(x) == 0
	case map[string]any:
		return len(x) == 0
	}
	return false
}

var label63 = regexp.MustCompile(`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`)

func validName(s string) bool { return len(s) <= 63 && label63.MatchString(s) }

// dns makes a Terraform label an RFC 1123 label.
func dns(s string) string {
	s = strings.ToLower(strings.ReplaceAll(s, "_", "-"))
	return strings.Trim(s, "-")
}

// validate checks the component's effective values (the chart's defaults,
// then inputs, then values) against the chart's values.schema.json.
func validate(c *Component, msg func(level, where, format string, a ...any), where string) {
	if c.Chart.SchemaPath == "" {
		msg(Note, where, "the %s chart has no values.schema.json: only the variable names were checked", c.Chart.Name)
		return
	}
	eff := map[string]any{}
	for k, v := range c.Chart.Values {
		eff[k] = jsonable(v)
	}
	for _, p := range append(append(Ordered{}, c.Inputs...), c.Values...) {
		eff[p.Key] = jsonable(p.Value)
	}
	data, err := json.Marshal(eff)
	if err != nil {
		msg(Invalid, where, "cannot encode the values: %v", err)
		return
	}
	inst, err := jsonschema.UnmarshalJSON(bytes.NewReader(data))
	if err != nil {
		msg(Invalid, where, "cannot decode the values: %v", err)
		return
	}
	comp := jsonschema.NewCompiler()
	abs, _ := filepath.Abs(c.Chart.SchemaPath)
	sch, err := comp.Compile("file://" + filepath.ToSlash(abs))
	if err != nil {
		msg(Invalid, where, "cannot compile %s: %v", c.Chart.SchemaPath, err)
		return
	}
	if err := sch.Validate(inst); err != nil {
		ve, ok := err.(*jsonschema.ValidationError)
		if !ok {
			msg(Invalid, where, "%v", err)
			return
		}
		seen := map[string]bool{}
		var walk func(u jsonschema.OutputUnit)
		walk = func(u jsonschema.OutputUnit) {
			if u.Error != nil && len(u.Errors) == 0 {
				loc := strings.TrimPrefix(u.InstanceLocation, "/")
				if loc == "" {
					loc = "(values)"
				}
				line := fmt.Sprintf("%s: %s", strings.ReplaceAll(loc, "/", "."), u.Error.String())
				if !seen[line] {
					seen[line] = true
					msg(Invalid, where+"."+strings.Split(loc, "/")[0], "does not match the chart's values.schema.json at %s", line)
				}
			}
			for _, e := range u.Errors {
				walk(e)
			}
		}
		walk(*ve.BasicOutput())
	}
}

// jsonable makes yaml-decoded values JSON-encodable (yaml.v3 gives
// map[string]any already; ints stay ints).
func jsonable(v any) any {
	switch x := v.(type) {
	case map[string]any:
		out := map[string]any{}
		for k, e := range x {
			out[k] = jsonable(e)
		}
		return out
	case map[any]any:
		out := map[string]any{}
		for k, e := range x {
			out[fmt.Sprint(k)] = jsonable(e)
		}
		return out
	case []any:
		out := make([]any, len(x))
		for i, e := range x {
			out[i] = jsonable(e)
		}
		return out
	}
	return v
}

// checkRefused applies a chart's refusal of a variable to a value. It
// returns false when the value cannot be carried at all; for a variable the
// chart accepts in part it says what the chart will refuse and still
// carries the value (the plan then shows the chart's own refusal).
func checkRefused(r upstream.Refused, v any, where string, allowAlpha bool, msg func(level, where, format string, a ...any)) bool {
	if isEmpty(v) {
		return true
	}
	if !r.Partial {
		msg(Gap, where, "refused by the chart (%s): %s", r.Kind, r.Reason)
		return false
	}
	said := false
	if r.NeedsAllowAlpha && !allowAlpha {
		msg(Gap, where, "needs an alpha Config Connector kind: add allow_alpha: true to the component's inputs to accept that its schema may change (%s)", r.Reason)
		said = true
	}
	for _, f := range r.Fields {
		for _, p := range findField(v, f, "") {
			msg(Gap, where+p, "refused by the chart (%s): %s", r.Kind, r.Reason)
			said = true
		}
	}
	if !allowAlpha {
		for _, f := range r.AlphaFields {
			for _, p := range findField(v, f, "") {
				msg(Gap, where+p, "needs an alpha Config Connector kind: add allow_alpha: true to the component's inputs to accept that its schema may change (%s)", r.Reason)
				said = true
			}
		}
	}
	if s, ok := v.(string); ok {
		for _, bad := range r.Values {
			if s == bad {
				msg(Gap, where, "refused by the chart (%s): %q: %s", r.Kind, s, r.Reason)
				said = true
			}
		}
	}
	if !said && len(r.Fields) == 0 && len(r.AlphaFields) == 0 && len(r.Values) == 0 && !r.NeedsAllowAlpha {
		msg(Note, where, "accepted in part (%s): %s", r.Kind, r.Reason)
	}
	return true
}

// findField lists the paths (".a[0].field") at which the attribute name has
// a non-empty value anywhere in v.
func findField(v any, name, path string) []string {
	var out []string
	switch x := v.(type) {
	case map[string]any:
		keys := make([]string, 0, len(x))
		for k := range x {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			if k == name && !isEmpty(x[k]) {
				out = append(out, path+"."+k)
			}
			out = append(out, findField(x[k], name, path+"."+k)...)
		}
	case []any:
		for i, e := range x {
			out = append(out, findField(e, name, fmt.Sprintf("%s[%d]", path, i))...)
		}
	}
	return out
}

// allowAlpha reports whether the module block sets allow_alpha to true.
func allowAlpha(c *Component, ch *Chart, attrs []*hclsyntax.Attribute, vars, locals map[string]cty.Value, byLabel map[string]*moduleBlock) bool {
	for _, a := range attrs {
		if a.Name == "allow_alpha" {
			v, d := a.Expr.Value(evalContext(vars, locals, byLabel))
			return !d.HasErrors() && v.Type() == cty.Bool && v.IsKnown() && v.True()
		}
	}
	return false
}

func tfvarsAllowAlpha(body *hclsyntax.Body) bool {
	a, ok := body.Attributes["allow_alpha"]
	if !ok {
		return false
	}
	v, d := a.Expr.Value(nil)
	return !d.HasErrors() && v.Type() == cty.Bool && v.True()
}
