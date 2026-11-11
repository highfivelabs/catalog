# Offramp conversion

From the Terraform state `/work/offload-artifacts/offramp/shared-vpc-ofr-11110129-7049/state.json` (Terraform 1.17.1), with Config Connector's kinds from `/work/.cache/offramp-kcc-v1.160.0`.

15 Config Connector objects in 3 components; 3 findings.

| Component | Package | Source | Kind | Name | Resource ID | Note |
| --- | --- | --- | --- | --- | --- | --- |
| firewall-rules | gcp-firewall-rules | `module.firewall_rules.google_compute_firewall.rules_ingress_egress["ofr-11110129-7049-allow-iap-ssh"]` | ComputeFirewall | ofr-11110129-7049-allow-iap-ssh | ofr-11110129-7049-allow-iap-ssh |  |
| firewall-rules | gcp-firewall-rules | `module.firewall_rules.google_compute_firewall.rules_ingress_egress["ofr-11110129-7049-allow-internal"]` | ComputeFirewall | ofr-11110129-7049-allow-internal | ofr-11110129-7049-allow-internal |  |
| firewall-rules | gcp-firewall-rules | `module.firewall_rules.google_compute_firewall.rules_ingress_egress["ofr-11110129-7049-deny-smtp"]` | ComputeFirewall | ofr-11110129-7049-deny-smtp | ofr-11110129-7049-deny-smtp |  |
| network-firewall-policy | gcp-network-firewall-policy | `module.network_firewall_policy.google_compute_network_firewall_policy.fw_policy[0]` | ComputeNetworkFirewallPolicy | ofr-11110129-7049-policy | ofr-11110129-7049-policy |  |
| network-firewall-policy | gcp-network-firewall-policy | `module.network_firewall_policy.google_compute_network_firewall_policy_association.vpc_associations["shared"]` | ComputeNetworkFirewallPolicyAssociation | ofr-11110129-7049-policy-ofr-11110129-7049-shared | ofr-11110129-7049-policy-ofr-11110129-7049-shared |  |
| network-firewall-policy | gcp-network-firewall-policy | `module.network_firewall_policy.google_compute_network_firewall_policy_rule.rules["1000"]` | ComputeNetworkFirewallPolicyRule | ofr-11110129-7049-policy-1000 | 1000 |  |
| network-firewall-policy | gcp-network-firewall-policy | `module.network_firewall_policy.google_compute_network_firewall_policy_rule.rules["2000"]` | ComputeNetworkFirewallPolicyRule | ofr-11110129-7049-policy-2000 | 2000 |  |
| vpc | gcp-net-vpc | `module.vpc.google_compute_network.network[0]` | ComputeNetwork | ofr-11110129-7049-shared | ofr-11110129-7049-shared |  |
| vpc | gcp-net-vpc | `module.vpc.google_compute_route.gateway["directpath-googleapis"]` | ComputeRoute | ofr-11110129-7049-shared-directpath-googleapis | ofr-11110129-7049-shared-directpath-googleapis |  |
| vpc | gcp-net-vpc | `module.vpc.google_compute_route.gateway["private-googleapis"]` | ComputeRoute | ofr-11110129-7049-shared-private-googleapis | ofr-11110129-7049-shared-private-googleapis |  |
| vpc | gcp-net-vpc | `module.vpc.google_compute_route.gateway["restricted-googleapis"]` | ComputeRoute | ofr-11110129-7049-shared-restricted-googleapis | ofr-11110129-7049-shared-restricted-googleapis |  |
| vpc | gcp-net-vpc | `module.vpc.google_compute_subnetwork.subnetwork["us-central1/ofr-11110129-7049-apps"]` | ComputeSubnetwork | ofr-11110129-7049-apps | ofr-11110129-7049-apps |  |
| vpc | gcp-net-vpc | `module.vpc.google_compute_subnetwork.subnetwork["us-central1/ofr-11110129-7049-gke"]` | ComputeSubnetwork | ofr-11110129-7049-gke | ofr-11110129-7049-gke |  |
| vpc | gcp-net-vpc | `module.vpc.google_compute_subnetwork_iam_binding.authoritative["us-central1/ofr-11110129-7049-gke.roles/compute.networkUser"]` | IAMPartialPolicy | ofr-11110129-7049-gke-compute-networkuser-9a7b57 |  |  |
| vpc | gcp-net-vpc | `module.vpc.google_compute_subnetwork_iam_member.bindings["network-user-0"]` | IAMPolicyMember | ofr-11110129-7049-apps-compute-networkuser-42a401 |  |  |

## Module calls and catalog charts

Each call whose module a catalog chart ports was converted to that chart's values (the call's arguments, unchanged), rendered, and compared object by object with what the state holds. A call graduates only when they match.

| Call | Chart | Result | Objects (render / state) | Import adds |
| --- | --- | --- | --- | --- |
| `module.vpc` | `gcp-net-vpc` 0.3.1 | **graduated**: the render matches the state | 8 / 8 | `deletion_policy` |
| `module.firewall_rules` | `gcp-firewall-rules` 0.1.0 | **graduated**: the render matches the state | 3 / 3 | `deletion_policy` |
| `module.network_firewall_policy` | `gcp-network-firewall-policy` 0.1.0 | **graduated**: the render matches the state | 4 / 4 | `deletion_policy` |
- note: module.firewall_rules: a component name is an RFC 1123 label: using "firewall-rules"
- note: module.network_firewall_policy: a component name is an RFC 1123 label: using "network-firewall-policy"
- note: module.network_firewall_policy.allow_alpha: added allow_alpha: true: rules needs an alpha Config Connector kind (ComputeNetworkFirewallPolicyRule is v1alpha1: needs allow_alpha: true; packet mirroring rules (is_mirroring: true) have no kind, and action apply_security_profile_group is refused (no securityProfileGroup or tlsInspect))

## Components

- `firewall-rules` (3 objects), after: vpc
- `network-firewall-policy` (4 objects), after: vpc
- `vpc` (8 objects), after: none

## Findings

| Class | Source | Type | Reason |
| --- | --- | --- | --- |
| note | `module.network_firewall_policy.google_compute_network_firewall_policy_rule.rules["1000"]` | google_compute_network_firewall_policy_rule | ComputeNetworkFirewallPolicyRule is v1alpha1 in Config Connector: it works, but its schema may change without notice |
| note | `module.network_firewall_policy.google_compute_network_firewall_policy_rule.rules["2000"]` | google_compute_network_firewall_policy_rule | ComputeNetworkFirewallPolicyRule is v1alpha1 in Config Connector: it works, but its schema may change without notice |
| note | `module.vpc.google_compute_subnetwork_iam_binding.authoritative["us-central1/ofr-11110129-7049-gke.roles/compute.networkUser"]` | google_compute_subnetwork_iam_binding | an authoritative binding becomes IAMPartialPolicy: the listed members are kept, and members added outside it are no longer removed (IAMRoleBinding in config-connector-extensions makes it exact) |
