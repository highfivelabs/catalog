# Offramp conversion

From the Terraform state `/work/offload-artifacts/offramp/shared-vpc-ofr-11102237-8371/state.json` (Terraform 1.17.1), with Config Connector's kinds from `/work/.cache/offramp-kcc-v1.160.0`.

12 Config Connector objects in 3 components; 3 findings.

| Component | Package | Source | Kind | Name | Resource ID | Note |
| --- | --- | --- | --- | --- | --- | --- |
| root | shared-vpc-root | `google_compute_subnetwork_iam_binding.gke_network_users` | IAMPartialPolicy | ofr-11102237-8371-gke-compute-networkuser-9a7b57 |  |  |
| root | shared-vpc-root | `google_compute_subnetwork_iam_member.apps_network_users["serviceAccount:cce-live-tests@hfl-dev-514205.iam.gserviceaccount.com"]` | IAMPolicyMember | ofr-11102237-8371-apps-compute-networkuser-42a401 |  |  |
| network-firewall-policy | shared-vpc-network-firewall-policy | `module.network_firewall_policy.google_compute_network_firewall_policy.fw_policy[0]` | ComputeNetworkFirewallPolicy | ofr-11102237-8371-policy | ofr-11102237-8371-policy |  |
| network-firewall-policy | shared-vpc-network-firewall-policy | `module.network_firewall_policy.google_compute_network_firewall_policy_association.vpc_associations["shared"]` | ComputeNetworkFirewallPolicyAssociation | ofr-11102237-8371-policy-ofr-11102237-8371-shared | ofr-11102237-8371-policy-ofr-11102237-8371-shared |  |
| network-firewall-policy | shared-vpc-network-firewall-policy | `module.network_firewall_policy.google_compute_network_firewall_policy_rule.rules["1000"]` | ComputeNetworkFirewallPolicyRule | ofr-11102237-8371-policy-1000 | 1000 |  |
| network-firewall-policy | shared-vpc-network-firewall-policy | `module.network_firewall_policy.google_compute_network_firewall_policy_rule.rules["2000"]` | ComputeNetworkFirewallPolicyRule | ofr-11102237-8371-policy-2000 | 2000 |  |
| vpc | shared-vpc-vpc | `module.vpc.module.firewall_rules.google_compute_firewall.rules_ingress_egress["ofr-11102237-8371-allow-iap-ssh"]` | ComputeFirewall | ofr-11102237-8371-allow-iap-ssh | ofr-11102237-8371-allow-iap-ssh |  |
| vpc | shared-vpc-vpc | `module.vpc.module.firewall_rules.google_compute_firewall.rules_ingress_egress["ofr-11102237-8371-allow-internal"]` | ComputeFirewall | ofr-11102237-8371-allow-internal | ofr-11102237-8371-allow-internal |  |
| vpc | shared-vpc-vpc | `module.vpc.module.firewall_rules.google_compute_firewall.rules_ingress_egress["ofr-11102237-8371-deny-smtp"]` | ComputeFirewall | ofr-11102237-8371-deny-smtp | ofr-11102237-8371-deny-smtp |  |
| vpc | shared-vpc-vpc | `module.vpc.module.subnets.google_compute_subnetwork.subnetwork["us-central1/ofr-11102237-8371-apps"]` | ComputeSubnetwork | ofr-11102237-8371-apps | ofr-11102237-8371-apps |  |
| vpc | shared-vpc-vpc | `module.vpc.module.subnets.google_compute_subnetwork.subnetwork["us-central1/ofr-11102237-8371-gke"]` | ComputeSubnetwork | ofr-11102237-8371-gke | ofr-11102237-8371-gke |  |
| vpc | shared-vpc-vpc | `module.vpc.module.vpc.google_compute_network.network` | ComputeNetwork | ofr-11102237-8371-shared | ofr-11102237-8371-shared |  |

## Components

- `root` (2 objects), after: vpc
- `network-firewall-policy` (4 objects), after: vpc
- `vpc` (6 objects), after: none

## Findings

| Class | Source | Type | Reason |
| --- | --- | --- | --- |
| note | `google_compute_subnetwork_iam_binding.gke_network_users` | google_compute_subnetwork_iam_binding | an authoritative binding becomes IAMPartialPolicy: the listed members are kept, and members added outside it are no longer removed (IAMRoleBinding in config-connector-extensions makes it exact) |
| note | `module.network_firewall_policy.google_compute_network_firewall_policy_rule.rules["1000"]` | google_compute_network_firewall_policy_rule | ComputeNetworkFirewallPolicyRule is v1alpha1 in Config Connector: it works, but its schema may change without notice |
| note | `module.network_firewall_policy.google_compute_network_firewall_policy_rule.rules["2000"]` | google_compute_network_firewall_policy_rule | ComputeNetworkFirewallPolicyRule is v1alpha1 in Config Connector: it works, but its schema may change without notice |
