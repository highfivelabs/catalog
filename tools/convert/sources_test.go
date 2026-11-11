// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package convert

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestTerraformGoogleModulesSourcesResolve(t *testing.T) {
	r := repo(t)
	for src, chart := range map[string]string{
		"terraform-google-modules/network/google//modules/firewall-rules":                                                    "firewall-rules",
		"registry.terraform.io/terraform-google-modules/network/google//modules/network-firewall-policy":                     "network-firewall-policy",
		"terraform-google-modules/folders/google":                                                                            "folders",
		"git::https://github.com/terraform-google-modules/terraform-google-org-policy.git//modules/org_policy_v2?ref=v7.4.0": "org-policy-v2",
		"terraform-google-modules/kubernetes-engine/google//modules/beta-autopilot-private-cluster":                          "gke-cluster",
	} {
		m, _, extra, err := r.ResolveCall(src)
		if err != nil {
			t.Errorf("%s: %v", src, err)
			continue
		}
		if filepath.Base(m.Chart) != chart {
			t.Errorf("%s: chart %q, want %q", src, m.Chart, chart)
		}
		if strings.Contains(src, "autopilot") && (len(extra) == 0 || extra[0].Key != "mode" || extra[0].Value != "autopilot") {
			t.Errorf("%s: want mode: autopilot added, got %v", src, extra)
		}
	}
	if _, _, _, err := r.ResolveCall("terraform-google-modules/sql-db/google"); err == nil {
		t.Error("an untracked terraform-google-modules module resolved")
	}
}

// A directory is one root module; modules.json gives the version; a count
// of 1 is one component and of 0 none; an output read by key and a
// function of an output are written as Bundt expressions.
func TestRootModuleDirectory(t *testing.T) {
	dir := t.TempDir()
	for name, body := range map[string]string{
		"variables.tf": `variable "prefix" { default = "p" }
variable "on" { default = false }`,
		"main.tf": `module "root" {
  source  = "terraform-google-modules/folders/google"
  version = "5.2.0"
  parent  = "folders/1"
  names   = ["root", "prod"]
  prefix  = var.prefix
}
module "teams" {
  source  = "terraform-google-modules/folders/google"
  version = "5.2.0"
  parent  = module.root.ids["prod"]
  names   = ["a"]
}
module "policy" {
  source         = "terraform-google-modules/org-policy/google//modules/org_policy_v2"
  version        = "7.4.0"
  policy_root    = "folder"
  policy_root_id = trimprefix(module.root.id, "folders/")
  constraint     = "compute.skipDefaultNetworkCreation"
  policy_type    = "boolean"
  rules          = [{ enforcement = true }]
}
module "maybe" {
  source = "terraform-google-modules/folders/google"
  count  = var.on ? 1 : 0
  parent = "folders/1"
  names  = ["x"]
}
module "bad" {
  source = "terraform-google-modules/folders/google"
  parent = title(module.root.id)
  names  = ["y"]
}`,
	} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	res, err := Convert(dir, Options{Repo: repo(t), Sources: map[string]ModuleSource{
		"root": {Key: "root", Source: "registry.terraform.io/terraform-google-modules/folders/google", Version: "5.1.0"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	msgs := messages(res)
	values := map[string]map[string]any{}
	for _, c := range res.Components {
		values[c.Name] = map[string]any{}
		for _, p := range append(c.Inputs, c.Values...) {
			values[c.Name][p.Key] = p.Value
		}
	}
	if values["teams"]["parent"] != "${components.root.outputs.ids['prod']}" {
		t.Errorf("teams.parent = %v", values["teams"]["parent"])
	}
	if got := values["policy"]["policy_root_id"]; got != "${components.root.outputs.id.startsWith('folders/') ? components.root.outputs.id.substring(8) : components.root.outputs.id}" {
		t.Errorf("policy.policy_root_id = %v", got)
	}
	if _, ok := values["maybe"]; ok || !strings.Contains(msgs, "module.maybe.count: count is 0") {
		t.Errorf("a call with count 0 is a component, or not said:\n%s", msgs)
	}
	if !strings.Contains(msgs, "title() of a module output cannot be written") {
		t.Errorf("title of an output is not a gap:\n%s", msgs)
	}
	if !strings.Contains(msgs, "module.root: the source pins 5.1.0") {
		t.Errorf("modules.json's version is not compared with the chart's:\n%s", msgs)
	}
	if res.TemplateName != filepath.Base(dir) && !validName(filepath.Base(dir)) {
		t.Errorf("template name %q", res.TemplateName)
	}
}
