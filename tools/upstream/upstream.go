// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

// Package upstream reads and checks where the catalog's charts came from:
// upstream/modules.yaml (every Terraform module the catalog tracks, with
// its pin) and each chart's upstream.yaml (the chart's own record of the
// module and release it was ported from).
package upstream

import (
	"bytes"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// Module is one entry of upstream/modules.yaml.
type Module struct {
	ID          string `yaml:"id"`
	Cloud       string `yaml:"cloud"`
	Module      string `yaml:"module"`
	Rank        int    `yaml:"rank"`
	Repo        string `yaml:"repo"`
	Path        string `yaml:"path"`
	TagPattern  string `yaml:"tag_pattern"`
	Version     string `yaml:"version"`
	Commit      string `yaml:"commit"`
	License     string `yaml:"license"`
	Copyright   string `yaml:"copyright"`
	RegistryURL string `yaml:"registry_url"`
	URL         string `yaml:"url"`
	Chart       string `yaml:"chart"`
}

// Excluded is a module that is deliberately not tracked.
type Excluded struct {
	Module string `yaml:"module"`
	Reason string `yaml:"reason"`
}

// File is upstream/modules.yaml.
type File struct {
	Schema   int        `yaml:"schema"`
	Modules  []Module   `yaml:"modules"`
	Excluded []Excluded `yaml:"excluded"`
}

// ChartUpstream is a chart's upstream.yaml.
type ChartUpstream struct {
	Module      string `yaml:"module"`
	Repo        string `yaml:"repo"`
	Path        string `yaml:"path"`
	Version     string `yaml:"version"`
	Commit      string `yaml:"commit"`
	License     string `yaml:"license"`
	Copyright   string `yaml:"copyright"`
	ModuleURL   string `yaml:"module_url"`
	RegistryURL string `yaml:"registry_url"`
	Synced      string `yaml:"synced"`
	// Refused are the module variables the chart keeps in its values but
	// refuses when set (docs/coverage reads them).
	Refused []Refused `yaml:"refused,omitempty"`
}

// Refused is a module variable the chart refuses, wholly or in part.
type Refused struct {
	Variable string `yaml:"variable"`
	// Kind is why: gap (Config Connector has no kind or field), alpha (only
	// a v1alpha1 kind), not-ported (Config Connector has it; the chart does
	// not map it yet) or by-design (Bundt replaces it).
	Kind   string `yaml:"kind"`
	Reason string `yaml:"reason"`
	// Partial marks a variable the chart accepts, with some of its fields
	// (or values) refused: the reason says which.
	Partial bool `yaml:"partial,omitempty"`
}

// Decode strictly decodes YAML into v: unknown fields are an error.
func Decode(data []byte, v any) error {
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	return dec.Decode(v)
}

// Load reads upstream/modules.yaml.
func Load(file string) (*File, error) {
	data, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}
	var f File
	if err := Decode(data, &f); err != nil {
		return nil, fmt.Errorf("%s: %w", file, err)
	}
	return &f, nil
}

// LoadChart reads a chart's upstream.yaml.
func LoadChart(chartDir string) (*ChartUpstream, error) {
	file := filepath.Join(chartDir, "upstream.yaml")
	data, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}
	var c ChartUpstream
	if err := Decode(data, &c); err != nil {
		return nil, fmt.Errorf("%s: %w", file, err)
	}
	return &c, nil
}

// Find returns the entry with the given id.
func (f *File) Find(id string) *Module {
	for i := range f.Modules {
		if f.Modules[i].ID == id {
			return &f.Modules[i]
		}
	}
	return nil
}

// Slug is the repository's "owner/name".
func (m *Module) Slug() string {
	return strings.TrimPrefix(m.Repo, "https://github.com/")
}

// TreeURL is the module's page at the given tag.
func (m *Module) TreeURL(tag string) string {
	p := ""
	if m.Path != "." && m.Path != "" {
		p = "/" + m.Path
	}
	return m.Repo + "/tree/" + tag + p
}

var (
	shaRE  = regexp.MustCompile(`^[0-9a-f]{40}$`)
	dateRE = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`)
)

// Problems checks modules.yaml on its own.
func (f *File) Problems(root string) []string {
	var p []string
	bad := func(format string, a ...any) { p = append(p, fmt.Sprintf(format, a...)) }
	if f.Schema != 1 {
		bad("modules.yaml: schema is %d, want 1", f.Schema)
	}
	seen := map[string]bool{}
	charts := map[string]string{}
	ranks := map[string]string{}
	for _, m := range f.Modules {
		who := m.ID
		if who == "" {
			bad("an entry has no id (module %q)", m.Module)
			continue
		}
		if seen[who] {
			bad("%s: listed twice", who)
		}
		seen[who] = true
		if want := m.Cloud + "/" + m.Module; who != want {
			bad("%s: id should be cloud/module, %s", who, want)
		}
		if !strings.HasPrefix(m.Repo, "https://github.com/") {
			bad("%s: repo %q is not a github.com URL", who, m.Repo)
		}
		if m.Path == "" || strings.HasPrefix(m.Path, "/") {
			bad("%s: path %q: use a relative directory, or . for the root", who, m.Path)
		}
		if ok, _ := path.Match(m.TagPattern, m.Version); !ok || m.TagPattern == "" {
			bad("%s: version %s does not match tag_pattern %q", who, m.Version, m.TagPattern)
		}
		if !shaRE.MatchString(m.Commit) {
			bad("%s: commit %q is not a 40-digit hex SHA", who, m.Commit)
		}
		if m.License == "" || m.Copyright == "" && m.Cloud != "aws" {
			bad("%s: license and copyright are needed (copyright may be null only for terraform-aws-modules, which carry no copyright line)", who)
		}
		if !strings.HasPrefix(m.URL, m.Repo+"/tree/"+m.Version) {
			bad("%s: url %q is not the module's page at %s", who, m.URL, m.Version)
		}
		if m.RegistryURL != "" && !strings.HasPrefix(m.RegistryURL, "https://registry.terraform.io/modules/") {
			bad("%s: registry_url %q", who, m.RegistryURL)
		}
		if m.Rank < 1 {
			bad("%s: rank is needed", who)
		}
		rk := fmt.Sprintf("%s#%d", m.Cloud, m.Rank)
		if other, dup := ranks[rk]; dup {
			bad("%s: rank %d is also %s's", who, m.Rank, other)
		}
		ranks[rk] = who
		if m.Chart != "" {
			if other, dup := charts[m.Chart]; dup {
				bad("%s: chart %s is also claimed by %s", who, m.Chart, other)
			}
			charts[m.Chart] = who
			if st, err := os.Stat(filepath.Join(root, m.Chart)); err != nil || !st.IsDir() {
				bad("%s: chart %s does not exist", who, m.Chart)
			}
		}
	}
	return p
}

// CheckChart checks a chart's upstream.yaml against modules.yaml and the
// chart's own Chart.yaml. root is the repository root; chartDir is relative
// to it (charts/gcp/gcs).
func CheckChart(root string, f *File, chartDir string) []string {
	var p []string
	bad := func(format string, a ...any) { p = append(p, chartDir+": "+fmt.Sprintf(format, a...)) }
	cu, err := LoadChart(filepath.Join(root, chartDir))
	if err != nil {
		return []string{chartDir + ": " + err.Error()}
	}
	m := f.Find(cu.Module)
	if m == nil {
		return []string{fmt.Sprintf("%s: upstream.yaml names module %q, which upstream/modules.yaml does not list", chartDir, cu.Module)}
	}
	if m.Chart != chartDir {
		bad("upstream/modules.yaml says %s is ported by %q, not this chart", m.ID, m.Chart)
	}
	same := func(field, a, b string) {
		if a != b {
			bad("upstream.yaml %s is %q, upstream/modules.yaml has %q", field, a, b)
		}
	}
	same("repo", cu.Repo, m.Repo)
	same("path", cu.Path, m.Path)
	same("version", cu.Version, m.Version)
	same("commit", cu.Commit, m.Commit)
	same("license", cu.License, m.License)
	same("copyright", cu.Copyright, m.Copyright)
	same("registry_url", cu.RegistryURL, m.RegistryURL)
	same("module_url", cu.ModuleURL, m.URL)
	if _, err := time.Parse("2006-01-02", cu.Synced); err != nil || !dateRE.MatchString(cu.Synced) {
		bad("upstream.yaml synced %q is not a date (YYYY-MM-DD)", cu.Synced)
	}
	// The chart's own metadata names the same release.
	data, err := os.ReadFile(filepath.Join(root, chartDir, "Chart.yaml"))
	if err != nil {
		return append(p, chartDir+": "+err.Error())
	}
	var ch struct {
		AppVersion  string            `yaml:"appVersion"`
		Annotations map[string]string `yaml:"annotations"`
	}
	if err := yaml.Unmarshal(data, &ch); err != nil {
		return append(p, chartDir+"/Chart.yaml: "+err.Error())
	}
	if got := ch.Annotations["hfl.dev/source-version"]; got != m.Version {
		bad("Chart.yaml hfl.dev/source-version is %q, upstream.yaml has %q", got, m.Version)
	}
	if got := ch.Annotations["hfl.dev/source-commit"]; got != m.Commit {
		bad("Chart.yaml hfl.dev/source-commit is %q, upstream.yaml has %q", got, m.Commit)
	}
	wantSrc := path.Base(m.Repo) + "/" + m.Path
	if m.Path == "." {
		wantSrc = path.Base(m.Repo)
	}
	if got := ch.Annotations["hfl.dev/source"]; got != wantSrc {
		bad("Chart.yaml hfl.dev/source is %q, want %q", got, wantSrc)
	}
	return p
}

// Charts lists the chart directories (charts/<cloud>/<name>), relative to root.
func Charts(root string) ([]string, error) {
	m, err := filepath.Glob(filepath.Join(root, "charts", "*", "*", "Chart.yaml"))
	if err != nil {
		return nil, err
	}
	var out []string
	for _, c := range m {
		rel, _ := filepath.Rel(root, filepath.Dir(c))
		out = append(out, filepath.ToSlash(rel))
	}
	sort.Strings(out)
	return out, nil
}

// CheckAll runs every check: modules.yaml, and each chart (or the named
// ones). Every chart on disk must be claimed by an entry.
func CheckAll(root string, only []string) ([]string, error) {
	f, err := Load(filepath.Join(root, "upstream", "modules.yaml"))
	if err != nil {
		return nil, err
	}
	p := f.Problems(root)
	charts, err := Charts(root)
	if err != nil {
		return nil, err
	}
	if len(only) > 0 {
		charts = only
	}
	for _, c := range charts {
		p = append(p, CheckChart(root, f, c)...)
	}
	if len(only) == 0 {
		for _, m := range f.Modules {
			if m.Chart == "" {
				continue
			}
			if _, err := os.Stat(filepath.Join(root, m.Chart, "upstream.yaml")); err != nil {
				p = append(p, fmt.Sprintf("%s: %s has no upstream.yaml", m.Chart, m.ID))
			}
		}
	}
	return p, nil
}
