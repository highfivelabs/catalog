// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package offramp

import (
	"fmt"
	"regexp"
	"strings"
)

// special holds the Terraform types whose attributes differ from what the
// service mapping (or the kind's generated shape) expects.
var special = map[string]func(*TFResource, *KCC) ([]*Object, []Finding){
	"google_folder":                               convertFolder,
	"google_org_policy_policy":                    convertOrgPolicy,
	"google_compute_firewall_policy":              convertFirewallPolicy,
	"google_compute_firewall_policy_rule":         convertFirewallPolicyRule,
	"google_compute_network_firewall_policy_rule": convertNetworkFirewallPolicyRule,
	"google_project_default_service_accounts": func(r *TFResource, _ *KCC) ([]*Object, []Finding) {
		return nil, []Finding{{r.Address, r.Type, "gap", "an action on the project's default service accounts (deprivilege, disable or delete), not a resource: nothing to adopt; record the outcome in the platform project's baseline (IAM on the default account), or leave it done"}}
	},
	"google_secret_manager_secret":       convertSecret,
	"google_project_organization_policy": legacyOrgPolicy,
	"google_folder_organization_policy":  legacyOrgPolicy,
	"google_organization_policy":         legacyOrgPolicy,
}

// convertFolder: upstream Terraform names the parent `parent`
// (folders/<n> or organizations/<n>); Config Connector's own Terraform
// fork, which the service mapping describes, has parent_folder_id and
// parent_org_id.
func convertFolder(r *TFResource, k *KCC) ([]*Object, []Finding) {
	crd := k.CRDs["Folder"]
	if crd == nil {
		return nil, []Finding{{r.Address, r.Type, "gap", "no Folder kind loaded"}}
	}
	o, f := generic(r, k, k.SM[r.Type], crd)
	spec := o.Obj["spec"].(map[string]any)
	setParent(spec, str(r.Attrs["parent"]), true)
	if n := str(r.Attrs["display_name"]); n != "" {
		o.Obj["metadata"].(map[string]any)["name"] = sanitize(n)
	}
	return []*Object{o}, f
}

// setParent writes folderRef or organizationRef (or projectRef) from a
// parent such as folders/123. Folders and organizations take the bare
// number when numberOnly is set, as Config Connector's Folder does.
func setParent(spec map[string]any, parent string, numberOnly bool) {
	if parent == "" {
		return
	}
	kind, id, ok := strings.Cut(parent, "/")
	if !ok {
		return
	}
	ext := parent
	if numberOnly {
		ext = id
	}
	switch kind {
	case "folders":
		spec["folderRef"] = map[string]any{"external": ext}
	case "organizations":
		spec["organizationRef"] = map[string]any{"external": ext}
	case "projects":
		spec["projectRef"] = map[string]any{"external": ext}
	}
}

// convertOrgPolicy: google_org_policy_policy is a direct kind,
// OrgPolicyPolicy. Its name is <parent>/policies/<constraint>, its
// resource ID the constraint; enforce and the like are "TRUE" in
// Terraform and booleans in the kind.
func convertOrgPolicy(r *TFResource, k *KCC) ([]*Object, []Finding) {
	crd := k.CRDs["OrgPolicyPolicy"]
	if crd == nil {
		return nil, []Finding{{r.Address, r.Type, "gap", "no OrgPolicyPolicy kind loaded"}}
	}
	o, f := generic(r, k, nil, crd)
	spec := o.Obj["spec"].(map[string]any)
	name := str(r.Attrs["name"])
	constraint := name[strings.LastIndex(name, "/")+1:]
	spec["resourceID"] = constraint
	delete(spec, "projectRef")
	setParent(spec, str(r.Attrs["parent"]), false)
	parent := strings.ReplaceAll(str(r.Attrs["parent"]), "/", "-")
	o.Obj["metadata"].(map[string]any)["name"] = sanitize(parent + "-" + constraint)
	return []*Object{o}, f
}

// convertFirewallPolicy: a hierarchical firewall policy's name is its
// number and its short name the one people know; its parent is a folder
// or the organization.
func convertFirewallPolicy(r *TFResource, k *KCC) ([]*Object, []Finding) {
	crd := k.CRDs["ComputeFirewallPolicy"]
	if crd == nil {
		return nil, []Finding{{r.Address, r.Type, "gap", "no ComputeFirewallPolicy kind loaded"}}
	}
	o, f := generic(r, k, nil, crd)
	spec := o.Obj["spec"].(map[string]any)
	delete(spec, "projectRef")
	setParent(spec, str(r.Attrs["parent"]), false)
	if n := str(r.Attrs["short_name"]); n != "" {
		o.Obj["metadata"].(map[string]any)["name"] = sanitize(n)
	}
	return []*Object{o}, f
}

var firewallPolicyNumber = regexp.MustCompile(`(\d+)$`)

// convertFirewallPolicyRule: a rule is known by its policy and priority.
func convertFirewallPolicyRule(r *TFResource, k *KCC) ([]*Object, []Finding) {
	crd := k.CRDs["ComputeFirewallPolicyRule"]
	if crd == nil {
		return nil, []Finding{{r.Address, r.Type, "gap", "no ComputeFirewallPolicyRule kind loaded"}}
	}
	o, f := generic(r, k, nil, crd)
	policy := firewallPolicyNumber.FindString(str(r.Attrs["firewall_policy"]))
	o.Obj["metadata"].(map[string]any)["name"] = sanitize(fmt.Sprintf("policy-%s-%s", policy, scalarString(r.Attrs["priority"])))
	return []*Object{o}, f
}

// convertNetworkFirewallPolicyRule: a rule's resource ID is its priority.
// Config Connector generates the kind from Terraform (v1alpha1), so there
// is no service mapping to say so.
func convertNetworkFirewallPolicyRule(r *TFResource, k *KCC) ([]*Object, []Finding) {
	crd := k.CRDs["ComputeNetworkFirewallPolicyRule"]
	if crd == nil {
		return nil, []Finding{{r.Address, r.Type, "gap", "no ComputeNetworkFirewallPolicyRule kind loaded"}}
	}
	o, f := generic(r, k, nil, crd)
	prio := scalarString(r.Attrs["priority"])
	o.Obj["spec"].(map[string]any)["resourceID"] = prio
	o.Obj["metadata"].(map[string]any)["name"] = sanitize(lastSegment(str(r.Attrs["firewall_policy"])) + "-" + prio)
	f = append(f, Finding{r.Address, r.Type, "note", "ComputeNetworkFirewallPolicyRule is v1alpha1 in Config Connector: it works, but its schema may change without notice"})
	return []*Object{o}, f
}

func legacyOrgPolicy(r *TFResource, _ *KCC) ([]*Object, []Finding) {
	return nil, []Finding{{r.Address, r.Type, "gap", "the v1 organization policy resource (ResourceManagerPolicy) is not converted: move it to google_org_policy_policy (OrgPolicyPolicy) in Terraform first, or convert it by hand"}}
}

// convertSecret: Terraform's automatic replication is an empty auto block
// (auto {}). Config Connector v1.160.0 reconciles SecretManagerSecret
// through its Terraform fork, which drops an empty auto and sends no
// replication, so the API refuses the secret; its own form for the same
// policy is automatic: true, which the secret-manager chart renders too.
// An auto block with a customer-managed key is kept as it is.
func convertSecret(r *TFResource, k *KCC) ([]*Object, []Finding) {
	crd := k.CRDs["SecretManagerSecret"]
	if crd == nil {
		return nil, []Finding{{r.Address, r.Type, "gap", "no SecretManagerSecret kind loaded"}}
	}
	o, f := generic(r, k, k.SM[r.Type], crd)
	spec := o.Obj["spec"].(map[string]any)
	rep, _ := spec["replication"].(map[string]any)
	if rep == nil {
		rep = map[string]any{}
	}
	if auto, ok := rep["auto"].(map[string]any); (ok && zero(auto["customerManagedEncryption"])) || (rep["auto"] == nil && autoInState(r.Attrs)) {
		delete(rep, "auto")
		rep["automatic"] = true
		spec["replication"] = rep
	}
	return []*Object{o}, f
}

// autoInState says the state's replication is an auto block, which the
// generic conversion leaves out when it is empty.
func autoInState(attrs map[string]any) bool {
	reps, _ := attrs["replication"].([]any)
	if len(reps) == 0 {
		return false
	}
	rep, _ := reps[0].(map[string]any)
	auto, _ := rep["auto"].([]any)
	return len(auto) > 0
}
