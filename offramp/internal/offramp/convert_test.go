// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package offramp

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// testdata/kcc holds Config Connector v1.160.0's CRDs and service mappings
// for the kinds the tests convert (Apache-2.0, copied unchanged from
// config/crds/resources and config/servicemappings at that tag).
// testdata/synthetic.tfstate is written by hand in the shape Terraform
// 1.17 writes; testdata/live/ holds states from the live runs.

func load(t *testing.T) (*KCC, *Result) {
	t.Helper()
	k, err := LoadKCC("testdata/kcc")
	if err != nil {
		t.Fatal(err)
	}
	st, err := ReadState("testdata/synthetic.tfstate")
	if err != nil {
		t.Fatal(err)
	}
	return k, ConvertState(st, k, Options{})
}

func find(t *testing.T, res *Result, source string) *Object {
	t.Helper()
	for _, o := range res.Objects {
		if o.Source == source {
			return o
		}
	}
	var have []string
	for _, o := range res.Objects {
		have = append(have, o.Source)
	}
	t.Fatalf("no object from %s; have %s", source, strings.Join(have, ", "))
	return nil
}

func jsonEq(t *testing.T, what string, got any, want string) {
	t.Helper()
	var w any
	if err := json.Unmarshal([]byte(want), &w); err != nil {
		t.Fatalf("bad want: %v", err)
	}
	gb, _ := json.Marshal(got)
	var g any
	_ = json.Unmarshal(gb, &g)
	if !reflect.DeepEqual(g, w) {
		t.Errorf("%s:\n got %s\nwant %s", what, gb, want)
	}
}

func TestSubnetwork(t *testing.T) {
	_, res := load(t)
	o := find(t, res, `module.vpc.module.subnets.google_compute_subnetwork.subnetwork["us-central1/t-apps"]`)
	if o.Kind != "ComputeSubnetwork" || o.Call != "vpc" {
		t.Fatalf("kind %s call %s", o.Kind, o.Call)
	}
	jsonEq(t, "spec", o.Obj["spec"], `{
		"resourceID": "t-apps",
		"description": "application VMs",
		"ipCidrRange": "10.10.1.0/24",
		"logConfig": {"aggregationInterval": "INTERVAL_10_MIN", "filterExpr": "true", "flowSampling": 0.5, "metadata": "INCLUDE_ALL_METADATA"},
		"networkRef": {"external": "https://www.googleapis.com/compute/v1/projects/demo-project/global/networks/t-shared"},
		"privateIpGoogleAccess": true,
		"privateIpv6GoogleAccess": "DISABLE_GOOGLE_ACCESS",
		"purpose": "PRIVATE",
		"region": "us-central1",
		"stackType": "IPV4_ONLY"
	}`)
	ann := dig(o.Obj, "metadata", "annotations").(map[string]any)
	for k, v := range map[string]string{
		"cnrm.cloud.google.com/project-id":      "demo-project",
		"cnrm.cloud.google.com/deletion-policy": "abandon",
		"cnrm.cloud.google.com/state-into-spec": "absent",
		AnnID:                                   "computesubnetwork-t-apps",
	} {
		if ann[k] != v {
			t.Errorf("annotation %s = %v, want %s", k, ann[k], v)
		}
	}
	if o.Name() != "t-apps" {
		t.Errorf("name %s", o.Name())
	}
}

func TestSecondaryRanges(t *testing.T) {
	_, res := load(t)
	o := find(t, res, `module.vpc.module.subnets.google_compute_subnetwork.subnetwork["us-central1/t-gke"]`)
	jsonEq(t, "secondaryIpRange", dig(o.Obj, "spec", "secondaryIpRange"),
		`[{"ipCidrRange": "10.20.0.0/20", "rangeName": "pods"}, {"ipCidrRange": "10.30.0.0/24", "rangeName": "services"}]`)
	if dig(o.Obj, "spec", "logConfig") != nil {
		t.Errorf("an empty log_config became %v", dig(o.Obj, "spec", "logConfig"))
	}
}

func TestNetworkAndFirewall(t *testing.T) {
	_, res := load(t)
	n := find(t, res, `module.vpc.module.vpc.google_compute_network.network`)
	jsonEq(t, "network spec", n.Obj["spec"], `{
		"resourceID": "t-shared", "autoCreateSubnetworks": false, "deleteDefaultRoutesOnCreate": false,
		"description": "offramp fixture: shared VPC", "enableUlaInternalIpv6": false,
		"networkFirewallPolicyEnforcementOrder": "AFTER_CLASSIC_FIREWALL", "routingMode": "GLOBAL"}`)
	f := find(t, res, `module.vpc.module.firewall_rules.google_compute_firewall.rules_ingress_egress["t-allow-iap-ssh"]`)
	jsonEq(t, "firewall spec", f.Obj["spec"], `{
		"resourceID": "t-allow-iap-ssh", "allow": [{"ports": ["22"], "protocol": "tcp"}],
		"description": "SSH through Identity-Aware Proxy", "direction": "INGRESS", "disabled": false,
		"networkRef": {"external": "t-shared"}, "priority": 1000,
		"sourceRanges": ["35.235.240.0/20"], "targetTags": ["ssh"]}`)
}

func TestNetworkFirewallPolicy(t *testing.T) {
	_, res := load(t)
	p := find(t, res, `module.network_firewall_policy.google_compute_network_firewall_policy.fw_policy[0]`)
	jsonEq(t, "policy", p.Obj["spec"], `{"resourceID": "t-policy", "description": "offramp fixture", "projectRef": {"external": "demo-project"}}`)
	r := find(t, res, `module.network_firewall_policy.google_compute_network_firewall_policy_rule.rules["1000"]`)
	if r.Kind != "ComputeNetworkFirewallPolicyRule" || dig(r.Obj, "apiVersion") != "compute.cnrm.cloud.google.com/v1alpha1" {
		t.Fatalf("rule is %s %v", r.Kind, dig(r.Obj, "apiVersion"))
	}
	jsonEq(t, "rule", r.Obj["spec"], `{
		"resourceID": "1000", "action": "allow", "direction": "INGRESS", "disabled": false, "enableLogging": false,
		"firewallPolicyRef": {"external": "t-policy"}, "projectRef": {"external": "demo-project"},
		"match": {"layer4Configs": [{"ipProtocol": "tcp", "ports": ["80", "443"]}], "srcIpRanges": ["35.191.0.0/16", "130.211.0.0/22"]},
		"ruleName": "allow-health-checks"}`)
	a := find(t, res, `module.network_firewall_policy.google_compute_network_firewall_policy_association.vpc_associations["shared"]`)
	jsonEq(t, "association", a.Obj["spec"], `{
		"resourceID": "t-policy-t-shared",
		"attachmentTargetRef": {"external": "projects/demo-project/global/networks/t-shared"},
		"firewallPolicyRef": {"external": "t-policy"}, "projectRef": {"external": "demo-project"}}`)
}

func TestIAM(t *testing.T) {
	_, res := load(t)
	m := find(t, res, `google_compute_subnetwork_iam_member.apps_network_users["serviceAccount:deployer@demo-project.iam.gserviceaccount.com"]`)
	jsonEq(t, "member", m.Obj["spec"], `{
		"member": "serviceAccount:deployer@demo-project.iam.gserviceaccount.com", "role": "roles/compute.networkUser",
		"resourceRef": {"apiVersion": "compute.cnrm.cloud.google.com/v1beta1", "kind": "ComputeSubnetwork",
		  "external": "projects/demo-project/regions/us-central1/subnetworks/t-apps"}}`)
	b := find(t, res, `google_compute_subnetwork_iam_binding.gke_network_users`)
	if b.Kind != "IAMPartialPolicy" {
		t.Fatalf("binding is %s", b.Kind)
	}
	// The binding's state names the subnet by name; the converter fills the
	// service mapping's ID template.
	jsonEq(t, "binding", b.Obj["spec"], `{
		"resourceRef": {"apiVersion": "compute.cnrm.cloud.google.com/v1beta1", "kind": "ComputeSubnetwork",
		  "external": "projects/demo-project/regions/us-central1/subnetworks/t-gke"},
		"bindings": [{"role": "roles/compute.networkUser", "members": [
		  {"member": "group:gke-admins@example.com"}, {"member": "serviceAccount:ci@demo-project.iam.gserviceaccount.com"}]}]}`)
}

// An authoritative binding on a resource IAMBinding takes (a folder)
// becomes one IAMBinding, exact as Terraform's, as the folders chart
// renders owners_combined; its condition is carried.
func TestIAMBinding(t *testing.T) {
	k, err := LoadKCC("testdata/kcc")
	if err != nil {
		t.Fatal(err)
	}
	st, err := ReadState("testdata/synthetic/folders/terraform.tfstate")
	if err != nil {
		t.Fatal(err)
	}
	res := ConvertState(st, k, Options{})
	b := find(t, res, `module.environments.google_folder_iam_binding.owners_combined["prod-roles/resourcemanager.folderViewer"]`)
	if b.Kind != "IAMBinding" || b.Obj["apiVersion"] != "iam.gcp.hfl.dev/v1beta1" {
		t.Fatalf("binding is %s %v", b.Kind, b.Obj["apiVersion"])
	}
	jsonEq(t, "binding", b.Obj["spec"], `{
		"resourceRef": {"apiVersion": "resourcemanager.cnrm.cloud.google.com/v1beta1", "kind": "Folder",
		  "external": "folders/100000000765"},
		"role": "roles/resourcemanager.folderViewer",
		"members": ["group:platform@example.com", "group:prod-admins@example.com"]}`)
	for _, f := range res.Findings {
		if f.Source == b.Source {
			t.Errorf("an exact binding needs no finding: %+v", f)
		}
	}

	cond := &TFResource{Address: "google_folder_iam_binding.c", Type: "google_folder_iam_binding", Attrs: map[string]any{
		"folder": "folders/1", "role": "roles/viewer", "members": []any{"user:a@example.com"},
		"condition": []any{map[string]any{"title": "t", "expression": "true"}}}}
	o, fs := convertIAM(cond, k)
	if o == nil {
		t.Fatalf("not converted: %+v", fs)
	}
	jsonEq(t, "conditional", o.Obj["spec"], `{
		"resourceRef": {"apiVersion": "resourcemanager.cnrm.cloud.google.com/v1beta1", "kind": "Folder", "external": "folders/1"},
		"role": "roles/viewer", "members": ["user:a@example.com"], "condition": {"title": "t", "expression": "true"}}`)

	// No members: Terraform empties the role; an IAMBinding cannot.
	empty := &TFResource{Address: "google_folder_iam_binding.e", Type: "google_folder_iam_binding", Attrs: map[string]any{
		"folder": "folders/1", "role": "roles/viewer", "members": []any{}}}
	if o, fs := convertIAM(empty, k); o != nil || len(fs) != 1 || fs[0].Class != "refused" {
		t.Errorf("empty binding: %v %+v, want refused", o, fs)
	}
}

func TestHierarchy(t *testing.T) {
	_, res := load(t)
	f := find(t, res, `google_folder.root`)
	if f.Name() != "t-root" {
		t.Errorf("folder name %s", f.Name())
	}
	jsonEq(t, "folder", f.Obj["spec"], `{"resourceID": "4444", "displayName": "t-root", "folderRef": {"external": "10000000001"}}`)
	p := find(t, res, `module.skip_default_network.google_org_policy_policy.folder_policy_boolean[0]`)
	jsonEq(t, "boolean policy", p.Obj["spec"], `{"resourceID": "compute.skipDefaultNetworkCreation",
		"folderRef": {"external": "folders/4444"},
		"spec": {"inheritFromParent": false, "reset": false, "rules": [{"enforce": true}]}}`)
	l := find(t, res, `module.resource_locations.google_org_policy_policy.folder_policy[0]`)
	jsonEq(t, "list policy", dig(l.Obj, "spec", "spec", "rules"), `[{"values": {"allowedValues": ["in:us-locations"]}}]`)
}

func TestProject(t *testing.T) {
	_, res := load(t)
	p := find(t, res, `module.project.google_project.main`)
	jsonEq(t, "project", p.Obj["spec"], `{"resourceID": "t-platform-1a2b", "name": "t-platform",
		"folderRef": {"external": "4444"}, "billingAccountRef": {"external": "000000-000000-000000"}}`)
	jsonEq(t, "labels", dig(p.Obj, "metadata", "labels"), `{"env": "platform", "goog-terraform-provisioned": "true"}`)
	if !p.Labelled {
		t.Error("a project is a labelled kind")
	}
	if a := dig(p.Obj, "metadata", "annotations", "cnrm.cloud.google.com/auto-create-network"); a != "false" {
		t.Errorf("auto-create-network directive %v", a)
	}
	s := find(t, res, `module.project.google_project_service.project_services["compute.googleapis.com"]`)
	jsonEq(t, "service", s.Obj["spec"], `{"resourceID": "compute.googleapis.com", "projectRef": {"external": "t-platform-1a2b"}}`)
	if a := dig(s.Obj, "metadata", "annotations", "cnrm.cloud.google.com/disable-on-destroy"); a != "false" {
		t.Errorf("disable-on-destroy %v", a)
	}
}

func TestFindings(t *testing.T) {
	_, res := load(t)
	got := map[string]string{}
	for _, f := range res.Findings {
		if f.Class != "note" {
			got[f.Source] = f.Class
		}
	}
	want := map[string]string{
		"google_project_iam_policy.everything":                                            "refused",
		"module.project.google_project_default_service_accounts.default_service_accounts": "gap",
		"module.project.random_id.random_project_id_suffix":                               "terraform-only",
		"data.google_client_config.default":                                               "terraform-only",
		"kubernetes_namespace.apps":                                                       "in-cluster",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("findings:\n got %v\nwant %v", got, want)
	}
}

func TestGroup(t *testing.T) {
	_, res := load(t)
	b := Group(res.Objects, BundtOptions{Name: "shared-vpc", Team: "platform", Env: "prod", Target: "infra", Version: "0.1.0", Namespace: "platform-prod", KCCVersion: "1.160.0"})
	deps := map[string][]string{}
	for _, c := range b.Components {
		deps[c.Name] = c.DependsOn
	}
	want := map[string][]string{
		"vpc":                     nil,
		"network-firewall-policy": {"vpc"},
		"root":                    {"vpc"},
		"skip-default-network":    {"root"},
		"resource-locations":      {"root"},
		"project":                 nil,
	}
	if !reflect.DeepEqual(deps, want) {
		t.Errorf("components and dependsOn:\n got %v\nwant %v", deps, want)
	}
	var kinds []string
	for _, d := range b.Catalog {
		kinds = append(kinds, d["kind"].(string))
	}
	if kinds[len(kinds)-1] != "Template" || len(kinds) != len(b.Components)+1 {
		t.Errorf("catalog kinds %v", kinds)
	}
	inst := b.Record[2]
	jsonEq(t, "instance", inst, `{"apiVersion": "hfl.dev/v1", "kind": "Instance",
		"metadata": {"name": "shared-vpc", "scope": "platform/prod"},
		"spec": {"stack": "shared-vpc", "version": "0.1.0", "cloudResources": "keep"}}`)
	if p := dig(b.Record[0], "spec", "cloud", "gcp", "project"); p != "demo-project" {
		t.Errorf("environment project %v", p)
	}
	// Every object of a component has its own hfl.dev/id.
	for _, c := range b.Components {
		ids := map[string]bool{}
		for _, o := range c.Objects {
			id := str(dig(o.Obj, "metadata", "annotations", AnnID))
			if id == "" || ids[id] {
				t.Errorf("component %s: id %q missing or repeated", c.Name, id)
			}
			ids[id] = true
		}
	}
}

func TestWrite(t *testing.T) {
	_, res := load(t)
	b := Group(res.Objects, BundtOptions{Name: "s", Team: "platform", Env: "prod", Target: "infra", Version: "0.1.0", Namespace: "platform-prod", KCCVersion: "1.160.0"})
	dir := t.TempDir()
	if err := Write(dir, res, b, ""); err != nil {
		t.Fatal(err)
	}
	all, err := ReadKRM(filepath.Join(dir, "krm", "all.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	if len(all) != len(res.Objects) {
		t.Errorf("krm/all.yaml has %d objects, want %d", len(all), len(res.Objects))
	}
	pk, err := ReadKRM(filepath.Join(dir, "packages", "s-vpc", "manifests"))
	if err != nil || len(pk) != 4 {
		t.Errorf("s-vpc's manifests: %d objects, %v", len(pk), err)
	}
	rep, _ := os.ReadFile(filepath.Join(dir, "report.md"))
	if !strings.Contains(string(rep), "managed-by-cnrm") || !strings.Contains(string(rep), "refused") {
		t.Errorf("report misses the labelled-kind note or the refusal:\n%s", rep)
	}
}

func TestCompare(t *testing.T) {
	_, res := load(t)
	var a []map[string]any
	for _, o := range res.Objects {
		a = append(a, o.Obj)
	}
	// An export names the network by relative name and lists the binding's
	// members one by one: no difference.
	b := []map[string]any{}
	for _, o := range a {
		raw, _ := json.Marshal(o)
		var c map[string]any
		_ = json.Unmarshal(raw, &c)
		if c["kind"] == "IAMPartialPolicy" {
			for _, m := range []string{"group:gke-admins@example.com", "serviceAccount:ci@demo-project.iam.gserviceaccount.com"} {
				b = append(b, map[string]any{"kind": "IAMPolicyMember", "spec": map[string]any{
					"resourceRef": dig(c, "spec", "resourceRef"), "role": "roles/compute.networkUser", "member": m}})
			}
			continue
		}
		if c["kind"] == "ComputeSubnetwork" {
			c["spec"].(map[string]any)["networkRef"] = map[string]any{"external": "projects/demo-project/global/networks/t-shared"}
		}
		b = append(b, c)
	}
	if d := Compare(a, b); len(d) != 0 {
		t.Errorf("want no differences, got %v", d)
	}
	b[0]["spec"].(map[string]any)["routingMode"] = "REGIONAL"
	d := Compare(a, b)
	if len(d) != 1 || d[0].Path != "spec.routingMode" {
		t.Errorf("want one difference at spec.routingMode, got %v", d)
	}
}

func TestHelpers(t *testing.T) {
	for in, want := range map[string]string{"ip_cidr_range": "ipCidrRange", "layer4_configs": "layer4Configs", "name": "name"} {
		if got := camel(in); got != want {
			t.Errorf("camel(%s) = %s", in, got)
		}
	}
	if got := stripKeys(`module.a["x.y"].module.b.google_x.y[0]`); got != "module.a.module.b.google_x.y" {
		t.Errorf("stripKeys: %s", got)
	}
	if got := rootCall(`module.vpc["a"].module.subnets`); got != "vpc" {
		t.Errorf("rootCall: %s", got)
	}
	if got := untemplate("folders/{{value}}", "folders/123"); got != "123" {
		t.Errorf("untemplate: %s", got)
	}
	if got := sanitize("Team_A Prod/1"); got != "team-a-prod-1" {
		t.Errorf("sanitize: %s", got)
	}
	if got := sanitize(strings.Repeat("a", 80)); len(got) != 63 {
		t.Errorf("sanitize length %d", len(got))
	}
	if got := ProviderName(`provider["registry.terraform.io/hashicorp/google-beta"]`); got != "google-beta" {
		t.Errorf("ProviderName: %s", got)
	}
}

func TestScanNames(t *testing.T) {
	as := []Asset{
		{Name: "//compute.googleapis.com/projects/p/global/networks/n", AssetType: "compute.googleapis.com/Network"},
		{Name: "//compute.googleapis.com/projects/p/global/routes/default-route-abc", AssetType: "compute.googleapis.com/Route"},
	}
	as[1].Resource.Data = map[string]any{"name": "default-route-abc"}
	names, skipped := ExportNames(as)
	if len(names) != 1 || len(skipped) != 1 {
		t.Errorf("names %v skipped %v", names, skipped)
	}
}

func TestConvertKRM(t *testing.T) {
	docs := []map[string]any{
		{"apiVersion": "compute.cnrm.cloud.google.com/v1beta1", "kind": "ComputeSubnetwork",
			"metadata": map[string]any{"name": "t-gke", "annotations": map[string]any{"cnrm.cloud.google.com/project-id": "p"}},
			"spec":     map[string]any{"resourceID": "t-gke", "region": "us-central1"}, "status": map[string]any{"x": 1}},
		{"apiVersion": "iam.cnrm.cloud.google.com/v1beta1", "kind": "IAMPolicyMember",
			"metadata": map[string]any{"name": "m"},
			"spec":     map[string]any{"resourceRef": map[string]any{"kind": "ComputeSubnetwork", "external": "projects/p/regions/us-central1/subnetworks/t-gke"}}},
	}
	res := ConvertKRM(docs, Options{})
	if res.Objects[0].Call != "network" || res.Objects[1].Call != "network" {
		t.Errorf("calls %s %s; subnet IAM goes with the network", res.Objects[0].Call, res.Objects[1].Call)
	}
	if docs[0]["status"] != nil {
		t.Error("status kept")
	}
	if dig(docs[1], "metadata", "annotations", AnnDeletionPolicy) != "abandon" {
		t.Error("no abandon")
	}
}

func TestSensitiveAttributesStayOut(t *testing.T) {
	k, err := LoadKCC("testdata/kcc")
	if err != nil {
		t.Fatal(err)
	}
	st := &State{Version: 4, Resources: []StateResource{{
		Mode: "managed", Type: "google_compute_network", Name: "n",
		Provider: `provider["registry.terraform.io/hashicorp/google"]`,
		Instances: []StateInstance{{
			Attributes:          map[string]any{"name": "n", "project": "p", "description": "a secret"},
			SensitiveAttributes: []any{[]any{map[string]any{"type": "get_attr", "value": "description"}}},
		}},
	}}}
	res := ConvertState(st, k, Options{})
	if d := dig(res.Objects[0].Obj, "spec", "description"); d != nil {
		t.Errorf("a sensitive attribute was written: %v", d)
	}
	if len(res.Findings) != 1 || !strings.Contains(res.Findings[0].Reason, "sensitive attribute description") {
		t.Errorf("findings %v", res.Findings)
	}
}

// TestLiveSharedVPC converts the state of the live run ofr-11102237-8371
// (results/shared-vpc-ofr-11102237-8371.md), whose objects Config Connector
// adopted with no write.
func TestLiveSharedVPC(t *testing.T) {
	k, err := LoadKCC("testdata/kcc")
	if err != nil {
		t.Fatal(err)
	}
	st, err := ReadState("testdata/live/shared-vpc.tfstate")
	if err != nil {
		t.Fatal(err)
	}
	res := ConvertState(st, k, Options{})
	kinds := map[string]int{}
	for _, o := range res.Objects {
		kinds[o.Kind]++
	}
	want := map[string]int{"ComputeNetwork": 1, "ComputeSubnetwork": 2, "ComputeFirewall": 3, "ComputeNetworkFirewallPolicy": 1,
		"ComputeNetworkFirewallPolicyRule": 2, "ComputeNetworkFirewallPolicyAssociation": 1, "IAMPolicyMember": 1, "IAMPartialPolicy": 1}
	if !reflect.DeepEqual(kinds, want) {
		t.Errorf("kinds %v, want %v", kinds, want)
	}
	for _, f := range res.Findings {
		if f.Class != "note" {
			t.Errorf("unexpected finding %+v", f)
		}
	}
	b := Group(res.Objects, BundtOptions{Name: "shared-vpc", Team: "platform", Env: "live", Target: "t", Version: "0.1.0", Namespace: "n", KCCVersion: "1.160.0"})
	if len(b.Components) != 3 {
		t.Errorf("components %d", len(b.Components))
	}
}

func TestCompareIgnoresZerosAndSetOrder(t *testing.T) {
	a := []map[string]any{{"kind": "ComputeFirewall", "spec": map[string]any{"resourceID": "f", "disabled": false,
		"allow": []any{map[string]any{"protocol": "tcp"}, map[string]any{"protocol": "icmp"}}}}}
	b := []map[string]any{{"kind": "ComputeFirewall", "spec": map[string]any{"resourceID": "f",
		"allow": []any{map[string]any{"protocol": "icmp"}, map[string]any{"protocol": "tcp"}}}}}
	if d := Compare(a, b); len(d) != 0 {
		t.Errorf("want none, got %v", d)
	}
}
