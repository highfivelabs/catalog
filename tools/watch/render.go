// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package watch

import (
	"encoding/json"
	"fmt"
	"strings"
)

// JSON is the machine-readable report.
func (r *Report) JSON() ([]byte, error) {
	b, err := json.MarshalIndent(r, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(b, '\n'), nil
}

func (e Entry) summary() string {
	if e.Error != "" {
		return "could not diff: " + e.Error
	}
	d := e.Diff
	if d.Empty() {
		return "none: the tag moved, the module's Terraform did not"
	}
	var p []string
	if n := len(d.VariablesAdded); n > 0 {
		p = append(p, fmt.Sprintf("+%d variables", n))
	}
	if n := len(d.VariablesRemoved); n > 0 {
		p = append(p, fmt.Sprintf("-%d variables", n))
	}
	if n := len(d.VariablesChanged); n > 0 {
		p = append(p, fmt.Sprintf("~%d variables", n))
	}
	if n := len(d.OutputsAdded) + len(d.OutputsRemoved); n > 0 {
		p = append(p, fmt.Sprintf("%d outputs", n))
	}
	if n := len(d.ResourceTypesAdded) + len(d.ResourceTypesGone); n > 0 {
		p = append(p, fmt.Sprintf("%d resource types", n))
	}
	s := strings.Join(p, ", ")
	if s == "" {
		s = "interface unchanged"
	}
	return fmt.Sprintf("%s; %d files", s, len(d.FilesChanged))
}

func (e Entry) links() string {
	return fmt.Sprintf("[compare](%s), [notes](%s)", e.CompareURL, e.ReleaseNotes)
}

func list(b *strings.Builder, title string, items []string, max int) {
	if len(items) == 0 {
		return
	}
	fmt.Fprintf(b, "- %s (%d):", title, len(items))
	for i, x := range items {
		if i == max {
			fmt.Fprintf(b, " … and %d more", len(items)-max)
			break
		}
		if i > 0 {
			b.WriteString(",")
		}
		fmt.Fprintf(b, " `%s`", x)
	}
	b.WriteString("\n")
}

// detail writes one module's differences.
func (e Entry) detail(b *strings.Builder) {
	fmt.Fprintf(b, "### `%s` %s to %s", e.ID, e.Pinned, e.Latest)
	if e.Chart != "" {
		fmt.Fprintf(b, " (chart `%s`)", e.Chart)
	}
	b.WriteString("\n\n")
	fmt.Fprintf(b, "%d release(s) behind. %s, [module page](%s).\n\n", e.ReleasesBehind, e.links(), e.ModuleURL)
	if e.Error != "" {
		fmt.Fprintf(b, "Could not diff: %s\n\n", e.Error)
		return
	}
	d := e.Diff
	if d.Empty() {
		b.WriteString("The tag moved; the module's Terraform files are the same.\n\n")
		return
	}
	list(b, "variables added", d.VariablesAdded, 25)
	list(b, "variables removed", d.VariablesRemoved, 25)
	if len(d.VariablesChanged) > 0 {
		fmt.Fprintf(b, "- variables changed (%d):\n", len(d.VariablesChanged))
		for i, c := range d.VariablesChanged {
			if i == 25 {
				fmt.Fprintf(b, "  - … and %d more\n", len(d.VariablesChanged)-25)
				break
			}
			fmt.Fprintf(b, "  - `%s`: %s\n", c.Name, c.What)
		}
	}
	list(b, "outputs added", d.OutputsAdded, 25)
	list(b, "outputs removed", d.OutputsRemoved, 25)
	list(b, "resource types added", d.ResourceTypesAdded, 25)
	list(b, "resource types removed", d.ResourceTypesGone, 25)
	list(b, "terraform files changed", d.FilesChanged, 12)
	b.WriteString("\n")
}

func (r *Report) hasDetails() bool {
	for _, e := range r.Behind {
		if e.Chart != "" || !e.Diff.Empty() || e.Error != "" {
			return true
		}
	}
	return false
}

func (r *Report) counts() (withChart int) {
	for _, e := range r.Behind {
		if e.Chart != "" {
			withChart++
		}
	}
	return
}

func (r *Report) header(b *strings.Builder) {
	fmt.Fprintf(b, "%d modules checked on %s: %d up to date, **%d with a newer release** (%d with a chart).\n",
		r.Checked, r.Date, r.UpToDate, len(r.Behind), r.counts())
	if len(r.Unchecked) > 0 {
		fmt.Fprintf(b, "%d could not be checked (below).\n", len(r.Unchecked))
	}
	b.WriteString("\n")
}

func (r *Report) table(b *strings.Builder, chart bool) {
	var rows []Entry
	for _, e := range r.Behind {
		if (e.Chart != "") == chart {
			rows = append(rows, e)
		}
	}
	if len(rows) == 0 {
		return
	}
	b.WriteString("| Module | Pinned | Latest | Releases behind | Interface changes | Links |\n| --- | --- | --- | ---: | --- | --- |\n")
	for _, e := range rows {
		fmt.Fprintf(b, "| `%s` | %s | %s | %d | %s | %s |\n", e.ID, e.Pinned, e.Latest, e.ReleasesBehind, e.summary(), e.links())
	}
	b.WriteString("\n")
}

func (r *Report) unchecked(b *strings.Builder) {
	if len(r.Unchecked) == 0 {
		return
	}
	b.WriteString("## Not checked\n\n")
	for _, u := range r.Unchecked {
		fmt.Fprintf(b, "- %s\n", u)
	}
	b.WriteString("\n")
}

// Markdown is docs/upstream-status.md.
func (r *Report) Markdown() string {
	var b strings.Builder
	b.WriteString("# Upstream status\n\n")
	b.WriteString("Which tracked Terraform modules have a release newer than the one pinned in [`upstream/modules.yaml`](../upstream/modules.yaml), and what changed. Written by `task upstream-watch` (read-only: `git ls-remote --tags` and tarball GETs); the same data is in [`upstream-status.json`](upstream-status.json). A daily workflow keeps one issue with this report. This file is refreshed when someone runs the task and commits it; it is a snapshot.\n\n")
	r.header(&b)
	b.WriteString("To take a release: carry its changes into the chart, then `task upstream-bump -- <module> <tag>` (UPSTREAM.md, \"Moving the pins\").\n\n")
	if r.counts() > 0 {
		b.WriteString("## Modules with a chart\n\n")
		r.table(&b, true)
	}
	if len(r.Behind) > r.counts() {
		b.WriteString("## Other modules\n\n")
		r.table(&b, false)
	}
	if r.hasDetails() {
		b.WriteString("## What changed\n\n")
		b.WriteString("Interface differences are read from each module's `variable`, `output` and `resource` blocks; \"files\" counts the module's `.tf` files that differ at all, since behaviour can change with the interface unchanged. Only modules whose Terraform changed are listed; the JSON has all of them.\n\n")
		for _, e := range r.Behind {
			if e.Chart != "" || !e.Diff.Empty() || e.Error != "" {
				e.detail(&b)
			}
		}
	}
	r.unchecked(&b)
	return b.String()
}

// IssueBody is the report for the tracking issue, cut to fit GitHub's
// limit (65,536 characters) with room to spare.
func (r *Report) IssueBody(max int) string {
	var b strings.Builder
	b.WriteString("Written by the `upstream-watch` workflow (`task upstream-watch`). It only reads the upstream repositories. This issue is updated in place; it closes itself when nothing is behind.\n\n")
	r.header(&b)
	if len(r.Behind) > 0 {
		b.WriteString("To take a release: carry its changes into the chart, then `task upstream-bump -- <module> <tag>` and open a pull request (UPSTREAM.md, \"Moving the pins\").\n\n")
	}
	if r.counts() > 0 {
		b.WriteString("## Modules with a chart\n\n")
		r.table(&b, true)
	}
	if len(r.Behind) > r.counts() {
		b.WriteString("## Other modules\n\n")
		r.table(&b, false)
	}
	r.unchecked(&b)
	var details strings.Builder
	for _, e := range r.Behind {
		if e.Chart != "" || !e.Diff.Empty() || e.Error != "" {
			e.detail(&details)
		}
	}
	if details.Len() > 0 {
		b.WriteString("## What changed\n\n")
		d := details.String()
		if room := max - b.Len() - 200; b.Len()+len(d) > max && room < 500 {
			d = "(Left out to fit an issue; the full report is the `upstream-status` artifact of the workflow run.)\n"
		} else if b.Len()+len(d) > max {
			d = d[:room]
			if i := strings.LastIndex(d, "\n### "); i > 0 {
				d = d[:i+1]
			}
			d += "\n(Cut to fit an issue; the full report is the `upstream-status` artifact of the workflow run.)\n"
		}
		b.WriteString(d)
	}
	return b.String()
}
