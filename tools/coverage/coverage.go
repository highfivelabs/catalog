// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

// Package coverage compares the catalog's charts with the open-source
// Terraform modules they port (and the ones nobody has ported yet), and
// writes the comparison as CSVs, SVG bars and a section of the README.
//
// How it counts (docs/coverage/README.md has the long version):
//   - a module's variables and outputs are its root module's `variable`
//     and `output` blocks at the pinned tag, parsed with HCL;
//   - a variable is one unit, however many attributes its object type has;
//   - a chart covers a variable unless its upstream.yaml lists it as refused;
//     a variable refused only in part ("partial") is covered, and said so;
//   - a chart covers an output when its Package declares an output of that name;
//   - a resource type has a stable kind when Config Connector (or ACK, or
//     ASO) has a GA/beta kind for it. Only Google Cloud is classified so
//     far (the inventory, docs/gcp-inventory.md).
package coverage

import (
	"encoding/csv"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"gopkg.in/yaml.v3"

	"github.com/highfivelabs/catalog/tools/tfmod"
	"github.com/highfivelabs/catalog/tools/upstream"
)

// Statuses.
const (
	Ported     = "ported"
	Partial    = "partial"
	Blocked    = "blocked"
	NotStarted = "not started"
)

// Row is one tracked module.
type Row struct {
	Cloud, Module, Slug, URL, Version, Chart, Status string
	Rank                                             int
	VarsTotal, VarsCovered, VarsPartial              int
	OutsTotal, OutsCovered                           int
	TypesTotal, TypesStable, TypesMissing            int
	// KindsKnown is false where resource types are not yet classified (AWS, Azure).
	KindsKnown bool
	Notes      string
	Refusals   int
}

// Pct formats covered/total with one decimal, or "" when total is 0.
func Pct(covered, total int) string {
	if total == 0 {
		return ""
	}
	return strconv.FormatFloat(float64(covered)*100/float64(total), 'f', 1, 64)
}

// VarRow is one variable of one module.
type VarRow struct {
	Cloud, Module, Variable, Type, Covered, Reason, GapKind string
}

// OutRow is one output of one module.
type OutRow struct {
	Cloud, Module, Output, Covered string
}

// TypeRow is one resource type of one module.
type TypeRow struct {
	Cloud, Module, Type, Class, Kind string
}

// Result is everything the generator computes.
type Result struct {
	Rows  []Row
	Vars  []VarRow
	Outs  []OutRow
	Types []TypeRow
}

// Options for Build.
type Options struct {
	Root     string
	CacheDir string
	// Offline fails instead of fetching sources that are not cached.
	Offline bool
}

var cloudOrder = map[string]int{"gcp": 0, "aws": 1, "azure": 2}

// Build reads upstream/modules.yaml, fetches each module's source at its
// pin, parses it and compares it with the chart that ports it.
func Build(o Options) (*Result, error) {
	f, err := upstream.Load(filepath.Join(o.Root, "upstream", "modules.yaml"))
	if err != nil {
		return nil, err
	}
	if p := f.Problems(o.Root); len(p) > 0 {
		return nil, fmt.Errorf("upstream/modules.yaml: %s", strings.Join(p, "; "))
	}
	kinds, err := readKinds(filepath.Join(o.Root, "docs", "coverage", "gcp-resource-kinds.csv"))
	if err != nil {
		return nil, err
	}

	// One download per (repository, tag), extracting every module path
	// that is pinned at it.
	type key struct{ slug, tag string }
	paths := map[key][]string{}
	for _, m := range f.Modules {
		k := key{m.Slug(), m.Version}
		paths[k] = appendUnique(paths[k], m.Path)
	}
	var keys []key
	for k := range paths {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].slug != keys[j].slug {
			return keys[i].slug < keys[j].slug
		}
		return keys[i].tag < keys[j].tag
	})
	sources := map[key]upstream.Source{}
	for _, k := range keys {
		if o.Offline {
			sources[k] = upstream.Source{Slug: k.slug, Tag: k.tag, Dir: filepath.Join(o.CacheDir, filepath.FromSlash(k.slug), k.tag)}
			continue
		}
		s, err := upstream.Fetch(o.CacheDir, k.slug, k.tag, paths[k])
		if err != nil {
			return nil, err
		}
		sources[k] = s
	}

	res := &Result{}
	for _, m := range f.Modules {
		src := sources[key{m.Slug(), m.Version}]
		mod, err := tfmod.ParseDir(src.ModuleDir(m.Path), m.Cloud != "gcp")
		if err != nil {
			return nil, fmt.Errorf("%s: %w (run `task coverage` online once to fetch %s@%s)", m.ID, err, m.Slug(), m.Version)
		}
		row := Row{Cloud: m.Cloud, Module: m.Module, Slug: m.Slug(), URL: m.URL, Version: m.Version, Chart: m.Chart, Rank: m.Rank,
			VarsTotal: len(mod.Variables), OutsTotal: len(mod.Outputs)}

		// Resource types.
		var missing []string
		if m.Cloud == "gcp" {
			row.KindsKnown = true
			for _, t := range kinds[m.Module] {
				row.TypesTotal++
				res.Types = append(res.Types, TypeRow{m.Cloud, m.Module, t.Type, t.Class, t.Kind})
				if t.Class == "stable" {
					row.TypesStable++
				} else {
					missing = append(missing, fmt.Sprintf("%s (%s)", t.Type, t.Class))
				}
			}
		} else {
			for _, t := range mod.ResourceTypes {
				row.TypesTotal++
				res.Types = append(res.Types, TypeRow{m.Cloud, m.Module, t, "unclassified", ""})
			}
		}
		row.TypesMissing = row.TypesTotal - row.TypesStable
		if !row.KindsKnown {
			row.TypesMissing = 0
		}

		// The chart, if any.
		var cu *upstream.ChartUpstream
		var pkgOuts map[string]bool
		var valueKeys map[string]bool
		if m.Chart != "" {
			cu, err = upstream.LoadChart(filepath.Join(o.Root, m.Chart))
			if err != nil {
				return nil, err
			}
			pkgOuts, err = packageOutputs(filepath.Join(o.Root, m.Chart, "package.yaml"))
			if err != nil {
				return nil, err
			}
			valueKeys, err = topLevelKeys(filepath.Join(o.Root, m.Chart, "values.yaml"))
			if err != nil {
				return nil, err
			}
		}
		refused := map[string]upstream.Refused{}
		if cu != nil {
			for _, r := range cu.Refused {
				if mod.Var(r.Variable) == nil {
					return nil, fmt.Errorf("%s: upstream.yaml refuses %q, which is not a variable of %s at %s", m.Chart, r.Variable, m.ID, m.Version)
				}
				switch r.Kind {
				case "gap", "alpha", "not-ported", "by-design":
				default:
					return nil, fmt.Errorf("%s: refused %s has kind %q (want gap, alpha, not-ported or by-design)", m.Chart, r.Variable, r.Kind)
				}
				if r.Reason == "" {
					return nil, fmt.Errorf("%s: refused %s needs a reason", m.Chart, r.Variable)
				}
				if _, dup := refused[r.Variable]; dup {
					return nil, fmt.Errorf("%s: %s is listed twice in refused", m.Chart, r.Variable)
				}
				refused[r.Variable] = r
			}
		}
		for _, v := range mod.Variables {
			vr := VarRow{Cloud: m.Cloud, Module: m.Module, Variable: v.Name, Type: v.Type}
			switch {
			case cu == nil:
				vr.Covered, vr.GapKind, vr.Reason = "no", "no-chart", ""
			case !valueKeys[v.Name]:
				// The chart's schema refuses a value it does not list.
				vr.Covered, vr.GapKind, vr.Reason = "no", "not-ported", "not in the chart's values, so its schema refuses it"
			default:
				if r, ok := refused[v.Name]; ok {
					vr.GapKind, vr.Reason = r.Kind, r.Reason
					if r.Partial {
						vr.Covered = "partial"
						row.VarsPartial++
					} else {
						vr.Covered = "no"
					}
				} else {
					vr.Covered = "yes"
				}
			}
			if vr.Covered != "no" {
				row.VarsCovered++
			} else if cu != nil {
				row.Refusals++
			}
			res.Vars = append(res.Vars, vr)
		}
		for _, out := range mod.Outputs {
			or := OutRow{Cloud: m.Cloud, Module: m.Module, Output: out.Name, Covered: "no"}
			if pkgOuts[out.Name] {
				or.Covered = "yes"
				row.OutsCovered++
			}
			res.Outs = append(res.Outs, or)
		}

		// Status.
		switch {
		case cu != nil && row.Refusals == 0 && row.VarsPartial == 0:
			row.Status = Ported
		case cu != nil:
			row.Status = Partial
		case row.KindsKnown && row.TypesMissing > 0:
			row.Status = Blocked
		default:
			row.Status = NotStarted
		}
		row.Notes = notes(&row, mod, missing, classSummary(res.Types, m.Module), refused, cu)
		res.Rows = append(res.Rows, row)
	}
	sort.SliceStable(res.Rows, func(i, j int) bool {
		a, b := res.Rows[i], res.Rows[j]
		if a.Cloud != b.Cloud {
			return cloudOrder[a.Cloud] < cloudOrder[b.Cloud]
		}
		return a.Rank < b.Rank
	})
	order := map[string]int{}
	for i, r := range res.Rows {
		order[r.Cloud+"/"+r.Module] = i
	}
	byMod := func(c, m string) int { return order[c+"/"+m] }
	sort.SliceStable(res.Vars, func(i, j int) bool {
		a, b := res.Vars[i], res.Vars[j]
		if x, y := byMod(a.Cloud, a.Module), byMod(b.Cloud, b.Module); x != y {
			return x < y
		}
		return a.Variable < b.Variable
	})
	sort.SliceStable(res.Outs, func(i, j int) bool {
		a, b := res.Outs[i], res.Outs[j]
		if x, y := byMod(a.Cloud, a.Module), byMod(b.Cloud, b.Module); x != y {
			return x < y
		}
		return a.Output < b.Output
	})
	sort.SliceStable(res.Types, func(i, j int) bool {
		a, b := res.Types[i], res.Types[j]
		if x, y := byMod(a.Cloud, a.Module), byMod(b.Cloud, b.Module); x != y {
			return x < y
		}
		return a.Type < b.Type
	})
	return res, nil
}

func notes(r *Row, mod *tfmod.Module, missing []string, classCounts string, refused map[string]upstream.Refused, cu *upstream.ChartUpstream) string {
	var n []string
	if cu != nil {
		counts := map[string]int{}
		for _, ref := range refused {
			if !ref.Partial {
				counts[ref.Kind]++
			}
		}
		var parts []string
		for _, k := range []string{"gap", "alpha", "not-ported", "by-design"} {
			if counts[k] > 0 {
				parts = append(parts, fmt.Sprintf("%d %s", counts[k], k))
			}
		}
		if r.Refusals > 0 {
			n = append(n, fmt.Sprintf("refuses %d variables (%s)", r.Refusals, strings.Join(parts, ", ")))
		}
		if r.VarsPartial > 0 {
			n = append(n, fmt.Sprintf("%d accepted in part", r.VarsPartial))
		}
		if r.OutsTotal > r.OutsCovered {
			n = append(n, fmt.Sprintf("%d of %d outputs not provided", r.OutsTotal-r.OutsCovered, r.OutsTotal))
		}
	}
	if cu == nil && r.Cloud == "gcp" {
		if r.TypesTotal == 0 {
			n = append(n, "creates no resource types of its own (it composes other modules, or reads or generates)")
		} else if len(missing) > 0 {
			show := missing
			if len(show) > 3 {
				show = show[:3]
			}
			s := fmt.Sprintf("%d resource types lack a stable kind (%s): %s", len(missing), classCounts, strings.Join(show, ", "))
			if len(missing) > 3 {
				s += fmt.Sprintf(" and %d more", len(missing)-3)
			}
			n = append(n, s)
		}
	}
	if r.Cloud != "gcp" {
		if r.VarsTotal == 0 {
			n = append(n, "the root module declares no variables: the module is its submodules, which are not counted")
		}
		n = append(n, "resource types counted from the source; not yet mapped to a controller's kinds")
	}
	return strings.Join(n, "; ")
}

func appendUnique(s []string, v string) []string {
	for _, x := range s {
		if x == v {
			return s
		}
	}
	return append(s, v)
}

type kindRow struct{ Type, Class, Kind string }

func readKinds(path string) (map[string][]kindRow, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("%w (task inventory writes it)", err)
	}
	defer f.Close()
	recs, err := csv.NewReader(f).ReadAll()
	if err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	out := map[string][]kindRow{}
	for _, r := range recs[1:] {
		out[r[0]] = append(out[r[0]], kindRow{r[1], r[3], r[4]})
	}
	return out, nil
}

func packageOutputs(path string) (map[string]bool, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var p struct {
		Spec struct {
			Outputs map[string]string `yaml:"outputs"`
		} `yaml:"spec"`
	}
	if err := yaml.Unmarshal(data, &p); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	out := map[string]bool{}
	for k := range p.Spec.Outputs {
		out[k] = true
	}
	return out, nil
}

func topLevelKeys(path string) (map[string]bool, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var m map[string]any
	if err := yaml.Unmarshal(data, &m); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	out := map[string]bool{}
	for k := range m {
		out[k] = true
	}
	return out, nil
}

// classSummary counts a gcp module's resource types that have no stable
// kind by class, like "2 alpha, 1 none".
func classSummary(types []TypeRow, module string) string {
	c := map[string]int{}
	for _, t := range types {
		if t.Cloud == "gcp" && t.Module == module && t.Class != "stable" {
			c[t.Class]++
		}
	}
	var parts []string
	for _, k := range []string{"alpha", "none", "extensions"} {
		if c[k] > 0 {
			parts = append(parts, fmt.Sprintf("%d %s", c[k], k))
		}
	}
	return strings.Join(parts, ", ")
}
