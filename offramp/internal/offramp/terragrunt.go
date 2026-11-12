// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package offramp

import (
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclsyntax"
	ctyyaml "github.com/zclconf/go-cty-yaml"
	"github.com/zclconf/go-cty/cty"
	"github.com/zclconf/go-cty/cty/function"
	"github.com/zclconf/go-cty/cty/function/stdlib"
)

// Reading a Terragrunt estate statically. Terragrunt is never run, and
// neither is Terraform: each unit's terragrunt.hcl is parsed with HCL and
// evaluated with the Terragrunt functions that need only the files
// (find_in_parent_folders, read_terragrunt_config, path_relative_to_include
// and the like) and Terraform's functions that need nothing else. An
// expression that needs anything more (run_cmd, a cloud call, an
// environment variable that is not set, a function of a dependency's
// output) is not guessed: the value is left out and a finding names the
// expression and why.

// TerragruntOptions steer reading an estate.
type TerragruntOptions struct {
	// Env are the environment variables get_env reads. A get_env of a
	// variable not here takes its default, and a note says so.
	Env map[string]string
	// SourceMap maps a remote source (its URL up to the double slash, as
	// Terragrunt's --source-map takes it) to a local directory, for a
	// team's own module that lives in another repository.
	SourceMap map[string]string
}

// TGUnit is one Terragrunt unit: a directory with a terragrunt.hcl, run
// as one Terraform root module with its own state.
type TGUnit struct {
	// Dir is the unit's directory (absolute); Rel is the same relative to
	// the estate, with forward slashes; Label is the component name it
	// gives (Rel, sanitized).
	Dir, Rel, Label string
	// Source is terraform.source as evaluated; empty when the unit runs
	// the .tf files of its own directory.
	Source string
	// Inputs are the inputs that evaluated, includes merged. A value that
	// reads a dependency's output holds a marker (depMarker) until
	// ResolveDependencies replaces it.
	Inputs map[string]cty.Value
	// InputFrom says which file set each input (the unit's own, or an
	// included one), for the report.
	InputFrom map[string]string
	// Dependencies are the dependency blocks; DependsOn the
	// dependencies { paths } (absolute directories).
	Dependencies []*TGDependency
	DependsOn    []string
	RemoteState  *TGRemoteState
	Generates    []TGGenerate
	Includes     []string
	Skip         bool
	Findings     []Finding
}

// TGDependency is a dependency block: another unit whose outputs this one
// reads.
type TGDependency struct {
	Name string
	// Dir is config_path, resolved to the unit's directory.
	Dir string
	// Mock is set when the block has mock_outputs, which the offramp never
	// uses: the value comes from the producing component.
	Mock bool
}

// TGRemoteState is where the unit's state lives.
type TGRemoteState struct {
	Backend string
	Config  map[string]any
	// Location is where the state object is, as a URL when the backend
	// has one (gs://bucket/prefix/default.tfstate).
	Location string
	From     string // the file that set it
}

// TGGenerate is a generate block (or remote_state's generate): a file
// Terragrunt writes into the unit's working directory before Terraform
// runs. The offramp does not write or run it; it lists it.
type TGGenerate struct {
	Name, Path, From string
}

// depMarker is the value a dependency output takes while the inputs are
// evaluated: replaced by the producing component's output expression.
const depMark = "\x02"

func depMarker(dep, path string) string { return depMark + dep + "\x1f" + path + depMark }

// ReadEstate finds the units under dir (every terragrunt.hcl that no other
// unit includes, .terragrunt-cache left out) and reads each.
func ReadEstate(dir string, opt TerragruntOptions) ([]*TGUnit, error) {
	root, err := filepath.Abs(dir)
	if err != nil {
		return nil, err
	}
	var configs []string
	err = filepath.WalkDir(root, func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() && (d.Name() == ".terragrunt-cache" || d.Name() == ".terraform" || d.Name() == ".git") {
			return filepath.SkipDir
		}
		if !d.IsDir() && d.Name() == "terragrunt.hcl" {
			configs = append(configs, p)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Strings(configs)
	r := &tgReader{opt: opt, cache: map[string]cty.Value{}}
	var units []*TGUnit
	included := map[string]bool{}
	for _, c := range configs {
		u, err := r.readUnit(root, c)
		if err != nil {
			return nil, err
		}
		for _, inc := range u.Includes {
			included[inc] = true
		}
		units = append(units, u)
	}
	var out []*TGUnit
	for _, u := range units {
		if included[filepath.Join(u.Dir, "terragrunt.hcl")] {
			continue // a root configuration named terragrunt.hcl
		}
		out = append(out, u)
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("%s: no Terragrunt unit (terragrunt.hcl) found", dir)
	}
	return out, nil
}

type tgReader struct {
	opt   TerragruntOptions
	cache map[string]cty.Value // read_terragrunt_config results by path
	depth int
}

// tgFile is one parsed configuration file.
type tgFile struct {
	path string
	src  []byte
	body *hclsyntax.Body
}

func parseTG(path string) (*tgFile, error) {
	src, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	f, d := hclsyntax.ParseConfig(src, path, hcl.InitialPos)
	if d.HasErrors() {
		return nil, fmt.Errorf("%s", d.Error())
	}
	return &tgFile{path: path, src: src, body: f.Body.(*hclsyntax.Body)}, nil
}

// text gives an expression's source, for a finding.
func (f *tgFile) text(r hcl.Range) string {
	if r.Start.Byte < 0 || r.End.Byte > len(f.src) || r.Start.Byte >= r.End.Byte {
		return ""
	}
	return strings.Join(strings.Fields(string(f.src[r.Start.Byte:r.End.Byte])), " ")
}

// tgScope is what a file's expressions are evaluated in: the unit being
// read (Terragrunt evaluates an included file in the including unit's
// context) and the file itself.
type tgScope struct {
	r       *tgReader
	unitDir string // get_terragrunt_dir()
	file    *tgFile
	// includes are the unit's include blocks by label; parent is the
	// include through which this file is read (nil for the unit's own).
	includes map[string]string
	parent   string
	vars     map[string]cty.Value
	// failedLocals says why each local that did not evaluate did not.
	failedLocals map[string]string
	findings     *[]Finding
	where        string // for findings: the unit's relative path
}

// errStatic is a function that needs more than the files.
type errStatic struct{ why string }

func (e errStatic) Error() string { return e.why }

func (s *tgScope) ctx() *hcl.EvalContext {
	return &hcl.EvalContext{Variables: s.vars, Functions: s.functions()}
}

func (s *tgScope) rel(p string) string {
	if p == "" {
		return ""
	}
	if r, err := filepath.Rel(s.unitDir, p); err == nil {
		return filepath.ToSlash(r)
	}
	return p
}

func (s *tgScope) note(class, typ, format string, a ...any) {
	*s.findings = append(*s.findings, Finding{Source: s.where, Type: typ, Class: class, Reason: fmt.Sprintf(format, a...)})
}

func (s *tgScope) fileRel() string {
	return s.rel(s.file.path)
}

// readUnit reads one unit's terragrunt.hcl and what it includes.
func (r *tgReader) readUnit(estate, config string) (*TGUnit, error) {
	f, err := parseTG(config)
	if err != nil {
		return nil, err
	}
	dir := filepath.Dir(config)
	rel, _ := filepath.Rel(estate, dir)
	rel = filepath.ToSlash(rel)
	u := &TGUnit{Dir: dir, Rel: rel, Label: sanitize(strings.ReplaceAll(rel, "/", "-")), Inputs: map[string]cty.Value{}, InputFrom: map[string]string{}}
	if rel == "." {
		u.Label = sanitize(filepath.Base(dir))
	}
	s := &tgScope{r: r, unitDir: dir, file: f, includes: map[string]string{}, findings: &u.Findings, where: rel, vars: map[string]cty.Value{}}

	// Includes first: their paths take functions only.
	type inc struct {
		label, path, strategy string
		expose                bool
	}
	var incs []inc
	for _, b := range f.body.Blocks {
		if b.Type != "include" {
			continue
		}
		label := ""
		if len(b.Labels) > 0 {
			label = b.Labels[0]
		}
		a := b.Body.Attributes["path"]
		if a == nil {
			s.note("unevaluated", "include", "include %q has no path", label)
			continue
		}
		v, d := a.Expr.Value(s.ctx())
		if d.HasErrors() || v.Type() != cty.String {
			s.note("unevaluated", "include", "include %q: path `%s` does not evaluate statically: %s; nothing it sets is read", label, f.text(a.Expr.Range()), firstDiag(d))
			continue
		}
		p := v.AsString()
		if !filepath.IsAbs(p) {
			p = filepath.Join(dir, p)
		}
		i := inc{label: label, path: filepath.Clean(p), strategy: "shallow"}
		if a := b.Body.Attributes["expose"]; a != nil {
			if v, d := a.Expr.Value(nil); !d.HasErrors() && v.Type() == cty.Bool {
				i.expose = v.True()
			}
		}
		if a := b.Body.Attributes["merge_strategy"]; a != nil {
			if v, d := a.Expr.Value(nil); !d.HasErrors() && v.Type() == cty.String {
				i.strategy = v.AsString()
			}
		}
		incs = append(incs, i)
		s.includes[label] = i.path
		u.Includes = append(u.Includes, i.path)
	}

	// Each included file, evaluated in this unit's context.
	type parentCfg struct {
		inc
		scope *tgScope
	}
	var parents []parentCfg
	exposed := map[string]cty.Value{}
	for _, i := range incs {
		pf, err := parseTG(i.path)
		if err != nil {
			s.note("unevaluated", "include", "include %q: %v", i.label, err)
			continue
		}
		ps := &tgScope{r: r, unitDir: dir, file: pf, includes: s.includes, parent: i.label, findings: &u.Findings, where: rel, vars: map[string]cty.Value{}}
		for _, b := range pf.body.Blocks {
			if b.Type == "include" {
				ps.note("unevaluated", "include", "%s includes another file; Terragrunt reads one level of include, so the offramp does not follow it", ps.fileRel())
			}
		}
		ps.evalLocals()
		parents = append(parents, parentCfg{i, ps})
		if i.expose {
			exposed[i.label] = ps.exposed()
		}
	}
	if len(exposed) > 0 {
		s.vars["include"] = cty.ObjectVal(exposed)
	}
	s.evalLocals()

	// Dependencies: the unit's own, then any an include adds.
	deps := map[string]*TGDependency{}
	var depOrder []string
	readDeps := func(sc *tgScope) {
		for _, b := range sc.file.body.Blocks {
			switch {
			case b.Type == "dependency" && len(b.Labels) == 1:
				a := b.Body.Attributes["config_path"]
				if a == nil {
					continue
				}
				v, d := a.Expr.Value(sc.ctx())
				if d.HasErrors() || v.Type() != cty.String {
					sc.note("unevaluated", "dependency", "dependency %q: config_path `%s` does not evaluate statically: %s", b.Labels[0], sc.file.text(a.Expr.Range()), firstDiag(d))
					continue
				}
				p := v.AsString()
				if !filepath.IsAbs(p) {
					p = filepath.Join(dir, p)
				}
				if _, ok := deps[b.Labels[0]]; !ok {
					depOrder = append(depOrder, b.Labels[0])
				}
				deps[b.Labels[0]] = &TGDependency{Name: b.Labels[0], Dir: filepath.Clean(p), Mock: b.Body.Attributes["mock_outputs"] != nil}
			case b.Type == "dependencies":
				if a := b.Body.Attributes["paths"]; a != nil {
					v, d := a.Expr.Value(sc.ctx())
					if d.HasErrors() || !(v.Type().IsTupleType() || v.Type().IsListType()) {
						sc.note("unevaluated", "dependencies", "dependencies.paths `%s` does not evaluate statically: %s", sc.file.text(a.Expr.Range()), firstDiag(d))
						continue
					}
					for it := v.ElementIterator(); it.Next(); {
						_, e := it.Element()
						if e.Type() == cty.String {
							p := e.AsString()
							if !filepath.IsAbs(p) {
								p = filepath.Join(dir, p)
							}
							u.DependsOn = append(u.DependsOn, filepath.Clean(p))
						}
					}
				}
			}
		}
	}
	readDeps(s)
	for _, p := range parents {
		if p.strategy != "no_merge" {
			readDeps(p.scope)
		}
	}
	for _, n := range depOrder {
		u.Dependencies = append(u.Dependencies, deps[n])
		if deps[n].Mock {
			s.note("note", "dependency", "dependency %q has mock_outputs: never used; the value comes from the output of the component made from %s", n, s.rel(deps[n].Dir))
		}
	}

	// The rest, parents first so the unit's own settings win.
	scopes := []*tgScope{}
	strategies := []string{}
	for _, p := range parents {
		if p.strategy == "no_merge" {
			continue
		}
		scopes = append(scopes, p.scope)
		strategies = append(strategies, p.strategy)
	}
	scopes = append(scopes, s)
	strategies = append(strategies, "shallow")
	for i, sc := range scopes {
		sc.vars["dependency"] = dependencyObject(sc.file.body, deps)
		if inc, ok := s.vars["include"]; ok {
			sc.vars["include"] = inc
		}
		sc.readRest(u, strategies[i])
	}
	return u, nil
}

// exposed is what include.<label> gives an including file: the included
// file's locals and inputs.
func (s *tgScope) exposed() cty.Value {
	m := map[string]cty.Value{}
	if l, ok := s.vars["local"]; ok {
		m["locals"] = l
	} else {
		m["locals"] = cty.EmptyObjectVal
	}
	if a := s.attr("inputs"); a != nil {
		if v, d := a.Expr.Value(s.ctx()); !d.HasErrors() {
			m["inputs"] = v
		}
	}
	return cty.ObjectVal(m)
}

func (s *tgScope) attr(name string) *hclsyntax.Attribute { return s.file.body.Attributes[name] }

// evalLocals evaluates the locals blocks, each local once those it reads
// are known; a local that cannot be evaluated is left out and remembered.
func (s *tgScope) evalLocals() {
	s.failedLocals = map[string]string{}
	pending := map[string]*hclsyntax.Attribute{}
	for _, b := range s.file.body.Blocks {
		if b.Type == "locals" {
			for n, a := range b.Body.Attributes {
				pending[n] = a
			}
		}
	}
	done := map[string]cty.Value{}
	for len(pending) > 0 {
		progress := false
		for _, n := range sortedAttrNames(pending) {
			a := pending[n]
			ready, blocked := true, ""
			for _, t := range a.Expr.Variables() {
				if t.RootName() != "local" || len(t) < 2 {
					continue
				}
				ref, ok := t[1].(hcl.TraverseAttr)
				if !ok {
					continue
				}
				if why, failed := s.failedLocals[ref.Name]; failed {
					blocked = fmt.Sprintf("it reads local.%s, which %s", ref.Name, why)
					break
				}
				if _, ok := done[ref.Name]; !ok {
					if _, p := pending[ref.Name]; p {
						ready = false
					}
				}
			}
			if blocked != "" {
				s.failedLocals[n] = blocked
				delete(pending, n)
				progress = true
				continue
			}
			if !ready {
				continue
			}
			s.vars["local"] = cty.ObjectVal(done)
			v, d := a.Expr.Value(s.ctx())
			if d.HasErrors() {
				s.failedLocals[n] = fmt.Sprintf("does not evaluate statically (`%s`: %s)", s.file.text(a.Expr.Range()), firstDiag(d))
			} else {
				done[n] = v
			}
			delete(pending, n)
			progress = true
		}
		if !progress {
			for n := range pending {
				s.failedLocals[n] = "reads itself through other locals (a cycle)"
			}
			break
		}
	}
	s.vars["local"] = cty.ObjectVal(done)
}

func sortedAttrNames(m map[string]*hclsyntax.Attribute) []string {
	out := make([]string, 0, len(m))
	for n := range m {
		out = append(out, n)
	}
	sort.Strings(out)
	return out
}

// why explains a failed evaluation: the local it read that failed, if
// any, else the diagnostic.
func (s *tgScope) why(e hclsyntax.Expression, d hcl.Diagnostics) string {
	for _, t := range e.Variables() {
		if t.RootName() == "local" && len(t) >= 2 {
			if ref, ok := t[1].(hcl.TraverseAttr); ok {
				if w, failed := s.failedLocals[ref.Name]; failed {
					return fmt.Sprintf("it reads local.%s, which %s", ref.Name, w)
				}
			}
		}
	}
	return firstDiag(d)
}

// readRest reads terraform, inputs, remote_state and generate from one
// file into the unit, over what earlier files set.
func (s *tgScope) readRest(u *TGUnit, strategy string) {
	from := s.fileRel()
	for _, b := range s.file.body.Blocks {
		switch b.Type {
		case "terraform":
			if a := b.Body.Attributes["source"]; a != nil {
				v, d := a.Expr.Value(s.ctx())
				if d.HasErrors() || v.Type() != cty.String {
					s.note("unevaluated", "terraform.source", "`%s` (%s) does not evaluate statically: %s; the unit's module is unknown", s.file.text(a.Expr.Range()), from, s.why(a.Expr, d))
				} else {
					u.Source = v.AsString()
				}
			}
			for _, hb := range b.Body.Blocks {
				switch hb.Type {
				case "before_hook", "after_hook", "error_hook":
					s.note("note", "terraform."+hb.Type, "%s %q (%s) runs a command around Terraform; the offramp does not run it. If it changes a resource, the import cannot see that", hb.Type, label(hb), from)
				case "extra_arguments":
					s.note("note", "terraform.extra_arguments", "extra_arguments %q (%s): arguments and -var-file files Terragrunt adds to Terraform's command line are not read; a variable set there is not among the inputs", label(hb), from)
				}
			}
		case "remote_state":
			s.readRemoteState(u, b, from)
		case "generate":
			g := TGGenerate{Name: label(b), From: from}
			if a := b.Body.Attributes["path"]; a != nil {
				if v, d := a.Expr.Value(s.ctx()); !d.HasErrors() && v.Type() == cty.String {
					g.Path = v.AsString()
				}
			}
			u.Generates = setGenerate(u.Generates, g)
		}
	}
	for _, n := range []string{"skip", "exclude", "prevent_destroy", "iam_role", "terraform_binary", "download_dir"} {
		a := s.attr(n)
		if a == nil {
			continue
		}
		switch n {
		case "skip":
			if v, d := a.Expr.Value(s.ctx()); !d.HasErrors() && v.Type() == cty.Bool && v.True() {
				u.Skip = true
			}
		case "prevent_destroy":
			s.note("note", n, "prevent_destroy (%s): the import keeps every resource on delete anyway (deletion-policy abandon, cloudResources: keep)", from)
		case "iam_role":
			s.note("note", n, "iam_role (%s) is an AWS role Terragrunt assumes; not used on Google Cloud", from)
		}
	}
	if a := s.attr("inputs"); a != nil {
		s.readInputs(u, a, from, strategy)
	}
}

func label(b *hclsyntax.Block) string {
	if len(b.Labels) > 0 {
		return b.Labels[0]
	}
	return ""
}

func setGenerate(gs []TGGenerate, g TGGenerate) []TGGenerate {
	for i := range gs {
		if gs[i].Name == g.Name {
			gs[i] = g
			return gs
		}
	}
	return append(gs, g)
}

func (s *tgScope) readRemoteState(u *TGUnit, b *hclsyntax.Block, from string) {
	rs := &TGRemoteState{From: from, Config: map[string]any{}}
	if a := b.Body.Attributes["backend"]; a != nil {
		if v, d := a.Expr.Value(s.ctx()); !d.HasErrors() && v.Type() == cty.String {
			rs.Backend = v.AsString()
		}
	}
	if a := b.Body.Attributes["config"]; a != nil {
		v, d := a.Expr.Value(s.ctx())
		if d.HasErrors() {
			s.note("unevaluated", "remote_state", "remote_state.config `%s` (%s) does not evaluate statically: %s; where the state lives is unknown", s.file.text(a.Expr.Range()), from, s.why(a.Expr, d))
		} else if g, err := ctyToGo(v); err == nil {
			if m, ok := g.(map[string]any); ok {
				rs.Config = m
			}
		}
	}
	if a := b.Body.Attributes["generate"]; a != nil {
		if v, d := a.Expr.Value(s.ctx()); !d.HasErrors() && v.CanIterateElements() {
			if p := v.GetAttr("path"); p.Type() == cty.String {
				u.Generates = setGenerate(u.Generates, TGGenerate{Name: "remote_state", Path: p.AsString(), From: from})
			}
		}
	}
	// A remote_state block may sit in a nested block form as well.
	for _, cb := range b.Body.Blocks {
		if cb.Type == "generate" {
			g := TGGenerate{Name: "remote_state", From: from}
			if a := cb.Body.Attributes["path"]; a != nil {
				if v, d := a.Expr.Value(s.ctx()); !d.HasErrors() && v.Type() == cty.String {
					g.Path = v.AsString()
				}
			}
			u.Generates = setGenerate(u.Generates, g)
		}
	}
	rs.Location = stateLocation(rs)
	u.RemoteState = rs
}

// stateLocation says where a backend keeps a unit's state (the default
// workspace's).
func stateLocation(rs *TGRemoteState) string {
	c := rs.Config
	get := func(k string) string { v, _ := c[k].(string); return v }
	switch rs.Backend {
	case "gcs":
		if get("bucket") == "" {
			return ""
		}
		p := strings.Trim(get("prefix"), "/")
		if p != "" {
			p += "/"
		}
		return "gs://" + get("bucket") + "/" + p + "default.tfstate"
	case "s3":
		if get("bucket") == "" {
			return ""
		}
		return "s3://" + get("bucket") + "/" + get("key")
	case "azurerm":
		return "azurerm: storage account " + get("storage_account_name") + ", container " + get("container_name") + ", blob " + get("key")
	case "local", "":
		if p := get("path"); p != "" {
			return p
		}
		return "terraform.tfstate in the unit's working directory"
	}
	return rs.Backend + " backend"
}

// readInputs evaluates inputs key by key where the expression is an object
// constructor, so a key that cannot be evaluated is the only one left
// out, and merges them over what an earlier file set.
func (s *tgScope) readInputs(u *TGUnit, a *hclsyntax.Attribute, from, strategy string) {
	set := func(k string, v cty.Value) {
		if old, ok := u.Inputs[k]; ok && strategy == "deep" {
			v = deepMerge(old, v)
		}
		u.Inputs[k] = v
		u.InputFrom[k] = from
	}
	fail := func(k string, e hclsyntax.Expression, why string) {
		delete(u.Inputs, k)
		u.InputFrom[k] = from
		s.note("unevaluated", "inputs."+k, "`%s` (%s) is not evaluated statically: %s. The input is left out; give the value in the unit, or carry it by hand", s.file.text(e.Range()), from, why)
	}
	obj, ok := a.Expr.(*hclsyntax.ObjectConsExpr)
	if !ok {
		if bad := depMisuse(a.Expr); bad != nil {
			s.note("unevaluated", "inputs", "`%s` (%s): %s; no input from this file is read", s.file.text(a.Expr.Range()), from, depMisuseWhy(s.file, bad))
			return
		}
		v, d := a.Expr.Value(s.ctx())
		if d.HasErrors() || !v.CanIterateElements() {
			s.note("unevaluated", "inputs", "`%s` (%s) is not evaluated statically: %s; no input from this file is read", s.file.text(a.Expr.Range()), from, s.why(a.Expr, d))
			return
		}
		for it := v.ElementIterator(); it.Next(); {
			k, e := it.Element()
			set(k.AsString(), e)
		}
		return
	}
	for _, it := range obj.Items {
		kv, d := it.KeyExpr.Value(&hcl.EvalContext{})
		if d.HasErrors() {
			if kt := hcl.ExprAsKeyword(it.KeyExpr); kt != "" {
				kv = cty.StringVal(kt)
			} else {
				s.note("unevaluated", "inputs", "the key `%s` (%s) is not a literal; the input is left out", s.file.text(it.KeyExpr.Range()), from)
				continue
			}
		}
		k := kv.AsString()
		if bad := depMisuse(it.ValueExpr); bad != nil {
			fail(k, it.ValueExpr, depMisuseWhy(s.file, bad))
			continue
		}
		v, d := it.ValueExpr.Value(s.ctx())
		if d.HasErrors() {
			fail(k, it.ValueExpr, s.why(it.ValueExpr, d))
			continue
		}
		set(k, v)
	}
}

func deepMerge(a, b cty.Value) cty.Value {
	at, bt := a.Type(), b.Type()
	if (at.IsObjectType() || at.IsMapType()) && (bt.IsObjectType() || bt.IsMapType()) && !a.IsNull() && !b.IsNull() {
		m := map[string]cty.Value{}
		for it := a.ElementIterator(); it.Next(); {
			k, v := it.Element()
			m[k.AsString()] = v
		}
		for it := b.ElementIterator(); it.Next(); {
			k, v := it.Element()
			if old, ok := m[k.AsString()]; ok {
				v = deepMerge(old, v)
			}
			m[k.AsString()] = v
		}
		return cty.ObjectVal(m)
	}
	if (at.IsTupleType() || at.IsListType()) && (bt.IsTupleType() || bt.IsListType()) && !a.IsNull() && !b.IsNull() {
		var l []cty.Value
		for it := a.ElementIterator(); it.Next(); {
			_, v := it.Element()
			l = append(l, v)
		}
		for it := b.ElementIterator(); it.Next(); {
			_, v := it.Element()
			l = append(l, v)
		}
		return cty.TupleVal(l)
	}
	return b
}

// dependencyObject is the dependency variable: for each dependency the
// file names, outputs.<path> as a marker for each output path the file's
// expressions read. A path that is read both whole and in part is a
// marker whole, so reading into it fails and is reported.
func dependencyObject(body *hclsyntax.Body, deps map[string]*TGDependency) cty.Value {
	paths := map[string][][]string{}
	var walk func(b *hclsyntax.Body)
	collect := func(e hclsyntax.Expression) {
		for _, t := range e.Variables() {
			if t.RootName() != "dependency" || len(t) < 3 {
				continue
			}
			dep, ok1 := t[1].(hcl.TraverseAttr)
			out, ok2 := t[2].(hcl.TraverseAttr)
			if !ok1 || !ok2 || out.Name != "outputs" {
				continue
			}
			var p []string
			for _, step := range t[3:] {
				switch x := step.(type) {
				case hcl.TraverseAttr:
					p = append(p, x.Name)
				case hcl.TraverseIndex:
					if x.Key.Type() == cty.String {
						p = append(p, x.Key.AsString())
					} else {
						goto done
					}
				default:
					goto done
				}
			}
		done:
			paths[dep.Name] = append(paths[dep.Name], p)
		}
	}
	walk = func(b *hclsyntax.Body) {
		for _, a := range b.Attributes {
			collect(a.Expr)
		}
		for _, c := range b.Blocks {
			walk(c.Body)
		}
	}
	walk(body)
	m := map[string]cty.Value{}
	for name := range deps {
		m[name] = cty.ObjectVal(map[string]cty.Value{"outputs": markerTree(name, nil, paths[name])})
	}
	if len(m) == 0 {
		return cty.EmptyObjectVal
	}
	return cty.ObjectVal(m)
}

func markerTree(dep string, prefix []string, paths [][]string) cty.Value {
	for _, p := range paths {
		if len(p) == 0 {
			return cty.StringVal(depMarker(dep, celPath(prefix)))
		}
	}
	children := map[string][][]string{}
	for _, p := range paths {
		children[p[0]] = append(children[p[0]], p[1:])
	}
	m := map[string]cty.Value{}
	for k, ps := range children {
		m[k] = markerTree(dep, append(append([]string{}, prefix...), k), ps)
	}
	return cty.ObjectVal(m)
}

// celPath writes an output path as CEL selections: name.x or name['a-b'].
func celPath(p []string) string {
	var b strings.Builder
	for i, s := range p {
		if i > 0 && !isIdent(s) {
			fmt.Fprintf(&b, "['%s']", strings.ReplaceAll(s, "'", "\\'"))
			continue
		}
		b.WriteString("." + s)
	}
	return strings.TrimPrefix(b.String(), ".")
}

func isIdent(s string) bool {
	if s == "" {
		return false
	}
	for i, c := range s {
		if !(c == '_' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || i > 0 && c >= '0' && c <= '9') {
			return false
		}
	}
	return true
}

// depMisuse finds where an expression does more with a dependency output
// than place it: a function of it, a condition on it, a loop over it. The
// offramp carries a dependency output only as a reference to the
// producing component's output (whole, or inside a string or a
// collection); anything else would be evaluated at plan time by Bundt as
// CEL, which the offramp does not write for Terragrunt yet.
func depMisuse(e hclsyntax.Expression) hclsyntax.Expression {
	uses := false
	for _, t := range e.Variables() {
		if t.RootName() == "dependency" {
			uses = true
			break
		}
	}
	if !uses {
		return nil
	}
	switch x := e.(type) {
	case *hclsyntax.ScopeTraversalExpr:
		return nil
	case *hclsyntax.TemplateExpr:
		for _, p := range x.Parts {
			if b := depMisuse(p); b != nil {
				return b
			}
		}
		return nil
	case *hclsyntax.TemplateWrapExpr:
		return depMisuse(x.Wrapped)
	case *hclsyntax.ParenthesesExpr:
		return depMisuse(x.Expression)
	case *hclsyntax.TupleConsExpr:
		for _, p := range x.Exprs {
			if b := depMisuse(p); b != nil {
				return b
			}
		}
		return nil
	case *hclsyntax.ObjectConsExpr:
		for _, it := range x.Items {
			if b := depMisuse(it.KeyExpr); b != nil {
				return b
			}
			if b := depMisuse(it.ValueExpr); b != nil {
				return b
			}
		}
		return nil
	case *hclsyntax.ObjectConsKeyExpr:
		if len(x.Wrapped.Variables()) > 0 && x.Wrapped.Variables()[0].RootName() == "dependency" {
			return x
		}
		return nil
	}
	return e
}

func depMisuseWhy(f *tgFile, bad hclsyntax.Expression) string {
	return fmt.Sprintf("`%s` computes with a dependency's output, which only Terraform's run knows; the offramp carries a dependency output only as a reference to the producing component's output", f.text(bad.Range()))
}

// functions are Terraform's functions that need nothing but their
// arguments and the files, and Terragrunt's that read the estate.
// Terragrunt's that need a command, a cloud call or the run itself fail
// with a reason.
func (s *tgScope) functions() map[string]function.Function {
	fs := map[string]function.Function{}
	for k, v := range tfFuncs {
		fs[k] = v
	}
	str0 := func(f func() (string, error)) function.Function {
		return function.New(&function.Spec{Type: function.StaticReturnType(cty.String), Impl: func([]cty.Value, cty.Type) (cty.Value, error) {
			v, err := f()
			if err != nil {
				return cty.NilVal, err
			}
			return cty.StringVal(v), nil
		}})
	}
	// An optional include label as the one argument.
	incDir := func(args []cty.Value) (string, error) {
		name := s.parent
		if len(args) > 0 {
			name = args[0].AsString()
		}
		if p, ok := s.includes[name]; ok {
			return filepath.Dir(p), nil
		}
		if len(args) == 0 && len(s.includes) == 1 {
			for _, p := range s.includes {
				return filepath.Dir(p), nil
			}
		}
		if len(args) == 0 && len(s.includes) == 0 {
			return s.unitDir, nil
		}
		return "", fmt.Errorf("no include %q", name)
	}
	optLabel := &function.Spec{
		VarParam: &function.Parameter{Name: "include", Type: cty.String},
		Type:     function.StaticReturnType(cty.String),
	}
	withLabel := func(f func(args []cty.Value) (string, error)) function.Function {
		sp := *optLabel
		sp.Impl = func(args []cty.Value, _ cty.Type) (cty.Value, error) {
			v, err := f(args)
			if err != nil {
				return cty.NilVal, err
			}
			return cty.StringVal(v), nil
		}
		return function.New(&sp)
	}
	fs["get_terragrunt_dir"] = str0(func() (string, error) { return s.unitDir, nil })
	fs["get_original_terragrunt_dir"] = fs["get_terragrunt_dir"]
	fs["get_parent_terragrunt_dir"] = withLabel(incDir)
	fs["path_relative_to_include"] = withLabel(func(args []cty.Value) (string, error) {
		d, err := incDir(args)
		if err != nil {
			return "", err
		}
		r, err := filepath.Rel(d, s.unitDir)
		return filepath.ToSlash(r), err
	})
	fs["path_relative_from_include"] = withLabel(func(args []cty.Value) (string, error) {
		d, err := incDir(args)
		if err != nil {
			return "", err
		}
		r, err := filepath.Rel(s.unitDir, d)
		return filepath.ToSlash(r), err
	})
	repoRoot := func() (string, error) {
		for d := s.unitDir; ; d = filepath.Dir(d) {
			if _, err := os.Stat(filepath.Join(d, ".git")); err == nil {
				return d, nil
			}
			if filepath.Dir(d) == d {
				return "", fmt.Errorf("get_repo_root: %s is not in a git repository", s.unitDir)
			}
		}
	}
	fs["get_repo_root"] = str0(repoRoot)
	fs["get_path_from_repo_root"] = str0(func() (string, error) {
		r, err := repoRoot()
		if err != nil {
			return "", err
		}
		p, err := filepath.Rel(r, s.unitDir)
		return filepath.ToSlash(p), err
	})
	fs["get_path_to_repo_root"] = str0(func() (string, error) {
		r, err := repoRoot()
		if err != nil {
			return "", err
		}
		p, err := filepath.Rel(s.unitDir, r)
		return filepath.ToSlash(p), err
	})
	fs["find_in_parent_folders"] = function.New(&function.Spec{
		VarParam: &function.Parameter{Name: "args", Type: cty.String},
		Type:     function.StaticReturnType(cty.String),
		Impl: func(args []cty.Value, _ cty.Type) (cty.Value, error) {
			name := "terragrunt.hcl"
			if len(args) > 0 {
				name = args[0].AsString()
			}
			for d := filepath.Dir(s.unitDir); ; d = filepath.Dir(d) {
				p := filepath.Join(d, name)
				if _, err := os.Stat(p); err == nil {
					return cty.StringVal(p), nil
				}
				if filepath.Dir(d) == d {
					break
				}
			}
			if len(args) > 1 {
				return args[1], nil
			}
			return cty.NilVal, fmt.Errorf("find_in_parent_folders: no %s above %s", name, s.unitDir)
		},
	})
	fs["read_terragrunt_config"] = function.New(&function.Spec{
		Params:   []function.Parameter{{Name: "path", Type: cty.String}},
		VarParam: &function.Parameter{Name: "default", Type: cty.DynamicPseudoType},
		Type:     function.StaticReturnType(cty.DynamicPseudoType),
		Impl: func(args []cty.Value, _ cty.Type) (cty.Value, error) {
			p := args[0].AsString()
			if !filepath.IsAbs(p) {
				p = filepath.Join(s.unitDir, p)
			}
			if _, err := os.Stat(p); err != nil && len(args) > 1 {
				return args[1], nil
			}
			return s.r.readConfig(filepath.Clean(p), s.findings, s.where)
		},
	})
	fs["read_tfvars_file"] = function.New(&function.Spec{
		Params: []function.Parameter{{Name: "path", Type: cty.String}},
		Type:   function.StaticReturnType(cty.String),
		Impl: func(args []cty.Value, _ cty.Type) (cty.Value, error) {
			p := args[0].AsString()
			if !filepath.IsAbs(p) {
				p = filepath.Join(s.unitDir, p)
			}
			src, err := os.ReadFile(p)
			if err != nil {
				return cty.NilVal, err
			}
			f, d := hclsyntax.ParseConfig(src, p, hcl.InitialPos)
			if d.HasErrors() {
				return cty.NilVal, fmt.Errorf("%s", d.Error())
			}
			m := map[string]cty.Value{}
			for n, a := range f.Body.(*hclsyntax.Body).Attributes {
				v, d := a.Expr.Value(&hcl.EvalContext{Functions: tfFuncs})
				if d.HasErrors() {
					return cty.NilVal, fmt.Errorf("%s", d.Error())
				}
				m[n] = v
			}
			j, err := stdlib.JSONEncode(cty.ObjectVal(m))
			if err != nil {
				return cty.NilVal, err
			}
			return j, nil
		},
	})
	fs["get_env"] = function.New(&function.Spec{
		Params:   []function.Parameter{{Name: "name", Type: cty.String}},
		VarParam: &function.Parameter{Name: "default", Type: cty.String},
		Type:     function.StaticReturnType(cty.String),
		Impl: func(args []cty.Value, _ cty.Type) (cty.Value, error) {
			n := args[0].AsString()
			if v, ok := s.r.opt.Env[n]; ok {
				s.note("note", "get_env", "get_env(%q) took %q given with --getenv", n, v)
				return cty.StringVal(v), nil
			}
			if len(args) > 1 {
				s.note("note", "get_env", "get_env(%q) took its default %q: the variable was not given (--getenv)", n, args[1].AsString())
				return args[1], nil
			}
			return cty.NilVal, errStatic{fmt.Sprintf("get_env(%q) has no default and the variable was not given (--getenv %s=...)", n, n)}
		},
	})
	fs["get_terragrunt_source_cli_flag"] = str0(func() (string, error) { return "", nil })
	for n, why := range map[string]string{
		"run_cmd":                               "runs a command",
		"sops_decrypt_file":                     "decrypts a file with keys the offramp does not hold",
		"get_aws_account_id":                    "calls AWS",
		"get_aws_account_alias":                 "calls AWS",
		"get_aws_caller_identity_arn":           "calls AWS",
		"get_aws_caller_identity_user_id":       "calls AWS",
		"get_terraform_command":                 "depends on the command Terragrunt runs",
		"get_terraform_cli_args":                "depends on the command Terragrunt runs",
		"get_platform":                          "depends on the machine Terragrunt runs on",
		"get_working_dir":                       "depends on Terragrunt's download directory",
		"get_default_retryable_errors":          "is Terragrunt's run configuration",
		"mark_as_read":                          "is Terragrunt's run bookkeeping",
		"constraint_check":                      "depends on the Terraform version that runs",
		"get_terraform_commands_that_need_vars": "is Terragrunt's run configuration",
	} {
		why := why
		name := n
		fs[n] = function.New(&function.Spec{
			VarParam: &function.Parameter{Name: "args", Type: cty.DynamicPseudoType, AllowNull: true, AllowUnknown: true, AllowDynamicType: true},
			Type:     function.StaticReturnType(cty.DynamicPseudoType),
			Impl: func([]cty.Value, cty.Type) (cty.Value, error) {
				return cty.NilVal, errStatic{name + " " + why + ": not evaluated statically"}
			},
		})
	}
	// Terraform's file functions, relative to the unit.
	fileAt := func(p string) string {
		if !filepath.IsAbs(p) {
			p = filepath.Join(s.unitDir, p)
		}
		return p
	}
	fs["file"] = function.New(&function.Spec{
		Params: []function.Parameter{{Name: "path", Type: cty.String}},
		Type:   function.StaticReturnType(cty.String),
		Impl: func(args []cty.Value, _ cty.Type) (cty.Value, error) {
			b, err := os.ReadFile(fileAt(args[0].AsString()))
			if err != nil {
				return cty.NilVal, err
			}
			return cty.StringVal(string(b)), nil
		},
	})
	fs["fileexists"] = function.New(&function.Spec{
		Params: []function.Parameter{{Name: "path", Type: cty.String}},
		Type:   function.StaticReturnType(cty.Bool),
		Impl: func(args []cty.Value, _ cty.Type) (cty.Value, error) {
			_, err := os.Stat(fileAt(args[0].AsString()))
			return cty.BoolVal(err == nil), nil
		},
	})
	fs["dirname"] = function.New(&function.Spec{
		Params: []function.Parameter{{Name: "path", Type: cty.String}},
		Type:   function.StaticReturnType(cty.String),
		Impl: func(args []cty.Value, _ cty.Type) (cty.Value, error) {
			return cty.StringVal(filepath.Dir(args[0].AsString())), nil
		},
	})
	fs["basename"] = function.New(&function.Spec{
		Params: []function.Parameter{{Name: "path", Type: cty.String}},
		Type:   function.StaticReturnType(cty.String),
		Impl: func(args []cty.Value, _ cty.Type) (cty.Value, error) {
			return cty.StringVal(filepath.Base(args[0].AsString())), nil
		},
	})
	fs["abspath"] = function.New(&function.Spec{
		Params: []function.Parameter{{Name: "path", Type: cty.String}},
		Type:   function.StaticReturnType(cty.String),
		Impl: func(args []cty.Value, _ cty.Type) (cty.Value, error) {
			return cty.StringVal(fileAt(args[0].AsString())), nil
		},
	})
	return fs
}

// readConfig is read_terragrunt_config: another file's locals and inputs,
// evaluated in its own directory.
func (r *tgReader) readConfig(path string, findings *[]Finding, where string) (cty.Value, error) {
	if v, ok := r.cache[path]; ok {
		return v, nil
	}
	if r.depth > 8 {
		return cty.NilVal, fmt.Errorf("read_terragrunt_config: %s: too deep", path)
	}
	r.depth++
	defer func() { r.depth-- }()
	f, err := parseTG(path)
	if err != nil {
		return cty.NilVal, err
	}
	s := &tgScope{r: r, unitDir: filepath.Dir(path), file: f, includes: map[string]string{}, findings: findings, where: where, vars: map[string]cty.Value{}}
	s.evalLocals()
	m := map[string]cty.Value{"locals": s.vars["local"]}
	if a := s.attr("inputs"); a != nil {
		v, d := a.Expr.Value(s.ctx())
		if d.HasErrors() {
			return cty.NilVal, fmt.Errorf("read_terragrunt_config(%s): inputs: %s", path, s.why(a.Expr, d))
		}
		m["inputs"] = v
	}
	v := cty.ObjectVal(m)
	r.cache[path] = v
	return v, nil
}

var tfFuncs = map[string]function.Function{
	"abs": stdlib.AbsoluteFunc, "ceil": stdlib.CeilFunc, "chomp": stdlib.ChompFunc, "coalesce": stdlib.CoalesceFunc,
	"coalescelist": stdlib.CoalesceListFunc, "compact": stdlib.CompactFunc, "concat": stdlib.ConcatFunc,
	"contains": stdlib.ContainsFunc, "distinct": stdlib.DistinctFunc, "element": stdlib.ElementFunc,
	"flatten": stdlib.FlattenFunc, "floor": stdlib.FloorFunc, "format": stdlib.FormatFunc,
	"formatlist": stdlib.FormatListFunc, "indent": stdlib.IndentFunc, "join": stdlib.JoinFunc,
	"jsondecode": stdlib.JSONDecodeFunc, "jsonencode": stdlib.JSONEncodeFunc, "keys": stdlib.KeysFunc,
	"length": stdlib.LengthFunc, "lookup": stdlib.LookupFunc, "lower": stdlib.LowerFunc, "max": stdlib.MaxFunc,
	"merge": stdlib.MergeFunc, "min": stdlib.MinFunc, "range": stdlib.RangeFunc, "regex": stdlib.RegexFunc,
	"regexall": stdlib.RegexAllFunc, "replace": stdlib.ReplaceFunc, "reverse": stdlib.ReverseListFunc,
	"setintersection": stdlib.SetIntersectionFunc, "setproduct": stdlib.SetProductFunc,
	"setsubtract": stdlib.SetSubtractFunc, "setunion": stdlib.SetUnionFunc, "slice": stdlib.SliceFunc,
	"sort": stdlib.SortFunc, "split": stdlib.SplitFunc, "strrev": stdlib.ReverseFunc, "substr": stdlib.SubstrFunc,
	"title": stdlib.TitleFunc, "tobool": stdlib.MakeToFunc(cty.Bool),
	"tolist": stdlib.MakeToFunc(cty.List(cty.DynamicPseudoType)), "tomap": stdlib.MakeToFunc(cty.Map(cty.DynamicPseudoType)),
	"tonumber": stdlib.MakeToFunc(cty.Number), "toset": stdlib.MakeToFunc(cty.Set(cty.DynamicPseudoType)),
	"tostring": stdlib.MakeToFunc(cty.String), "trim": stdlib.TrimFunc, "trimprefix": stdlib.TrimPrefixFunc,
	"trimspace": stdlib.TrimSpaceFunc, "trimsuffix": stdlib.TrimSuffixFunc, "upper": stdlib.UpperFunc,
	"values": stdlib.ValuesFunc, "zipmap": stdlib.ZipmapFunc, "chunklist": stdlib.ChunklistFunc,
	"formatdate": stdlib.FormatDateFunc, "csvdecode": stdlib.CSVDecodeFunc,
	"yamldecode": ctyyaml.YAMLDecodeFunc, "yamlencode": ctyyaml.YAMLEncodeFunc,
	"can":       canFunc,
	"try":       tryFunc,
	"timestamp": staticFail("timestamp", "is the time Terraform runs"),
	"uuid":      staticFail("uuid", "is random"),
}

func staticFail(name, why string) function.Function {
	return function.New(&function.Spec{
		VarParam: &function.Parameter{Name: "args", Type: cty.DynamicPseudoType, AllowNull: true},
		Type:     function.StaticReturnType(cty.DynamicPseudoType),
		Impl: func([]cty.Value, cty.Type) (cty.Value, error) {
			return cty.NilVal, errStatic{name + " " + why + ": not evaluated statically"}
		},
	})
}

// can and try evaluate eagerly here: HCL has already evaluated their
// arguments, so a failing argument fails the whole expression, and the
// finding names it. That never guesses, at the cost of reporting an
// expression Terraform would have recovered from.
var canFunc = function.New(&function.Spec{
	Params: []function.Parameter{{Name: "expression", Type: cty.DynamicPseudoType, AllowNull: true}},
	Type:   function.StaticReturnType(cty.Bool),
	Impl: func([]cty.Value, cty.Type) (cty.Value, error) {
		return cty.True, nil
	},
})

var tryFunc = function.New(&function.Spec{
	VarParam: &function.Parameter{Name: "expressions", Type: cty.DynamicPseudoType, AllowNull: true},
	Type: func(args []cty.Value) (cty.Type, error) {
		if len(args) == 0 {
			return cty.NilType, fmt.Errorf("try needs an argument")
		}
		return args[0].Type(), nil
	},
	Impl: func(args []cty.Value, _ cty.Type) (cty.Value, error) {
		return args[0], nil
	},
})

func firstDiag(d hcl.Diagnostics) string {
	for _, x := range d {
		if x.Severity == hcl.DiagError {
			if x.Detail != "" {
				return x.Detail
			}
			return x.Summary
		}
	}
	return "unknown error"
}

// ctyToGo turns an evaluated value into plain Go (numbers as int64 when
// whole, else float64).
func ctyToGo(v cty.Value) (any, error) {
	if v.IsNull() {
		return nil, nil
	}
	if !v.IsKnown() {
		return nil, fmt.Errorf("an unknown value")
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
			if i, acc := bf.Int64(); acc == big.Exact {
				return i, nil
			}
		}
		f, _ := bf.Float64()
		return f, nil
	case t.IsListType() || t.IsTupleType() || t.IsSetType():
		out := []any{}
		for it := v.ElementIterator(); it.Next(); {
			_, e := it.Element()
			g, err := ctyToGo(e)
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
			g, err := ctyToGo(e)
			if err != nil {
				return nil, err
			}
			out[k.AsString()] = g
		}
		return out, nil
	}
	return nil, fmt.Errorf("a value of type %s", t.FriendlyName())
}
