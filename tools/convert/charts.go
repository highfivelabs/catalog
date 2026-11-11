// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

// Package convert turns a Terraform module call (or a tfvars file) for one
// of the catalog's ported modules into the Bundt documents that replace it:
// a Template whose component carries the arguments, a Stack, and an
// Instance whose values carry what differs per environment. It validates
// the result against the chart's values.schema.json and says, for every
// argument or value it cannot carry, which gap stops it.
package convert

import (
	"fmt"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strings"

	"gopkg.in/yaml.v3"

	"github.com/highfivelabs/catalog/tools/upstream"
)

// Chart is what the converter needs to know about one ported chart.
type Chart struct {
	Dir         string // relative to the repository root
	Name        string // charts/gcp/<name>
	Package     string // the Bundt Package name, gcp-gcs
	Version     string // the chart's version
	Module      *upstream.Module
	Upstream    *upstream.ChartUpstream
	Values      map[string]any // values.yaml
	SchemaPath  string         // "" when the chart has none
	Outputs     []string       // the Package's outputs, sorted
	Refused     map[string]upstream.Refused
	ValuesOrder []string
}

// Repo is the repository's modules and charts.
type Repo struct {
	Root    string
	Modules *upstream.File
}

// OpenRepo reads upstream/modules.yaml under root.
func OpenRepo(root string) (*Repo, error) {
	f, err := upstream.Load(filepath.Join(root, "upstream", "modules.yaml"))
	if err != nil {
		return nil, err
	}
	return &Repo{Root: root, Modules: f}, nil
}

// ChartByName finds a ported chart by its directory name (gcs).
func (r *Repo) ChartByName(name string) (*Chart, error) {
	for i := range r.Modules.Modules {
		m := &r.Modules.Modules[i]
		if m.Chart != "" && path.Base(m.Chart) == name {
			return r.loadChart(m)
		}
	}
	return nil, fmt.Errorf("no chart named %q (charts: %s)", name, strings.Join(r.chartNames(), ", "))
}

func (r *Repo) chartNames() []string {
	var n []string
	for _, m := range r.Modules.Modules {
		if m.Chart != "" {
			n = append(n, path.Base(m.Chart))
		}
	}
	return n
}

var (
	fabricModule = regexp.MustCompile(`(?:^|/)modules/([a-z0-9-]+)(?:$|[/?])`)
	awsRegistry  = regexp.MustCompile(`^(?:registry\.terraform\.io/)?terraform-aws-modules/([a-z0-9-]+)/aws(?:$|//)`)
	azRegistry   = regexp.MustCompile(`^(?:registry\.terraform\.io/)?Azure/([a-z0-9-]+)/(azurerm|azure)(?:$|//)`)
	awsGit       = regexp.MustCompile(`terraform-aws-modules/terraform-aws-([a-z0-9-]+)`)
	azGit        = regexp.MustCompile(`Azure/terraform-(?:azurerm|azure)-([a-z0-9-]+)`)
)

// Resolve finds the tracked module a `source` argument names, and its
// chart (nil when none ports it). ref is the version the source pins, "".
func (r *Repo) Resolve(source string) (m *upstream.Module, ref string, err error) {
	m, ref, _, err = r.ResolveCall(source)
	return m, ref, err
}

// ResolveCall is Resolve, and also gives the inputs a variant module adds
// (a sibling module whose chart is its base's: sources.go, variants).
func (r *Repo) ResolveCall(source string) (m *upstream.Module, ref string, extra Ordered, err error) {
	src := strings.TrimPrefix(source, "git::")
	if i := strings.Index(src, "?ref="); i >= 0 {
		ref = src[i+5:]
		if j := strings.IndexAny(ref, "&#"); j >= 0 {
			ref = ref[:j]
		}
	}
	if tm, ex, ok, terr := r.resolveTGM(strings.SplitN(src, "?", 2)[0]); ok {
		return tm, ref, ex, terr
	}
	var id string
	switch {
	case awsRegistry.MatchString(src):
		id = "aws/" + awsRegistry.FindStringSubmatch(src)[1]
	case awsGit.MatchString(src):
		id = "aws/" + awsGit.FindStringSubmatch(src)[1]
	case azRegistry.MatchString(src):
		id = "azure/" + azRegistry.FindStringSubmatch(src)[1]
	case azGit.MatchString(src):
		id = "azure/" + azGit.FindStringSubmatch(src)[1]
	case fabricModule.MatchString(src):
		// Fabric: a git URL, or a path to a local copy of its modules/ directory.
		id = "gcp/" + fabricModule.FindStringSubmatch(src)[1]
	default:
		return nil, ref, nil, fmt.Errorf("source %q is not a module the catalog tracks (fabric's modules/<name>, terraform-google-modules, terraform-aws-modules, Azure Verified Modules)", source)
	}
	m = r.Modules.Find(id)
	if m == nil {
		return nil, ref, nil, fmt.Errorf("source %q: %s is not in upstream/modules.yaml", source, id)
	}
	return m, ref, nil, nil
}

func (r *Repo) loadChart(m *upstream.Module) (*Chart, error) {
	dir := filepath.Join(r.Root, m.Chart)
	c := &Chart{Dir: m.Chart, Name: path.Base(m.Chart), Module: m}
	cu, err := upstream.LoadChart(dir)
	if err != nil {
		return nil, err
	}
	c.Upstream = cu
	c.Refused = map[string]upstream.Refused{}
	for _, x := range cu.Refused {
		c.Refused[x.Variable] = x
	}
	data, err := os.ReadFile(filepath.Join(dir, "Chart.yaml"))
	if err != nil {
		return nil, err
	}
	var ch struct {
		Version string `yaml:"version"`
	}
	if err := yaml.Unmarshal(data, &ch); err != nil {
		return nil, err
	}
	c.Version = ch.Version
	data, err = os.ReadFile(filepath.Join(dir, "package.yaml"))
	if err != nil {
		return nil, err
	}
	var pkg struct {
		Metadata struct {
			Name string `yaml:"name"`
		} `yaml:"metadata"`
		Spec struct {
			Outputs map[string]any `yaml:"outputs"`
		} `yaml:"spec"`
	}
	if err := yaml.Unmarshal(data, &pkg); err != nil {
		return nil, err
	}
	c.Package = pkg.Metadata.Name
	for k := range pkg.Spec.Outputs {
		c.Outputs = append(c.Outputs, k)
	}
	sortStrings(c.Outputs)
	data, err = os.ReadFile(filepath.Join(dir, "values.yaml"))
	if err != nil {
		return nil, err
	}
	if err := yaml.Unmarshal(data, &c.Values); err != nil {
		return nil, err
	}
	if _, err := os.Stat(filepath.Join(dir, "values.schema.json")); err == nil {
		c.SchemaPath = filepath.Join(dir, "values.schema.json")
	}
	return c, nil
}

func sortStrings(s []string) {
	for i := 1; i < len(s); i++ {
		for j := i; j > 0 && s[j] < s[j-1]; j-- {
			s[j], s[j-1] = s[j-1], s[j]
		}
	}
}
