// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package coverage

import (
	"bytes"
	"encoding/csv"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// Dir is where the outputs live, relative to the repository root.
const Dir = "docs/coverage"

// Markers delimit the README section the generator owns.
const (
	StartMarker = "<!-- coverage:start -->"
	EndMarker   = "<!-- coverage:end -->"
)

// Colours: ported green, partial amber, blocked a darker grey, not
// started a lighter grey. They read on both light and dark pages.
var statusColour = map[string]string{
	Ported:     "#2da44e",
	Partial:    "#d4a72c",
	Blocked:    "#6e7781",
	NotStarted: "#afb8c1",
}

const trackColour = "#8c959f"

var statuses = []string{Ported, Partial, Blocked, NotStarted}

func cloudName(c string) string {
	switch c {
	case "gcp":
		return "Google Cloud: Cloud Foundation Fabric"
	case "aws":
		return "AWS: terraform-aws-modules"
	case "azure":
		return "Azure: Azure Verified Modules"
	}
	return c
}

// Files renders every output, keyed by path relative to the repository
// root. The README is not among them (see Readme).
func Files(res *Result) (map[string][]byte, error) {
	files := map[string][]byte{}
	var b bytes.Buffer

	w := csv.NewWriter(&b)
	w.Write([]string{"cloud", "module", "upstream_url", "pinned_version", "chart", "status", "variables_total", "variables_covered", "outputs_total", "outputs_covered", "resource_types_total", "resource_types_with_stable_kind", "resource_types_missing", "pct_variables", "pct_outputs", "notes"})
	for _, r := range res.Rows {
		stable, missing := "", ""
		if r.KindsKnown {
			stable, missing = strconv.Itoa(r.TypesStable), strconv.Itoa(r.TypesMissing)
		}
		w.Write([]string{r.Cloud, r.Module, r.URL, r.Version, r.Chart, r.Status,
			strconv.Itoa(r.VarsTotal), strconv.Itoa(r.VarsCovered), strconv.Itoa(r.OutsTotal), strconv.Itoa(r.OutsCovered),
			strconv.Itoa(r.TypesTotal), stable, missing, Pct(r.VarsCovered, r.VarsTotal), Pct(r.OutsCovered, r.OutsTotal), r.Notes})
	}
	w.Flush()
	files[Dir+"/modules.csv"] = append([]byte(nil), b.Bytes()...)

	b.Reset()
	w = csv.NewWriter(&b)
	w.Write([]string{"cloud", "module", "variable", "type", "covered", "refused_reason", "gap_kind"})
	for _, v := range res.Vars {
		w.Write([]string{v.Cloud, v.Module, v.Variable, v.Type, v.Covered, v.Reason, v.GapKind})
	}
	w.Flush()
	files[Dir+"/variables.csv"] = append([]byte(nil), b.Bytes()...)

	b.Reset()
	w = csv.NewWriter(&b)
	w.Write([]string{"cloud", "module", "output", "covered"})
	for _, o := range res.Outs {
		w.Write([]string{o.Cloud, o.Module, o.Output, o.Covered})
	}
	w.Flush()
	files[Dir+"/outputs.csv"] = append([]byte(nil), b.Bytes()...)

	b.Reset()
	w = csv.NewWriter(&b)
	w.Write([]string{"cloud", "module", "resource_type", "class", "kind"})
	for _, t := range res.Types {
		w.Write([]string{t.Cloud, t.Module, t.Type, t.Class, t.Kind})
	}
	w.Flush()
	files[Dir+"/resource-types.csv"] = append([]byte(nil), b.Bytes()...)

	// Bars: the total, one per cloud, and one per module the README shows.
	files[Dir+"/total.svg"] = segmentedBar(statusCounts(res.Rows, ""), "All tracked modules")
	for _, c := range []string{"gcp", "aws", "azure"} {
		files[Dir+"/"+c+".svg"] = segmentedBar(statusCounts(res.Rows, c), cloudName(c))
	}
	for _, r := range shown(res) {
		files[barPath(r)] = progressBar(r)
	}
	return files, nil
}

func barPath(r Row) string { return Dir + "/bars/" + r.Cloud + "-" + r.Module + ".svg" }

type counts map[string]int

func statusCounts(rows []Row, cloud string) counts {
	c := counts{}
	for _, r := range rows {
		if cloud == "" || r.Cloud == cloud {
			c[r.Status]++
		}
	}
	return c
}

func (c counts) total() int {
	n := 0
	for _, v := range c {
		n += v
	}
	return n
}

// shown are the rows the README lists: every chart; then, per cloud, the
// first blocked and not-started modules by rank.
const topN = 10

func shown(res *Result) []Row {
	var out []Row
	taken := map[string]int{}
	for _, r := range res.Rows {
		if r.Status == Ported || r.Status == Partial {
			out = append(out, r)
			continue
		}
		k := r.Cloud + "/" + r.Status
		if taken[k] < topN {
			taken[k]++
			out = append(out, r)
		}
	}
	return out
}

func segmentedBar(c counts, label string) []byte {
	const w, h = 480, 18
	total := c.total()
	var b bytes.Buffer
	desc := label + ": "
	var parts []string
	for _, s := range statuses {
		parts = append(parts, fmt.Sprintf("%d %s", c[s], s))
	}
	desc += strings.Join(parts, ", ") + fmt.Sprintf(" of %d modules", total)
	fmt.Fprintf(&b, `<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" role="img" aria-label="%s">`+"\n", w, h, w, h, esc(desc))
	fmt.Fprintf(&b, "<title>%s</title>\n", esc(desc))
	fmt.Fprintf(&b, `<clipPath id="r"><rect width="%d" height="%d" rx="4"/></clipPath>`+"\n", w, h)
	fmt.Fprintf(&b, `<g clip-path="url(#r)"><rect width="%d" height="%d" fill="%s" fill-opacity="0.25"/>`+"\n", w, h, trackColour)
	x, cum := 0, 0
	for _, s := range statuses {
		if c[s] == 0 || total == 0 {
			continue
		}
		cum += c[s]
		next := int(float64(w)*float64(cum)/float64(total) + 0.5)
		if next > x {
			fmt.Fprintf(&b, `<rect x="%d" width="%d" height="%d" fill="%s"/>`+"\n", x, next-x, h, statusColour[s])
		}
		x = next
	}
	b.WriteString("</g>\n</svg>\n")
	return b.Bytes()
}

func progressBar(r Row) []byte {
	const w, h = 160, 12
	desc := fmt.Sprintf("%s %s: %d of %d variables covered (%s)", r.Cloud, r.Module, r.VarsCovered, r.VarsTotal, r.Status)
	var b bytes.Buffer
	fmt.Fprintf(&b, `<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" role="img" aria-label="%s">`+"\n", w, h, w, h, esc(desc))
	fmt.Fprintf(&b, "<title>%s</title>\n", esc(desc))
	fmt.Fprintf(&b, `<clipPath id="r"><rect width="%d" height="%d" rx="3"/></clipPath>`+"\n", w, h)
	fmt.Fprintf(&b, `<g clip-path="url(#r)"><rect width="%d" height="%d" fill="%s" fill-opacity="0.25"/>`+"\n", w, h, trackColour)
	if r.VarsTotal > 0 && r.VarsCovered > 0 {
		fw := int(float64(w)*float64(r.VarsCovered)/float64(r.VarsTotal) + 0.5)
		if fw < 2 {
			fw = 2
		}
		fmt.Fprintf(&b, `<rect width="%d" height="%d" fill="%s"/>`+"\n", fw, h, statusColour[r.Status])
	}
	b.WriteString("</g>\n</svg>\n")
	return b.Bytes()
}

func esc(s string) string {
	return strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&quot;").Replace(s)
}

// Readme renders the README section, markers included.
func Readme(res *Result) string {
	var b strings.Builder
	b.WriteString(StartMarker + "\n")
	b.WriteString("## Coverage against the open-source modules\n\n")
	b.WriteString("How much of the Terraform modules people use today the catalog carries, counted from each module's `variables.tf` and `outputs.tf` at the release pinned in [`upstream/modules.yaml`](upstream/modules.yaml). Method, columns and the full per-module data: [`docs/coverage/`](docs/coverage/README.md).\n\n")

	all := statusCounts(res.Rows, "")
	fmt.Fprintf(&b, "![All tracked modules](docs/coverage/total.svg)\n\n")
	fmt.Fprintf(&b, "**%d modules tracked**: %s. Green is ported, amber partial (some variables refused with a message that names the gap), dark grey blocked (a resource type of the module has no stable kind: none, or only an alpha one), light grey not started.\n\n", all.total(), countText(all))

	b.WriteString("| Source | Modules | Bar | Variables covered |\n| --- | ---: | --- | ---: |\n")
	allV, allC := 0, 0
	for _, c := range []string{"gcp", "aws", "azure"} {
		cc := statusCounts(res.Rows, c)
		vt, vc := 0, 0
		for _, r := range res.Rows {
			if r.Cloud == c {
				vt += r.VarsTotal
				vc += r.VarsCovered
			}
		}
		allV, allC = allV+vt, allC+vc
		fmt.Fprintf(&b, "| %s | %d | ![%s](docs/coverage/%s.svg) | %d of %d (%s%%) |\n", cloudName(c), cc.total(), c, c, vc, vt, Pct(vc, vt))
	}
	fmt.Fprintf(&b, "| **All** | **%d** | | **%d of %d (%s%%)** |\n", all.total(), allC, allV, Pct(allC, allV))
	b.WriteString("\n")

	for _, c := range []string{"gcp", "aws", "azure"} {
		fmt.Fprintf(&b, "### %s\n\n", cloudName(c))
		cc := statusCounts(res.Rows, c)
		fmt.Fprintf(&b, "%s.\n\n", countText(cc))
		for _, group := range []struct {
			title string
			match func(string) bool
		}{
			{"Ported and partial", func(s string) bool { return s == Ported || s == Partial }},
			{"Blocked: a resource type has no stable kind", func(s string) bool { return s == Blocked }},
			{"Not started", func(s string) bool { return s == NotStarted }},
		} {
			var rows []Row
			total := 0
			for _, r := range res.Rows {
				if r.Cloud == c && group.match(r.Status) {
					total++
					if len(rows) < topN || r.Status == Ported || r.Status == Partial {
						rows = append(rows, r)
					}
				}
			}
			if total == 0 {
				continue
			}
			title := group.title
			if total > len(rows) {
				title += fmt.Sprintf(" (first %d of %d, by rank)", len(rows), total)
			}
			fmt.Fprintf(&b, "**%s**\n\n", title)
			if c == "gcp" {
				b.WriteString("| Module | Variables covered | Outputs | Resource types with a stable kind | Status |\n| --- | --- | ---: | ---: | --- |\n")
			} else {
				b.WriteString("| Module | Variables covered | Outputs | Resource types | Status |\n| --- | --- | ---: | ---: | --- |\n")
			}
			for _, r := range rows {
				kinds := fmt.Sprintf("%d", r.TypesTotal)
				if r.KindsKnown {
					kinds = fmt.Sprintf("%d of %d", r.TypesStable, r.TypesTotal)
				}
				name := fmt.Sprintf("[`%s`](%s)", r.Module, r.URL)
				if r.Chart != "" {
					name += fmt.Sprintf(" ([chart](%s))", r.Chart)
				}
				fmt.Fprintf(&b, "| %s | ![%s](%s) %d of %d | %d of %d | %s | %s |\n", name, r.Module, barPath(r), r.VarsCovered, r.VarsTotal, r.OutsCovered, r.OutsTotal, kinds, r.Status)
			}
			b.WriteString("\n")
		}
	}
	b.WriteString("Every module, variable and output: [`modules.csv`](docs/coverage/modules.csv), [`variables.csv`](docs/coverage/variables.csv), [`outputs.csv`](docs/coverage/outputs.csv), [`resource-types.csv`](docs/coverage/resource-types.csv). `task coverage` regenerates this section and those files; `task coverage-check` fails when they are out of date.\n")
	b.WriteString(EndMarker)
	return b.String()
}

func countText(c counts) string {
	var parts []string
	for _, s := range statuses {
		parts = append(parts, fmt.Sprintf("%d %s", c[s], s))
	}
	return strings.Join(parts, ", ")
}

// SpliceReadme returns readme with the section between the markers replaced.
func SpliceReadme(readme, section string) (string, error) {
	i := strings.Index(readme, StartMarker)
	j := strings.Index(readme, EndMarker)
	if i < 0 || j < i {
		return "", fmt.Errorf("README.md needs the markers %s and %s", StartMarker, EndMarker)
	}
	return readme[:i] + section + readme[j+len(EndMarker):], nil
}

// Write writes the files (removing stale bars) and splices the README, or,
// with check, returns an error naming every output that differs.
func Write(root string, files map[string][]byte, readmeSection string, check bool) error {
	var diffs []string
	readmePath := filepath.Join(root, "README.md")
	cur, err := os.ReadFile(readmePath)
	if err != nil {
		return err
	}
	next, err := SpliceReadme(string(cur), readmeSection)
	if err != nil {
		return err
	}
	if next != string(cur) {
		diffs = append(diffs, "README.md (coverage section)")
		if !check {
			if err := os.WriteFile(readmePath, []byte(next), 0o644); err != nil {
				return err
			}
		}
	}
	for p, data := range files {
		full := filepath.Join(root, filepath.FromSlash(p))
		old, err := os.ReadFile(full)
		if err == nil && bytes.Equal(old, data) {
			continue
		}
		diffs = append(diffs, p)
		if !check {
			if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
				return err
			}
			if err := os.WriteFile(full, data, 0o644); err != nil {
				return err
			}
		}
	}
	// Bars no longer shown.
	bars, _ := filepath.Glob(filepath.Join(root, Dir, "bars", "*.svg"))
	for _, full := range bars {
		rel, _ := filepath.Rel(root, full)
		rel = filepath.ToSlash(rel)
		if _, ok := files[rel]; !ok {
			diffs = append(diffs, rel+" (stale)")
			if !check {
				os.Remove(full)
			}
		}
	}
	if check && len(diffs) > 0 {
		sort.Strings(diffs)
		return fmt.Errorf("docs/coverage is out of date (run `task coverage`):\n  %s", strings.Join(diffs, "\n  "))
	}
	return nil
}
