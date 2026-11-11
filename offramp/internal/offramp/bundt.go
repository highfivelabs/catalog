// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package offramp

import (
	"fmt"

	"github.com/highfivelabs/catalog/tools/convert"
	"sort"
	"strings"
)

// BundtOptions name what the import lands in. The output shape is the
// design's draft (drafts/tf-offramp/README.md in Bundt, "Output shape"):
// documents as apps/bundt/spec defines them, with no field the specs lack.
type BundtOptions struct {
	// Name is the Template's, the Stack's and the Instance's name: the
	// Terraform root module's (its directory).
	Name    string
	Team    string
	Env     string
	Target  string
	Version string // the Packages' and the Template's version
	// Namespace is the Environment's namespace on its Target.
	Namespace string
	// KCCVersion is the Config Connector provider version the
	// Environment pins.
	KCCVersion string
	// Registry is where the Packages' manifests artifacts are pushed
	// (`<Registry>/<package>`); their digests are known only after the push.
	Registry string
	// Graduation, when set, says which calls graduate to an Instance of a
	// catalog chart (Graduate); the rest keep frozen Packages.
	Graduation *Graduation
}

// Component is one Template component: the objects of one root module
// call, or of the root module itself.
type Component struct {
	Name      string
	Package   string
	Objects   []*Object
	DependsOn []string
	// Graduated is set when the call graduates to a catalog chart: the
	// component is an Instance of that chart, not a frozen Package.
	Graduated *Graduated
}

// Bundle is what the converter writes for Bundt.
type Bundle struct {
	Components []*Component
	// Catalog holds the Packages and the Template (published by one plan).
	Catalog []map[string]any
	// Record holds the Environment, the Stack and the Instance (a second
	// plan, once the catalog is published).
	Record []map[string]any
	// Prereqs are the Team and the Target the record names, for a Bundt
	// that does not have them yet.
	Prereqs []map[string]any
	Notes   []string
	// Graduation is the check of each call against its chart, when made.
	Graduation *Graduation
}

// Group puts objects into components: one per root module call (its
// name), and `root` for what the root module declares itself. The
// Template's dependsOn follows Terraform's dependencies between calls.
func Group(objs []*Object, opt BundtOptions) *Bundle {
	byCall := map[string]*Component{}
	var order []string
	callOf := map[string]string{} // address without key -> component
	for _, o := range objs {
		name := componentName(o.Call)
		c := byCall[name]
		if c == nil {
			c = &Component{Name: name, Package: fitName(sanitize(opt.Name+"-"+name), "")}
			byCall[name] = c
			order = append(order, name)
		}
		c.Objects = append(c.Objects, o)
		callOf[stripKeys(o.Source)] = name
	}
	b := &Bundle{}
	for _, name := range order {
		c := byCall[name]
		deps := map[string]bool{}
		for _, o := range c.Objects {
			for _, d := range o.Deps {
				dc, ok := callOf[stripKeys(d)]
				if !ok {
					// A dependency on a data source or a terraform-only
					// resource: nothing to order.
					dc = componentName(rootCall(modulePart(d)))
					if _, known := byCall[dc]; !known {
						continue
					}
				}
				if dc != name {
					deps[dc] = true
				}
			}
		}
		for d := range deps {
			c.DependsOn = append(c.DependsOn, d)
		}
		sort.Strings(c.DependsOn)
		b.Components = append(b.Components, c)
	}
	if cyc := cycle(b.Components); len(cyc) > 0 {
		b.Notes = append(b.Notes, fmt.Sprintf("the components %s depend on each other in a cycle through Terraform's resource-level dependencies; their dependsOn was dropped (Bundt blocks a cycle, templates.md R22), and Config Connector orders them by reference instead", strings.Join(cyc, ", ")))
		for _, c := range b.Components {
			c.DependsOn = nil
		}
	}
	b.Graduation = opt.Graduation
	b.build(opt)
	return b
}

func componentName(call string) string {
	if call == "" {
		return "root"
	}
	return sanitize(call)
}

// modulePart gives the module path of an address (without the resource).
func modulePart(addr string) string {
	parts := strings.Split(addr, ".")
	var out []string
	for i := 0; i+1 < len(parts); i += 2 {
		if parts[i] != "module" {
			break
		}
		out = append(out, parts[i], parts[i+1])
	}
	return strings.Join(out, ".")
}

// stripKeys removes instance keys: a.b["x"].c[0] is a.b.c.
func stripKeys(addr string) string {
	var b strings.Builder
	depth := 0
	inStr := false
	for i := 0; i < len(addr); i++ {
		c := addr[i]
		switch {
		case inStr:
			if c == '\\' {
				i++
			} else if c == '"' {
				inStr = false
			}
		case c == '[':
			depth++
		case c == ']':
			depth--
		case c == '"' && depth > 0:
			inStr = true
		case depth == 0:
			b.WriteByte(c)
		}
	}
	return b.String()
}

func cycle(cs []*Component) []string {
	deps := map[string][]string{}
	for _, c := range cs {
		deps[c.Name] = c.DependsOn
	}
	state := map[string]int{}
	var stack, found []string
	var visit func(string) bool
	visit = func(n string) bool {
		state[n] = 1
		stack = append(stack, n)
		for _, d := range deps[n] {
			if state[d] == 1 {
				for i, s := range stack {
					if s == d {
						found = append([]string(nil), stack[i:]...)
					}
				}
				return true
			}
			if state[d] == 0 && visit(d) {
				return true
			}
		}
		stack = stack[:len(stack)-1]
		state[n] = 2
		return false
	}
	for _, c := range cs {
		if state[c.Name] == 0 && visit(c.Name) {
			sort.Strings(found)
			return found
		}
	}
	return nil
}

func (b *Bundle) build(opt BundtOptions) {
	kccVersion := opt.KCCVersion
	var tcomps []any
	instValues := map[string]any{}
	for _, c := range b.Components {
		if opt.Graduation != nil {
			for _, g := range opt.Graduation.Calls {
				if g.Component == c.Name && g.OK() {
					c.Graduated = g
				}
			}
		}
		if g := c.Graduated; g != nil {
			c.Package = g.Chart.Package
			inputs := map[string]any{}
			for _, p := range append(append(convertOrdered{}, g.Inputs...), g.Import...) {
				inputs[p.Key] = p.Value
			}
			tc := map[string]any{
				"name":    c.Name,
				"package": map[string]any{"name": g.Chart.Package, "version": g.Chart.Version},
				"inputs":  inputs,
			}
			if len(c.DependsOn) > 0 {
				var d []any
				for _, x := range c.DependsOn {
					d = append(d, x)
				}
				tc["dependsOn"] = d
			}
			tcomps = append(tcomps, tc)
			if len(g.Values) > 0 {
				vals := map[string]any{}
				for _, p := range g.Values {
					vals[p.Key] = p.Value
				}
				instValues[c.Name] = map[string]any{"values": vals}
			}
			continue
		}
		pkg := map[string]any{
			"apiVersion": "hfl.dev/v1",
			"kind":       "Package",
			"metadata": map[string]any{
				"name":        c.Package,
				"annotations": map[string]any{"offramp.hfl.dev/manifests": "packages/" + c.Package + "/manifests"},
			},
			"spec": map[string]any{
				"version":   opt.Version,
				"engine":    "manifests",
				"outputs":   map[string]any{},
				"providers": []any{"kcc"},
			},
		}
		if mes := managedElsewhere(c.Objects); len(mes) > 0 {
			pkg["spec"].(map[string]any)["managedElsewhere"] = mes
		}
		b.Catalog = append(b.Catalog, pkg)
		tc := map[string]any{
			"name":    c.Name,
			"package": map[string]any{"name": c.Package, "version": opt.Version},
			"inputs":  map[string]any{},
		}
		if len(c.DependsOn) > 0 {
			var d []any
			for _, x := range c.DependsOn {
				d = append(d, x)
			}
			tc["dependsOn"] = d
		}
		tcomps = append(tcomps, tc)
	}
	b.Catalog = append(b.Catalog, map[string]any{
		"apiVersion": "hfl.dev/v1",
		"kind":       "Template",
		"metadata":   map[string]any{"name": opt.Name},
		"spec":       map[string]any{"version": opt.Version, "components": tcomps},
	})
	project := commonProject(b.Components)
	env := map[string]any{
		"target":     opt.Target,
		"namespaces": []any{opt.Namespace},
		"providers":  map[string]any{"kcc": kccVersion},
	}
	if project != "" {
		env["cloud"] = map[string]any{"gcp": map[string]any{"project": project}}
	}
	b.Record = []map[string]any{
		{"apiVersion": "hfl.dev/v1", "kind": "Environment", "metadata": map[string]any{"name": opt.Env, "scope": opt.Team}, "spec": env},
		{"apiVersion": "hfl.dev/v1", "kind": "Stack", "metadata": map[string]any{"name": opt.Name, "scope": opt.Team}, "spec": map[string]any{"template": opt.Name}},
		{"apiVersion": "hfl.dev/v1", "kind": "Instance", "metadata": map[string]any{"name": opt.Name, "scope": opt.Team + "/" + opt.Env},
			"spec": map[string]any{"stack": opt.Name, "version": opt.Version, "cloudResources": "keep"}},
	}
	if len(instValues) > 0 {
		b.Record[2]["spec"].(map[string]any)["components"] = instValues
	}
	b.Prereqs = []map[string]any{
		{"apiVersion": "hfl.dev/v1", "kind": "Team", "metadata": map[string]any{"name": opt.Team}, "spec": map[string]any{"displayName": opt.Team}},
		{"apiVersion": "hfl.dev/v1", "kind": "Target", "metadata": map[string]any{"name": opt.Target}, "spec": map[string]any{"type": "cluster", "class": "infra"}},
	}
}

// managedElsewhere lists fields another controller sets on what the
// component renders (packages.md R36): a node pool's size under its
// autoscaler.
func managedElsewhere(objs []*Object) []any {
	var out []any
	seen := map[string]bool{}
	for _, o := range objs {
		if o.Kind == "ContainerNodePool" && dig(o.Obj, "spec", "autoscaling") != nil && !seen["np"] {
			seen["np"] = true
			out = append(out, map[string]any{"kind": "ContainerNodePool", "path": "spec.nodeCount"})
		}
	}
	return out
}

// commonProject is the project most objects name, for the Environment's
// cloud account.
func commonProject(cs []*Component) string {
	count := map[string]int{}
	for _, c := range cs {
		for _, o := range c.Objects {
			p := str(dig(o.Obj, "metadata", "annotations", "cnrm.cloud.google.com/project-id"))
			if p == "" {
				p = strings.TrimPrefix(str(dig(o.Obj, "spec", "projectRef", "external")), "projects/")
			}
			if p != "" {
				count[p]++
			}
		}
	}
	best, n := "", 0
	for _, p := range sortedKeys(count) {
		if count[p] > n {
			best, n = p, count[p]
		}
	}
	return best
}

type convertOrdered = convert.Ordered
