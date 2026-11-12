// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package convert

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclsyntax"
	"github.com/highfivelabs/catalog/tools/upstream"
)

// ModuleSource is where `terraform init` resolved one module call from:
// an entry of .terraform/modules/modules.json.
type ModuleSource struct {
	Key     string `json:"Key"`
	Source  string `json:"Source"`
	Version string `json:"Version"`
	Dir     string `json:"Dir"`
}

// ReadModulesJSON reads .terraform/modules/modules.json (written by
// `terraform init`) and returns the root module's calls by label. Nested
// calls (vpc.subnets) are left out: a call is converted as a whole.
func ReadModulesJSON(path string) (map[string]ModuleSource, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var f struct {
		Modules []ModuleSource `json:"Modules"`
	}
	if err := json.Unmarshal(b, &f); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	out := map[string]ModuleSource{}
	for _, m := range f.Modules {
		if m.Key == "" || strings.Contains(m.Key, ".") {
			continue
		}
		out[m.Key] = m
	}
	return out, nil
}

var (
	// terraform-google-modules, from the registry or from GitHub.
	tgmRegistry = regexp.MustCompile(`^(?:registry\.terraform\.io/)?terraform-google-modules/([a-z0-9-]+)/google(?://([^?]+))?$`)
	tgmGit      = regexp.MustCompile(`github\.com/terraform-google-modules/terraform-google-([a-z0-9-]+?)(?:\.git)?(?://([^?]+))?(?:\?|$)`)
)

// variant is a module whose inputs are a subset of a ported module's: the
// chart takes it with Inputs added (unless the call sets them itself).
type variant struct {
	ID     string // the ported module's id in upstream/modules.yaml
	Inputs Ordered
}

// variants are the sibling modules a chart carries (its README, "Variants").
var variants = map[string]variant{
	"terraform-google-kubernetes-engine//":                                            {ID: "gcp/kubernetes-engine-beta-private-cluster"},
	"terraform-google-kubernetes-engine//modules/private-cluster":                     {ID: "gcp/kubernetes-engine-beta-private-cluster"},
	"terraform-google-kubernetes-engine//modules/private-cluster-update-variant":      {ID: "gcp/kubernetes-engine-beta-private-cluster"},
	"terraform-google-kubernetes-engine//modules/beta-private-cluster-update-variant": {ID: "gcp/kubernetes-engine-beta-private-cluster"},
	"terraform-google-kubernetes-engine//modules/beta-public-cluster": {ID: "gcp/kubernetes-engine-beta-private-cluster",
		Inputs: Ordered{{"enable_private_nodes", false}}},
	"terraform-google-kubernetes-engine//modules/beta-public-cluster-update-variant": {ID: "gcp/kubernetes-engine-beta-private-cluster",
		Inputs: Ordered{{"enable_private_nodes", false}}},
	"terraform-google-kubernetes-engine//modules/beta-autopilot-private-cluster": {ID: "gcp/kubernetes-engine-beta-private-cluster",
		Inputs: Ordered{{"mode", "autopilot"}}},
	"terraform-google-kubernetes-engine//modules/beta-autopilot-public-cluster": {ID: "gcp/kubernetes-engine-beta-private-cluster",
		Inputs: Ordered{{"mode", "autopilot"}, {"enable_private_nodes", false}}},
}

// resolveTGM finds a terraform-google-modules source in upstream/modules.yaml
// by repository and path, or as a variant of a ported module. ok is false
// when the source is not terraform-google-modules'.
func (r *Repo) resolveTGM(src string) (m *upstream.Module, extra Ordered, ok bool, err error) {
	var name, sub string
	switch {
	case tgmRegistry.MatchString(src):
		g := tgmRegistry.FindStringSubmatch(src)
		name, sub = g[1], g[2]
	case tgmGit.MatchString(src):
		g := tgmGit.FindStringSubmatch(src)
		name, sub = g[1], g[2]
	default:
		return nil, nil, false, nil
	}
	repo := "terraform-google-" + name
	clean := func(p string) string {
		p = strings.Trim(strings.TrimPrefix(p, "./"), "/")
		if p == "." {
			return ""
		}
		return p
	}
	sub = clean(sub)
	for i := range r.Modules.Modules {
		x := &r.Modules.Modules[i]
		if strings.TrimSuffix(x.Repo, ".git") == "https://github.com/terraform-google-modules/"+repo && clean(x.Path) == sub {
			return x, nil, true, nil
		}
	}
	if v, found := variants[repo+"//"+sub]; found {
		if x := r.Modules.Find(v.ID); x != nil {
			return x, v.Inputs, true, nil
		}
	}
	where := repo
	if sub != "" {
		where += "//" + sub
	}
	return nil, nil, true, fmt.Errorf("source %q: terraform-google-modules %s is not in upstream/modules.yaml", src, where)
}

// readConfig parses a Terraform file, or every .tf file of a root module's
// directory, into one body (Terraform reads a directory as one module).
func readConfig(path string) (*hclsyntax.Body, error) {
	st, err := os.Stat(path)
	if err != nil {
		return nil, err
	}
	files := []string{path}
	if st.IsDir() {
		files, err = filepath.Glob(filepath.Join(path, "*.tf"))
		if err != nil {
			return nil, err
		}
		sort.Strings(files)
		if len(files) == 0 {
			return nil, fmt.Errorf("%s: no .tf files", path)
		}
	}
	merged := &hclsyntax.Body{Attributes: hclsyntax.Attributes{}}
	for _, f := range files {
		src, err := os.ReadFile(f)
		if err != nil {
			return nil, err
		}
		pf, diags := hclsyntax.ParseConfig(src, f, hcl.InitialPos)
		if diags.HasErrors() {
			return nil, fmt.Errorf("%s", diags.Error())
		}
		b := pf.Body.(*hclsyntax.Body)
		merged.Blocks = append(merged.Blocks, b.Blocks...)
		for k, a := range b.Attributes {
			merged.Attributes[k] = a
		}
	}
	return merged, nil
}
