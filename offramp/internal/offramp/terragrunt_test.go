// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package offramp

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
)

// The Terragrunt estate in fixtures-terragrunt, read statically. Its units
// take the two cases a Terragrunt unit's source can be:
//
//	network/vpc, network/firewall-rules, network/network-firewall-policy
//	    case "module": the source is an open-source module itself (fabric
//	    net-vpc over git, terraform-google-modules' firewall modules from
//	    the registry with tfr:// and from GitHub with git::). Their states
//	    are the live run ofr-11110114-2801's, re-rooted per unit
//	    (testdata/terragrunt/README.md).
//	gke/gke-platform
//	    case "wrapper": the team's own root module (fixtures-terragrunt/
//	    modules/gke-platform) around fabric net-vpc and terraform-google-
//	    modules' beta-private-cluster, with three resources of its own.
//	    A synthetic state (offramp synth).
//	platform/project
//	    case "wrapper" around fabric's project, iam-service-account, gcs and
//	    secret-manager modules: fixtures/platform-project, with its
//	    synthetic state.

const tgEstate = "../../fixtures-terragrunt"

// The static reading agrees with Terragrunt's own: each unit's source,
// remote state and inputs as `terragrunt render-json` (v0.48.6) gave them
// (testdata/terragrunt/render-json; units with a dependency block are left
// out there, since render-json would read the dependency's state).
func TestTerragruntMatchesRenderJSON(t *testing.T) {
	units, err := ReadEstate(tgEstate, TerragruntOptions{})
	if err != nil {
		t.Fatal(err)
	}
	byRel := map[string]*TGUnit{}
	for _, u := range units {
		byRel[u.Rel] = u
	}
	var rels []string
	for r := range byRel {
		rels = append(rels, r)
	}
	sort.Strings(rels)
	want := []string{"gke/gke-platform", "network/firewall-rules", "network/network-firewall-policy", "network/vpc", "platform/project"}
	if !reflect.DeepEqual(rels, want) {
		t.Fatalf("units %v, want %v", rels, want)
	}
	files, _ := filepath.Glob("testdata/terragrunt/render-json/*.json")
	if len(files) == 0 {
		t.Fatal("no render-json goldens")
	}
	abs, _ := filepath.Abs(tgEstate)
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		var g struct {
			Unit      string
			Terraform struct{ Source string }
			Remote    struct {
				Backend string
				Config  map[string]any
			} `json:"remote_state"`
			Inputs map[string]any
		}
		if err := json.Unmarshal(b, &g); err != nil {
			t.Fatal(err)
		}
		u := byRel[g.Unit]
		if u == nil {
			t.Errorf("%s: no unit", g.Unit)
			continue
		}
		if got := strings.ReplaceAll(u.Source, abs, "<estate>"); got != g.Terraform.Source {
			t.Errorf("%s: source %q, Terragrunt %q", g.Unit, got, g.Terraform.Source)
		}
		if u.RemoteState == nil || u.RemoteState.Backend != g.Remote.Backend || !jsonEqual(u.RemoteState.Config, g.Remote.Config) {
			t.Errorf("%s: remote state %+v, Terragrunt %v %v", g.Unit, u.RemoteState, g.Remote.Backend, g.Remote.Config)
		}
		got := map[string]any{}
		for k, v := range u.Inputs {
			if got[k], err = ctyToGo(v); err != nil {
				t.Fatal(err)
			}
		}
		if !jsonEqual(got, g.Inputs) {
			gb, _ := json.MarshalIndent(got, "", " ")
			t.Errorf("%s: inputs differ from Terragrunt's:\n%s", g.Unit, gb)
		}
		if u.Findings != nil {
			for _, f := range u.Findings {
				if f.Class == "unevaluated" {
					t.Errorf("%s: %s: %s", g.Unit, f.Type, f.Reason)
				}
			}
		}
	}
	if loc := byRel["network/vpc"].RemoteState.Location; loc != "gs://my-dev-project-tfstate/network/vpc/default.tfstate" {
		t.Errorf("network/vpc's state is at %q", loc)
	}
	var gens []string
	for _, g := range byRel["network/vpc"].Generates {
		gens = append(gens, g.Name+"="+g.Path)
	}
	sort.Strings(gens)
	if strings.Join(gens, ",") != "provider=provider.tf,remote_state=backend.tf" {
		t.Errorf("generate blocks %v", gens)
	}
}

func jsonEqual(a, b any) bool {
	ja, _ := json.Marshal(a)
	jb, _ := json.Marshal(b)
	var x, y any
	_ = json.Unmarshal(ja, &x)
	_ = json.Unmarshal(jb, &y)
	return reflect.DeepEqual(x, y)
}

type tgCase struct {
	estate string
	opt    EstateOptions
	// graduate and frozen are components, frozen each with a substring of
	// why; unmapped the Terraform addresses of the wrapper's own resources.
	graduate []string
	frozen   map[string]string
	unmapped []string
}

var tgCases = []tgCase{
	{
		estate:   "network",
		opt:      EstateOptions{StateDir: "testdata/terragrunt/network"},
		graduate: []string{"firewall-rules", "network-firewall-policy", "vpc"},
	},
	{
		estate:   "gke",
		opt:      EstateOptions{StateDir: "testdata/terragrunt/gke"},
		graduate: []string{"gke-platform-network"},
		// As fixtures/gke's gke_standard (catalog PR #16's open item).
		frozen: map[string]string{"gke-platform-cluster": "datapathProvider"},
		unmapped: []string{
			"gke-platform:google_compute_firewall.master_webhooks",
			"gke-platform:google_project_iam_member.workload_log_writer",
			"gke-platform:google_service_account.workload",
		},
	},
	{
		estate: "platform",
		opt: EstateOptions{
			States:      map[string]string{"project": "testdata/synthetic/platform-project/terraform.tfstate"},
			ModulesJSON: map[string]string{"project": "testdata/modules/platform-project/modules.json"},
		},
		// As fixtures/platform-project read as a Terraform root.
		graduate: []string{"project-checkout", "project-checkout-assets", "project-platform-ci", "project-platform-deployer"},
		frozen:   map[string]string{"project-project": "ServiceIdentity"},
	},
}

// The equivalence check for a Terragrunt estate: each unit whose source is
// an open-source module renders, through its chart with the unit's inputs
// as values, to what the unit's state holds; inside a wrapper, each module
// call does; and the wrapper's own resources are listed, never mapped.
func TestTerragruntEquivalence(t *testing.T) {
	if _, err := exec.LookPath("helm"); err != nil {
		t.Skip("helm is not installed: the charts cannot be rendered")
	}
	k, err := LoadKCC("testdata/kcc")
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range tgCases {
		t.Run(tc.estate, func(t *testing.T) {
			units, err := ReadEstate(filepath.Join(tgEstate, tc.estate), TerragruntOptions{})
			if err != nil {
				t.Fatal(err)
			}
			opt := tc.opt
			opt.Catalog, opt.Namespace = filepath.Join("..", "..", ".."), "offramp"
			e, err := ConvertEstate(units, k, opt)
			if err != nil {
				t.Fatal(err)
			}
			for _, f := range e.Result.Findings {
				if f.Class == "gap" || f.Class == "unevaluated" {
					t.Errorf("%s: %s %s: %s", f.Source, f.Class, f.Type, f.Reason)
				}
			}
			var got []string
			for _, gr := range e.Graduation.Calls {
				if gr.OK() {
					got = append(got, gr.Component)
					if len(gr.Rendered) == 0 {
						t.Errorf("%s: graduated with an empty render", gr.Component)
					}
					r, st := index(gr.Normalized), index(gr.State)
					for id := range st {
						if _, ok := r[id]; !ok {
							t.Errorf("%s: %s is in the state, not in the render", gr.Component, id)
						}
					}
					continue
				}
				detail := gr.Err
				for _, d := range gr.Differences {
					detail += "\n  " + d.String()
				}
				why, ok := tc.frozen[gr.Component]
				if !ok {
					t.Errorf("%s (%s): the render of %s differs from the state:%s", gr.Component, gr.Where(), gr.Chart.Package, detail)
				} else if !strings.Contains(detail, why) {
					t.Errorf("%s: frozen, not for the expected reason (%q):%s", gr.Component, why, detail)
				}
			}
			sort.Strings(got)
			if strings.Join(got, ",") != strings.Join(tc.graduate, ",") {
				t.Errorf("graduated %v, want %v", got, tc.graduate)
			}
			var unmapped []string
			for _, f := range e.Result.Findings {
				if f.Class == "unmapped" {
					unmapped = append(unmapped, f.Source)
				}
			}
			sort.Strings(unmapped)
			if strings.Join(unmapped, ",") != strings.Join(tc.unmapped, ",") {
				t.Errorf("unmapped %v, want %v", unmapped, tc.unmapped)
			}
			// Every object belongs to a component of its unit, and carries
			// its unit and Terraform address.
			b := Group(e.Result.Objects, BundtOptions{Name: tc.estate, Team: "platform", Env: "imported", Target: "infra", Namespace: "offramp", Version: "0.1.0", Graduation: e.Graduation, DependsOn: e.DependsOn})
			for _, c := range b.Components {
				for _, o := range c.Objects {
					src := str(dig(o.Obj, "metadata", "annotations", AnnAddress))
					if !strings.Contains(src, ":") || src != o.Source {
						t.Errorf("%s: %s carries %q", c.Name, o.Name(), src)
					}
				}
			}
			if tc.estate == "network" {
				checkNetworkWiring(t, e, b)
			}
		})
	}
}

// A dependency block's output is the producing component's output: the
// Template reads it from there, the check resolved it to the value the
// producer's render and state give, and the consumer comes after.
func checkNetworkWiring(t *testing.T, e *Estate, b *Bundle) {
	var fw *Graduated
	for _, g := range e.Graduation.Calls {
		if g.Component == "firewall-rules" {
			fw = g
		}
	}
	if fw == nil {
		t.Fatal("no firewall-rules call")
	}
	var expr any
	for _, p := range append(fw.Inputs, fw.Values...) {
		if p.Key == "network_name" {
			expr = p.Value
		}
	}
	if expr != "${components.vpc.outputs.name}" {
		t.Errorf("network_name = %v, want the vpc component's output", expr)
	}
	if got := fw.Effective["network_name"]; got != "ofr-11110114-2801-shared" {
		t.Errorf("network_name resolved to %v", got)
	}
	for _, c := range b.Components {
		if c.Name != "vpc" && !reflect.DeepEqual(c.DependsOn, []string{"vpc"}) {
			t.Errorf("%s: dependsOn %v, want [vpc]", c.Name, c.DependsOn)
		}
	}
	var tmpl map[string]any
	for _, d := range b.Catalog {
		if d["kind"] == "Template" {
			tmpl = d
		}
	}
	found := false
	for _, c := range dig(tmpl, "spec", "components").([]any) {
		cm := c.(map[string]any)
		if cm["name"] == "network-firewall-policy" {
			found = true
			if v := dig(cm, "inputs", "target_vpcs_map", "shared"); v != "${components.vpc.outputs.id}" {
				t.Errorf("network-firewall-policy's target_vpcs_map.shared = %v", v)
			}
		}
	}
	if !found {
		t.Error("no network-firewall-policy component in the Template")
	}
}

// writeEstate writes files under a new directory.
func writeEstate(t *testing.T, files map[string]string) string {
	t.Helper()
	d := t.TempDir()
	for p, c := range files {
		f := filepath.Join(d, filepath.FromSlash(p))
		if err := os.MkdirAll(filepath.Dir(f), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(f, []byte(c), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return d
}

// What cannot be evaluated from the files is reported, naming the
// expression, and left out: never guessed.
func TestTerragruntUnevaluated(t *testing.T) {
	d := writeEstate(t, map[string]string{
		"root.hcl": `
locals {
  account = run_cmd("gcloud", "config", "get-value", "project")
  region  = get_env("REGION", "europe-west1")
}
inputs = {
  project_id = local.account
  region     = local.region
}
`,
		"vpc/terragrunt.hcl": `
include "root" { path = find_in_parent_folders("root.hcl") }
terraform { source = "../modules//net" }
inputs = { name = "net" }
`,
		"app/terragrunt.hcl": `
include "root" { path = find_in_parent_folders("root.hcl") }
terraform { source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v60.0.0" }
dependency "vpc" { config_path = "../vpc" }
inputs = {
  name        = upper(dependency.vpc.outputs.network)
  network     = dependency.vpc.outputs.network
  link        = "${dependency.vpc.outputs.self_link}/x"
  token       = sops_decrypt_file("secret.enc.yaml")
  owner       = get_env("OWNER")
}
`,
		"modules/net/main.tf": `
module "network" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v60.0.0"
  name   = var.name
}
resource "google_compute_router" "r" {
  name    = "r"
  network = module.network.self_link
}
output "network" { value = module.network.name }
output "self_link" { value = google_compute_router.r.self_link }
`,
		"modules/net/variables.tf": `variable "name" { type = string }`,
	})
	units, err := ReadEstate(d, TerragruntOptions{})
	if err != nil {
		t.Fatal(err)
	}
	var app *TGUnit
	for _, u := range units {
		if u.Rel == "app" {
			app = u
		}
	}
	reasons := map[string]string{}
	for _, f := range app.Findings {
		reasons[f.Type] += f.Class + ": " + f.Reason + "\n"
	}
	for typ, want := range map[string]string{
		"inputs.project_id": "run_cmd runs a command",
		"inputs.name":       "upper(dependency.vpc.outputs.network)",
		"inputs.token":      "sops_decrypt_file",
		"inputs.owner":      `get_env("OWNER") has no default`,
		"get_env":           `took its default "europe-west1"`,
	} {
		if !strings.Contains(reasons[typ], want) {
			t.Errorf("%s: want a finding naming %q, got %q", typ, want, reasons[typ])
		}
	}
	for _, k := range []string{"project_id", "name", "token", "owner"} {
		if _, ok := app.Inputs[k]; ok {
			t.Errorf("input %s was carried; it cannot be evaluated statically", k)
		}
	}
	if v, ok := app.Inputs["region"]; !ok || v.AsString() != "europe-west1" {
		t.Errorf("region = %v", v)
	}

	// Outputs of a wrapper: one passed on from a module call is that
	// component's output; one from the wrapper's own resource is not.
	e := &Estate{}
	byDir := map[string]*EstateUnit{}
	var eapp *EstateUnit
	for _, u := range units {
		eu := &EstateUnit{TGUnit: u}
		byDir[u.Dir] = eu
		if u.Rel == "vpc" {
			eu.Case, eu.ModuleDir = "wrapper", localSource(u.Dir, u.Source)
			eu.outputs = wrapperOutputs(eu.ModuleDir, u.Label)
		} else {
			eapp = eu
		}
	}
	in := e.resolveInputs(eapp, byDir)
	if v := in["network"]; v.AsString() != "${components.vpc-network.outputs.name}" {
		t.Errorf("network = %q, want the wrapper's network call's output", v.AsString())
	}
	if _, ok := in["link"]; ok {
		t.Error("link was carried, though the wrapper's self_link comes from its own resource")
	}
	found := false
	for _, f := range eapp.Findings {
		if f.Type == "inputs.link" && strings.Contains(f.Reason, "google_compute_router.r.self_link") {
			found = true
		}
	}
	if !found {
		t.Errorf("no finding for link naming the wrapper's output: %+v", eapp.Findings)
	}
}

func TestTerragruntSources(t *testing.T) {
	for in, want := range map[string][2]string{
		"tfr:///terraform-google-modules/network/google//modules/firewall-rules?version=18.3.1": {"terraform-google-modules/network/google//modules/firewall-rules", "18.3.1"},
		"tfr://registry.terraform.io/terraform-google-modules/folders/google?version=5.2.0":     {"terraform-google-modules/folders/google", "5.2.0"},
		"git::https://github.com/x/y.git//m?ref=v1":                                             {"git::https://github.com/x/y.git//m?ref=v1", ""},
	} {
		s, v := normalizeSource(in)
		if s != want[0] || v != want[1] {
			t.Errorf("normalizeSource(%q) = %q, %q", in, s, v)
		}
	}
	for in, want := range map[string]bool{"../modules//x": true, "/abs/x": true, "file:///a": true, "git::https://x//y": false, "tfr:///a/b/c": false, "github.com/a/b//c": false} {
		if isLocalSource(in) != want {
			t.Errorf("isLocalSource(%q) != %v", in, want)
		}
	}
	if got := localSource("/e/u", "../../modules//gke"); got != "/modules/gke" {
		t.Errorf("localSource = %q", got)
	}
	m := map[string]string{"git::git@github.com:acme/infra-modules.git": "/src/infra-modules"}
	if got := mappedSource("git::git@github.com:acme/infra-modules.git//project?ref=v1.2.0", m); got != "/src/infra-modules/project" {
		t.Errorf("mappedSource = %q", got)
	}
	if got := mappedSource("git::https://github.com/acme/infra.git//wrappers/gke?ref=v2", map[string]string{"https://github.com/acme/infra.git": "/src/infra"}); got != "/src/infra/wrappers/gke" {
		t.Errorf("mappedSource (https) = %q", got)
	}
}
