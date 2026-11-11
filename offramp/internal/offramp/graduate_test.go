// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package offramp

import (
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

// The equivalence check: each fixture's module calls, converted to the
// values of the catalog chart that ports their module (the calls'
// arguments unchanged), render to the same Config Connector objects as the
// resource-level conversion of the state. A call graduates only when they
// match; the test pins which calls graduate, and why the others do not.
//
// The root modules are read from OFFRAMP_FIXTURES (default
// offramp/fixtures; they may move to the terraform-offramp-demo
// repository). The states are testdata/live/<shape> (what a live run's
// terraform apply recorded) or testdata/synthetic/<shape> (offramp synth:
// Terraform's own offline plan of the fixture, with only cloud-assigned
// values made up; see testdata/synthetic/README.md).

func fixturesDir(t *testing.T) string {
	if d := os.Getenv("OFFRAMP_FIXTURES"); d != "" {
		return d
	}
	return filepath.Join("..", "..", "fixtures")
}

type equivalenceCase struct {
	shape, state, tfvars string
	// graduate are the calls whose render must match the state; frozen,
	// the calls that must not graduate, each with a substring of why.
	graduate []string
	frozen   map[string]string
}

var equivalenceCases = []equivalenceCase{
	{
		// A real state: the live run ofr-11110114-2801 in hfl-dev-514205.
		shape: "shared-vpc", state: "testdata/live/shared-vpc-modules/terraform.tfstate", tfvars: "testdata/live/shared-vpc-modules/terraform.tfvars",
		graduate: []string{"firewall_rules", "network_firewall_policy", "vpc"},
	},
	{
		shape: "shared-vpc", state: "testdata/synthetic/shared-vpc/terraform.tfstate", tfvars: "testdata/synthetic/shared-vpc/terraform.tfvars",
		graduate: []string{"firewall_rules", "network_firewall_policy", "vpc"},
	},
	{
		shape: "folders", state: "testdata/synthetic/folders/terraform.tfstate", tfvars: "testdata/synthetic/folders/terraform.tfvars",
		graduate: []string{"auditor", "environments", "hierarchical_firewall", "require_os_login", "resource_locations", "root", "skip_default_network", "teams"},
	},
	{
		shape: "platform-project", state: "testdata/synthetic/platform-project/terraform.tfstate", tfvars: "testdata/synthetic/platform-project/terraform.tfvars",
		graduate: []string{"checkout", "checkout_assets", "platform_ci", "platform_deployer"},
		frozen: map[string]string{
			// fabric's project grants its service agents their roles by
			// default; the project chart does not port service agents yet.
			"project": "ServiceIdentity",
		},
	},
	{
		shape: "gke", state: "testdata/synthetic/gke/terraform.tfstate", tfvars: "testdata/synthetic/gke/terraform.tfvars",
		graduate: []string{"network"},
		frozen: map[string]string{
			// gke-cluster renders datapathProvider and initialNodeCount where
			// the planned state holds neither (catalog PR #16's open item).
			"gke_standard": "datapathProvider",
		},
	},
}

func TestEquivalence(t *testing.T) {
	if _, err := exec.LookPath("helm"); err != nil {
		t.Skip("helm is not installed: the charts cannot be rendered")
	}
	k, err := LoadKCC("testdata/kcc")
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range equivalenceCases {
		t.Run(tc.shape+"/"+filepath.Base(filepath.Dir(filepath.Dir(tc.state))), func(t *testing.T) {
			st, err := ReadState(tc.state)
			if err != nil {
				t.Fatal(err)
			}
			res := ConvertState(st, k, Options{})
			g, err := Graduate(res, st, GraduateOptions{
				Catalog:     filepath.Join("..", "..", ".."),
				Root:        filepath.Join(fixturesDir(t), tc.shape),
				Tfvars:      []string{tc.tfvars},
				ModulesJSON: filepath.Join("testdata", "modules", tc.shape, "modules.json"),
				Namespace:   "offramp",
			})
			if err != nil {
				t.Fatal(err)
			}
			var got []string
			for call, gr := range g.Calls {
				if gr.OK() {
					got = append(got, call)
					if len(gr.Rendered) == 0 {
						t.Errorf("%s: graduated with an empty render", call)
					}
					continue
				}
				why, want := tc.frozen[call]
				detail := gr.Err
				for _, d := range gr.Differences {
					detail += "\n  " + d.String()
				}
				if !want {
					t.Errorf("%s: the render of %s differs from the state:%s", call, gr.Chart.Package, detail)
				} else if !strings.Contains(detail, why) {
					t.Errorf("%s: frozen, but not for the expected reason (%q):%s", call, why, detail)
				}
			}
			sort.Strings(got)
			if strings.Join(got, ",") != strings.Join(tc.graduate, ",") {
				t.Errorf("graduated %v, want %v", got, tc.graduate)
			}
			for call := range tc.frozen {
				if gr := g.Calls[call]; gr != nil && gr.OK() {
					t.Errorf("%s graduated; the test expects it frozen: update the case", call)
				}
			}
			// Every graduated call's render covers every object the state
			// holds for it: nothing Terraform made is left behind.
			for _, call := range tc.graduate {
				gr := g.Calls[call]
				if gr == nil {
					continue
				}
				// (Counted as Compare counts them: an IAMPartialPolicy is
				// one grant per member and role.)
				r, st := index(gr.Normalized), index(gr.State)
				for id := range st {
					if _, ok := r[id]; !ok {
						t.Errorf("%s: %s is in the state, not in the render", call, id)
					}
				}
			}
		})
	}
}

// A module output read through a function becomes a CEL expression, and
// Bundt's evaluation of it gives what Terraform gave: the folders fixture's
// policy_root_id = trimprefix(module.root.id, "folders/").
func TestGraduateResolvesFunctionOfOutput(t *testing.T) {
	if _, err := exec.LookPath("helm"); err != nil {
		t.Skip("helm is not installed")
	}
	k, err := LoadKCC("testdata/kcc")
	if err != nil {
		t.Fatal(err)
	}
	st, err := ReadState("testdata/synthetic/folders/terraform.tfstate")
	if err != nil {
		t.Fatal(err)
	}
	g, err := Graduate(ConvertState(st, k, Options{}), st, GraduateOptions{
		Catalog: filepath.Join("..", "..", ".."), Root: filepath.Join(fixturesDir(t), "folders"),
		Tfvars:      []string{"testdata/synthetic/folders/terraform.tfvars"},
		ModulesJSON: "testdata/modules/folders/modules.json", Namespace: "offramp",
	})
	if err != nil {
		t.Fatal(err)
	}
	gr := g.Calls["skip_default_network"]
	var expr string
	for _, p := range append(gr.Inputs, gr.Values...) {
		if p.Key == "policy_root_id" {
			expr, _ = p.Value.(string)
		}
	}
	if !strings.Contains(expr, "${components.root.outputs.id.startsWith('folders/')") {
		t.Errorf("policy_root_id = %q, want a CEL expression over components.root.outputs.id", expr)
	}
	root := ""
	for _, in := range st.Instances() {
		if in.Address == `module.root.google_folder.folders["root"]` {
			root = str(in.Attrs["folder_id"])
		}
	}
	if got := str(gr.Effective["policy_root_id"]); got == "" || got != root {
		t.Errorf("policy_root_id evaluated to %q, want the root folder's number %q", got, root)
	}
}
