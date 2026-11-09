// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

// Package watch finds which tracked upstream modules have a newer release
// than the one pinned in upstream/modules.yaml, and what changed in each:
// the variables, outputs and resource types added, removed or changed, and
// how many of the module's Terraform files differ.
//
// It only reads upstream: `git ls-remote --tags` and GETs of public
// tarballs, spaced apart. It never writes to, comments on or opens anything
// in an upstream repository.
package watch

import (
	"crypto/sha256"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/highfivelabs/catalog/tools/tfmod"
	"github.com/highfivelabs/catalog/tools/upstream"
)

// Change is a variable whose declaration changed.
type Change struct {
	Name string `json:"name"`
	What string `json:"what"`
}

// Diff is the interface difference between two releases of a module.
type Diff struct {
	VariablesAdded     []string `json:"variables_added,omitempty"`
	VariablesRemoved   []string `json:"variables_removed,omitempty"`
	VariablesChanged   []Change `json:"variables_changed,omitempty"`
	OutputsAdded       []string `json:"outputs_added,omitempty"`
	OutputsRemoved     []string `json:"outputs_removed,omitempty"`
	ResourceTypesAdded []string `json:"resource_types_added,omitempty"`
	ResourceTypesGone  []string `json:"resource_types_removed,omitempty"`
	// FilesChanged are the Terraform files (relative to the module) that
	// differ, added or removed; the interface can stay the same while the
	// behaviour changes.
	FilesChanged []string `json:"files_changed,omitempty"`
}

// Empty says nothing changed in the module's Terraform at all.
func (d Diff) Empty() bool { return d.InterfaceEmpty() && len(d.FilesChanged) == 0 }

// InterfaceEmpty says the variables, outputs and resource types are the same.
func (d Diff) InterfaceEmpty() bool {
	return len(d.VariablesAdded)+len(d.VariablesRemoved)+len(d.VariablesChanged)+
		len(d.OutputsAdded)+len(d.OutputsRemoved)+len(d.ResourceTypesAdded)+len(d.ResourceTypesGone) == 0
}

// Entry is a module with a newer release.
type Entry struct {
	ID             string `json:"id"`
	Cloud          string `json:"cloud"`
	Module         string `json:"module"`
	Rank           int    `json:"rank"`
	Chart          string `json:"chart,omitempty"`
	Pinned         string `json:"pinned"`
	Latest         string `json:"latest"`
	LatestCommit   string `json:"latest_commit"`
	ReleasesBehind int    `json:"releases_behind"`
	CompareURL     string `json:"compare_url"`
	ReleaseNotes   string `json:"release_notes_url"`
	ModuleURL      string `json:"module_url"`
	RegistryURL    string `json:"registry_url,omitempty"`
	Diff           Diff   `json:"diff"`
	// Error is set when the diff could not be computed.
	Error string `json:"error,omitempty"`
}

// Report is the result of a run.
type Report struct {
	Date      string   `json:"date"`
	Checked   int      `json:"modules_checked"`
	UpToDate  int      `json:"modules_up_to_date"`
	Behind    []Entry  `json:"behind"`
	Unchecked []string `json:"unchecked,omitempty"`
}

// Options for Run.
type Options struct {
	Root     string
	CacheDir string
	Date     string
	// Only limits the run to these module ids (empty: all).
	Only []string
	// Progress, if set, is called with a line per repository checked.
	Progress func(string)
}

// Run checks every tracked module.
func Run(o Options) (*Report, error) {
	f, err := upstream.Load(filepath.Join(o.Root, "upstream", "modules.yaml"))
	if err != nil {
		return nil, err
	}
	rep := &Report{Date: o.Date}
	only := map[string]bool{}
	for _, id := range o.Only {
		only[id] = true
	}
	progress := o.Progress
	if progress == nil {
		progress = func(string) {}
	}

	// One ls-remote for each repository and tag pattern.
	type key struct{ repo, pattern string }
	tagCache := map[key][]upstream.Tag{}
	tagErr := map[key]error{}
	var moved []Entry
	for _, m := range f.Modules {
		if len(only) > 0 && !only[m.ID] {
			continue
		}
		k := key{m.Repo, m.TagPattern}
		tags, seen := tagCache[k]
		if !seen && tagErr[k] == nil {
			progress("ls-remote " + m.Repo)
			tags, err = upstream.ListTags(m.Repo, m.TagPattern)
			if err != nil {
				tagErr[k] = err
			} else {
				tagCache[k] = tags
			}
		}
		if tagErr[k] != nil {
			rep.Unchecked = append(rep.Unchecked, fmt.Sprintf("%s: %v", m.ID, tagErr[k]))
			continue
		}
		rep.Checked++
		pinned, ok := upstream.ParseSemver(m.Version)
		if !ok {
			rep.Unchecked = append(rep.Unchecked, fmt.Sprintf("%s: pinned version %q is not X.Y.Z", m.ID, m.Version))
			continue
		}
		if len(tags) == 0 {
			rep.Unchecked = append(rep.Unchecked, fmt.Sprintf("%s: no release tags match %q in %s", m.ID, m.TagPattern, m.Repo))
			continue
		}
		latest := tags[len(tags)-1]
		if !upstream.Less(pinned, latest.Semver) {
			rep.UpToDate++
			continue
		}
		behind := 0
		for _, t := range tags {
			if upstream.Less(pinned, t.Semver) {
				behind++
			}
		}
		moved = append(moved, Entry{
			ID: m.ID, Cloud: m.Cloud, Module: m.Module, Rank: m.Rank, Chart: m.Chart,
			Pinned: m.Version, Latest: latest.Name, LatestCommit: latest.Commit, ReleasesBehind: behind,
			CompareURL:   fmt.Sprintf("%s/compare/%s...%s", m.Repo, m.Version, latest.Name),
			ReleaseNotes: fmt.Sprintf("%s/releases/tag/%s", m.Repo, latest.Name),
			ModuleURL:    m.TreeURL(latest.Name), RegistryURL: m.RegistryURL,
		})
	}

	// Fetch both releases once per repository, then diff each module.
	type rel struct{ slug, tag string }
	paths := map[rel][]string{}
	mods := map[string]upstream.Module{}
	for _, m := range f.Modules {
		mods[m.ID] = m
	}
	for _, e := range moved {
		m := mods[e.ID]
		for _, tag := range []string{e.Pinned, e.Latest} {
			r := rel{m.Slug(), tag}
			paths[r] = append(paths[r], m.Path)
		}
	}
	srcs := map[rel]upstream.Source{}
	failed := map[rel]error{}
	var rels []rel
	for r := range paths {
		rels = append(rels, r)
	}
	sort.Slice(rels, func(i, j int) bool {
		if rels[i].slug != rels[j].slug {
			return rels[i].slug < rels[j].slug
		}
		return rels[i].tag < rels[j].tag
	})
	for _, r := range rels {
		progress(fmt.Sprintf("fetch %s@%s", r.slug, r.tag))
		s, err := upstream.Fetch(o.CacheDir, r.slug, r.tag, paths[r])
		if err != nil {
			failed[r] = err
			continue
		}
		srcs[r] = s
	}
	for i := range moved {
		e := &moved[i]
		m := mods[e.ID]
		oldR, newR := rel{m.Slug(), e.Pinned}, rel{m.Slug(), e.Latest}
		if err := failed[oldR]; err != nil {
			e.Error = err.Error()
			continue
		}
		if err := failed[newR]; err != nil {
			e.Error = err.Error()
			continue
		}
		d, err := Compare(srcs[oldR].ModuleDir(m.Path), srcs[newR].ModuleDir(m.Path))
		if err != nil {
			e.Error = err.Error()
			continue
		}
		e.Diff = *d
	}
	sort.SliceStable(moved, func(i, j int) bool {
		a, b := moved[i], moved[j]
		if (a.Chart != "") != (b.Chart != "") {
			return a.Chart != ""
		}
		if a.Cloud != b.Cloud {
			return a.Cloud < b.Cloud
		}
		return a.Rank < b.Rank
	})
	rep.Behind = moved
	return rep, nil
}

// Compare diffs two extracted releases of one module.
func Compare(oldDir, newDir string) (*Diff, error) {
	a, err := tfmod.ParseDir(oldDir, true)
	if err != nil {
		return nil, fmt.Errorf("the pinned release: %w", err)
	}
	b, err := tfmod.ParseDir(newDir, true)
	if err != nil {
		return nil, fmt.Errorf("the latest release: %w", err)
	}
	d := &Diff{}
	av, bv := map[string]tfmod.Variable{}, map[string]tfmod.Variable{}
	for _, v := range a.Variables {
		av[v.Name] = v
	}
	for _, v := range b.Variables {
		bv[v.Name] = v
	}
	for _, v := range b.Variables {
		o, ok := av[v.Name]
		if !ok {
			what := "optional"
			if v.Required {
				what = "required"
			}
			d.VariablesAdded = append(d.VariablesAdded, fmt.Sprintf("%s (%s, %s)", v.Name, v.Type, what))
			continue
		}
		var what []string
		if o.TypeExpr != v.TypeExpr {
			if o.Type != v.Type {
				what = append(what, fmt.Sprintf("type %s -> %s", o.Type, v.Type))
			} else {
				what = append(what, "type changed inside (same outer shape)")
			}
		}
		if o.Required != v.Required {
			if v.Required {
				what = append(what, "now required")
			} else {
				what = append(what, "now optional")
			}
		}
		if o.DefaultExpr != v.DefaultExpr && o.HasDefault && v.HasDefault {
			what = append(what, fmt.Sprintf("default %s -> %s", abbrev(o.DefaultExpr), abbrev(v.DefaultExpr)))
		}
		if o.Nullable != v.Nullable {
			what = append(what, fmt.Sprintf("nullable %v -> %v", o.Nullable, v.Nullable))
		}
		if len(what) > 0 {
			d.VariablesChanged = append(d.VariablesChanged, Change{v.Name, strings.Join(what, "; ")})
		}
	}
	for _, v := range a.Variables {
		if _, ok := bv[v.Name]; !ok {
			d.VariablesRemoved = append(d.VariablesRemoved, v.Name)
		}
	}
	d.OutputsAdded, d.OutputsRemoved = setDiff(outNames(a), outNames(b))
	d.ResourceTypesAdded, d.ResourceTypesGone = setDiff(a.ResourceTypes, b.ResourceTypes)
	files, err := changedFiles(oldDir, newDir)
	if err != nil {
		return nil, err
	}
	d.FilesChanged = files
	return d, nil
}

func abbrev(s string) string {
	if len(s) > 60 {
		return s[:57] + "..."
	}
	return s
}

func outNames(m *tfmod.Module) []string {
	var n []string
	for _, o := range m.Outputs {
		n = append(n, o.Name)
	}
	return n
}

// setDiff returns what b has that a lacks, and what a has that b lacks.
func setDiff(a, b []string) (added, removed []string) {
	as, bs := map[string]bool{}, map[string]bool{}
	for _, x := range a {
		as[x] = true
	}
	for _, x := range b {
		bs[x] = true
		if !as[x] {
			added = append(added, x)
		}
	}
	for _, x := range a {
		if !bs[x] {
			removed = append(removed, x)
		}
	}
	sort.Strings(added)
	sort.Strings(removed)
	return
}

// changedFiles lists the .tf files (relative paths) added, removed or
// different between two module directories.
func changedFiles(oldDir, newDir string) ([]string, error) {
	oh, err := hashes(oldDir)
	if err != nil {
		return nil, err
	}
	nh, err := hashes(newDir)
	if err != nil {
		return nil, err
	}
	var out []string
	for p, h := range nh {
		if oh[p] != h {
			out = append(out, p)
		}
	}
	for p := range oh {
		if _, ok := nh[p]; !ok {
			out = append(out, p)
		}
	}
	sort.Strings(out)
	return out, nil
}

func hashes(dir string) (map[string]string, error) {
	out := map[string]string{}
	err := filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || !strings.HasSuffix(p, ".tf") {
			return nil
		}
		data, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(dir, p)
		out[filepath.ToSlash(rel)] = fmt.Sprintf("%x", sha256.Sum256(data))
		return nil
	})
	return out, err
}
