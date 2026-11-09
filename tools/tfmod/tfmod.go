// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

// Package tfmod reads a Terraform module's interface from its HCL: the
// variables (name, type, default, whether required), the outputs and the
// resource types it creates. It parses with HashiCorp's HCL, not with
// regular expressions, so multi-line types, heredocs and comments are
// handled as Terraform handles them.
package tfmod

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/hashicorp/hcl/v2/ext/typeexpr"
	"github.com/hashicorp/hcl/v2/hclparse"
	"github.com/hashicorp/hcl/v2/hclsyntax"
	"github.com/zclconf/go-cty/cty"
)

// Variable is one `variable` block.
type Variable struct {
	Name string
	// Type is the declared type, abbreviated (Shape); "any" when none.
	Type string
	// TypeCty is the declared type; cty.DynamicPseudoType for any.
	TypeCty cty.Type
	// Required is true when the variable has no default.
	Required    bool
	HasDefault  bool
	Nullable    bool
	Description string
	// Attributes names the top-level attributes of an object type, or of
	// the object inside a map or list of objects (the keys a caller sets).
	Attributes []string
	// Defaults are the attribute defaults declared with optional(type, default) at
	// the top level of the object, by attribute name, when the type declares them.
	Defaults map[string]cty.Value
	// DefaultExpr is the source text of the variable's default, if any, and
	// TypeExpr the declared type's, both with whitespace collapsed.
	DefaultExpr string
	TypeExpr    string
}

// Output is one `output` block.
type Output struct {
	Name        string
	Description string
}

// Module is what a module directory declares.
type Module struct {
	Dir       string
	Variables []Variable
	Outputs   []Output
	// ResourceTypes are the distinct resource types the module (and its
	// submodules, when requested) creates, sorted. An azapi_resource with
	// a literal `type = "Microsoft.X/y@version"` is named by that ARM type.
	ResourceTypes []string
}

// Var returns the named variable.
func (m *Module) Var(name string) *Variable {
	for i := range m.Variables {
		if m.Variables[i].Name == name {
			return &m.Variables[i]
		}
	}
	return nil
}

var skipDirs = map[string]bool{
	".git": true, ".github": true, ".terraform": true, "examples": true, "example": true,
	"tests": true, "test": true, "wrappers": true, "node_modules": true,
}

// ParseDir reads dir's own variables and outputs. When withSubmodules,
// resource types are collected from every .tf file below dir (except
// examples, tests and wrappers) rather than from dir alone.
func ParseDir(dir string, withSubmodules bool) (*Module, error) {
	m := &Module{Dir: dir}
	root, err := parseFiles(dir)
	if err != nil {
		return nil, err
	}
	types := map[string]bool{}
	for _, f := range root {
		if err := collect(m, f, true, types); err != nil {
			return nil, err
		}
	}
	if withSubmodules {
		err := filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if d.IsDir() {
				if p != dir && skipDirs[d.Name()] {
					return filepath.SkipDir
				}
				return nil
			}
			if filepath.Dir(p) == dir || !strings.HasSuffix(p, ".tf") {
				return nil
			}
			f, err := parseFile(p)
			if err != nil {
				return err
			}
			return collect(m, f, false, types)
		})
		if err != nil {
			return nil, err
		}
	}
	for t := range types {
		m.ResourceTypes = append(m.ResourceTypes, t)
	}
	sort.Strings(m.ResourceTypes)
	sort.Slice(m.Variables, func(i, j int) bool { return m.Variables[i].Name < m.Variables[j].Name })
	sort.Slice(m.Outputs, func(i, j int) bool { return m.Outputs[i].Name < m.Outputs[j].Name })
	return m, nil
}

type parsed struct {
	path string
	body *hclsyntax.Body
	src  []byte
}

func parseFiles(dir string) ([]parsed, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var out []parsed
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".tf") {
			continue
		}
		f, err := parseFile(filepath.Join(dir, e.Name()))
		if err != nil {
			return nil, err
		}
		out = append(out, f)
	}
	return out, nil
}

func parseFile(path string) (parsed, error) {
	src, err := os.ReadFile(path)
	if err != nil {
		return parsed{}, err
	}
	f, diags := hclparse.NewParser().ParseHCL(src, path)
	if diags.HasErrors() {
		return parsed{}, fmt.Errorf("%s: %s", path, diags.Error())
	}
	body, ok := f.Body.(*hclsyntax.Body)
	if !ok {
		return parsed{}, fmt.Errorf("%s: not native HCL syntax", path)
	}
	return parsed{path, body, src}, nil
}

func collect(m *Module, f parsed, root bool, types map[string]bool) error {
	for _, b := range f.body.Blocks {
		switch b.Type {
		case "variable":
			if !root || len(b.Labels) != 1 {
				continue
			}
			v, err := variable(b, f.src)
			if err != nil {
				return fmt.Errorf("%s: variable %q: %w", f.path, b.Labels[0], err)
			}
			m.Variables = append(m.Variables, v)
		case "output":
			if !root || len(b.Labels) != 1 {
				continue
			}
			o := Output{Name: b.Labels[0]}
			if a, ok := b.Body.Attributes["description"]; ok {
				o.Description = literalString(a.Expr)
			}
			m.Outputs = append(m.Outputs, o)
		case "resource":
			if len(b.Labels) != 2 {
				continue
			}
			t := b.Labels[0]
			if ignoredType(t) {
				continue
			}
			if strings.HasPrefix(t, "azapi_") {
				if a, ok := b.Body.Attributes["type"]; ok {
					lit := literalString(a.Expr)
					if lit == "" {
						// Not a literal (a local or a variable): name the block's type.
						types[t] = true
						continue
					}
					if i := strings.Index(lit, "@"); i >= 0 {
						lit = lit[:i]
					}
					if strings.EqualFold(lit, "Microsoft.Resources/deployments") {
						continue // AVM's telemetry deployment
					}
					types[t+":"+lit] = true
					continue
				}
			}
			types[t] = true
		}
	}
	return nil
}

// ignoredType reports resource types that are not infrastructure: Terraform
// helpers and the usage telemetry Azure Verified Modules create.
func ignoredType(t string) bool {
	switch t {
	case "null_resource", "terraform_data", "time_sleep", "time_static", "time_rotating", "local_file", "local_sensitive_file", "modtm_telemetry", "random_id", "random_uuid", "random_string", "random_password", "random_integer", "random_pet", "tls_private_key", "tls_self_signed_cert", "tls_cert_request", "tls_locally_signed_cert", "azurerm_resource_group_template_deployment":
		return true
	}
	return false
}

func variable(b *hclsyntax.Block, src []byte) (Variable, error) {
	v := Variable{Name: b.Labels[0], Required: true, Nullable: true, Type: "any", TypeCty: cty.DynamicPseudoType}
	if a, ok := b.Body.Attributes["default"]; ok {
		v.Required, v.HasDefault = false, true
		v.DefaultExpr = strings.Join(strings.Fields(string(a.Expr.Range().SliceBytes(src))), " ")
	}
	if a, ok := b.Body.Attributes["description"]; ok {
		v.Description = literalString(a.Expr)
	}
	if a, ok := b.Body.Attributes["nullable"]; ok {
		if val, d := a.Expr.Value(nil); !d.HasErrors() && val.Type() == cty.Bool && val.False() {
			v.Nullable = false
		}
	}
	if a, ok := b.Body.Attributes["type"]; ok {
		v.TypeExpr = strings.Join(strings.Fields(string(a.Expr.Range().SliceBytes(src))), " ")
		t, defs, diags := typeexpr.TypeConstraintWithDefaults(a.Expr)
		if diags.HasErrors() {
			return v, fmt.Errorf("type: %s", diags.Error())
		}
		v.TypeCty = t
		v.Type = Shape(t)
		v.Attributes = attributes(t)
		if defs != nil && len(defs.DefaultValues) > 0 {
			v.Defaults = defs.DefaultValues
		}
	}
	return v, nil
}

// attributes names the top-level attributes of an object type (looking
// through a map, list or set of objects).
func attributes(t cty.Type) []string {
	for {
		switch {
		case t.IsMapType(), t.IsListType(), t.IsSetType():
			t = t.ElementType()
		case t.IsObjectType():
			var names []string
			for n := range t.AttributeTypes() {
				names = append(names, n)
			}
			sort.Strings(names)
			return names
		default:
			return nil
		}
	}
}

// Shape writes a type compactly: the outer collection types and, for the
// first object met, its attribute names (up to six); deeper objects are
// just "object".
func Shape(t cty.Type) string {
	return shape(t, true)
}

func shape(t cty.Type, expand bool) string {
	switch {
	case t == cty.DynamicPseudoType:
		return "any"
	case t == cty.String:
		return "string"
	case t == cty.Number:
		return "number"
	case t == cty.Bool:
		return "bool"
	case t.IsListType():
		return "list(" + shape(t.ElementType(), expand) + ")"
	case t.IsSetType():
		return "set(" + shape(t.ElementType(), expand) + ")"
	case t.IsMapType():
		return "map(" + shape(t.ElementType(), expand) + ")"
	case t.IsTupleType():
		return "tuple"
	case t.IsObjectType():
		if !expand {
			return "object"
		}
		var names []string
		for n := range t.AttributeTypes() {
			names = append(names, n)
		}
		sort.Strings(names)
		if len(names) > 6 {
			return fmt.Sprintf("object({%s, +%d})", strings.Join(names[:6], ", "), len(names)-6)
		}
		return "object({" + strings.Join(names, ", ") + "})"
	}
	return t.FriendlyName()
}

// literalString returns an expression's value when it is a plain string
// (a quoted string or heredoc without interpolation), else "".
func literalString(e hclsyntax.Expression) string {
	v, d := e.Value(nil)
	if d.HasErrors() || v.IsNull() || !v.IsKnown() || v.Type() != cty.String {
		return ""
	}
	return v.AsString()
}
