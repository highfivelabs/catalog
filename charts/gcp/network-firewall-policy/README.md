# network-firewall-policy

A global network firewall policy, its associations with VPC networks and
its rules, as Config Connector objects. A port of terraform-google-modules'
[`network`](https://registry.terraform.io/modules/terraform-google-modules/network/google)
module's
[`modules/network-firewall-policy`](https://github.com/terraform-google-modules/terraform-google-network/tree/91352bed3014ddbfb323d979b6413a90e7253acf/modules/network-firewall-policy)
submodule at v18.3.1 (`91352bed`), Apache-2.0, Copyright Google LLC.
Bundt Package `gcp-network-firewall-policy` (`package.yaml`). Checked
against Config Connector v1.160.0.

## What it renders

| Module resource | Object (`apiVersion`) | `hfl.dev/id` | Cloud name (`resourceID`) |
| --- | --- | --- | --- |
| `google_compute_network_firewall_policy.fw_policy[0]` | `ComputeNetworkFirewallPolicy` (`compute.cnrm.cloud.google.com/v1beta1`) | `policy` | `names.policy`, else `policy_name` (with the `namePrefix` in front when set) |
| `google_compute_network_firewall_policy_association.vpc_associations[<key>]` | `ComputeNetworkFirewallPolicyAssociation` (`v1beta1`) | `association:<key>` | `<policy name>-<the VPC ID's last segment>`, as the module names it |
| `google_compute_network_firewall_policy_rule.rules[<priority>]` | `ComputeNetworkFirewallPolicyRule` (`v1alpha1`: needs `allow_alpha: true`) | `rule:<priority>` | the priority |

Associations are keyed as the module keys them: by `target_vpcs_map`'s
keys, or, when the map is empty, by the base64 of each `target_vpcs`
entry; with a non-empty map, `target_vpcs` is ignored, as in the module.
The regional half of the module (`policy_region` set) and packet mirroring
rules are refused (below).

## Values: module inputs to Config Connector

| Module input | Config Connector |
| --- | --- |
| `project_id` (required) | `spec.projectRef.external` and `cnrm.cloud.google.com/project-id` on every object |
| `policy_name` (required; the module's RFC 1035 validation) | the policy's `resourceID` (or `names.policy`) |
| `description` | the policy's `description` (left out when null) |
| `target_vpcs_map`, `target_vpcs` | one association each: `attachmentTargetRef.external`, the network's self link (`https://www.googleapis.com/compute/v1/projects/<p>/global/networks/<n>`) from the VPC ID or self link given |
| rule `priority` | the rule's `resourceID` |
| `direction`, `action`, `rule_name`, `description` | `direction`, `action`, `ruleName`, `description` (the last two left out when null) |
| `disabled`, `enable_logging` | `disabled`, `enableLogging`; null is rendered `false`, what Terraform records |
| `target_service_accounts` | `targetServiceAccountRefs`, each `{external: <email>}` |
| `target_secure_tags` | `targetSecureTags`, each `{name: <tagValues/...>}`, sorted and unique (the module's `toset`); none when `target_service_accounts` is not null, as in the module |
| `match.src_ip_ranges`, `match.dest_ip_ranges` | `match.srcIpRanges`, `match.destIpRanges` |
| `match.src_fqdns`, `src_region_codes`, `src_threat_intelligences`, `src_address_groups`, `src_secure_tags` | `match.srcFqdns`, `srcRegionCodes`, `srcThreatIntelligences`, `srcAddressGroups`, `srcSecureTags`, for `INGRESS` rules only (dropped for `EGRESS`, as the module drops them) |
| `match.dest_fqdns`, `dest_region_codes`, `dest_threat_intelligences`, `dest_address_groups` | `match.destFqdns`, ..., for `EGRESS` rules only |
| `match.layer4_configs` (default `[{}]`) | `match.layer4Configs`: `ipProtocol` (default `all`), `ports` |
| `is_mirroring` (default `false`) | `false` renders the rule; `true` is refused |
| `tls_inspect`, `security_profile_group_id` | used by the module only with `action: apply_security_profile_group`, which is refused; otherwise no effect, as in the module |
| `src_networks`, `src_network_scope`, `dest_network_scope` | no effect, as in the module: it looks them up in `match`, whose type has no such attributes, so it always sends its defaults (none) |

A list that is empty or null is left out: the module sends an empty list
as no value. Two rules of one priority are refused, as Terraform refuses
the duplicate key; so is setting both `target_secure_tags` and
`target_service_accounts` (the module's validation).

### Not module inputs

| Value | Renders |
| --- | --- |
| `names.policy` | the policy's cloud name in full, used as given (no `namePrefix`), at most 63 characters, starting with a letter; the associations' names derive from it |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `policy_name`, and so of the associations' names. Rules are named by priority within their policy and take none |
| `labels` | Kubernetes labels on every object. Network firewall policies have no Google Cloud labels |
| `tags` | accepted for the catalog's common interface; these resources have no labels, so they stay on the objects |
| `deletion_policy` | `DELETE` (default) or `ABANDON`: the policy, its associations and rules stay in the cloud when the component is deleted. `PREVENT` is refused |
| `allow_alpha` | `true` to render rules (`ComputeNetworkFirewallPolicyRule` is `v1alpha1`); without it, any rule is refused by name |

### Refused when set

| Input | Kind | Why |
| --- | --- | --- |
| `policy_region` | gap | Config Connector v1.160.0 has no regional network firewall policy kinds (`google_compute_region_network_firewall_policy`, its association and its rules) |
| `policy_type` | gap | `ComputeNetworkFirewallPolicy` has no `policyType` |
| `rules` without `allow_alpha: true` | alpha | `ComputeNetworkFirewallPolicyRule` is `v1alpha1` |
| a rule with `is_mirroring: true` | gap | no kind for `google_compute_network_firewall_policy_packet_mirroring_rule` |
| a rule with `action: apply_security_profile_group` | gap | `ComputeNetworkFirewallPolicyRule` has no `securityProfileGroup` or `tlsInspect` |

## Outputs

| Output | From |
| --- | --- |
| `fw_policy` | the policy's ID, `projects/<p>/global/firewallPolicies/<name>` |
| `vpc_associations` | `{<key>: projects/<p>/global/firewallPolicies/<policy>/associations/<name>}` |
| `rules` | `{<priority>: projects/<p>/global/firewallPolicies/<policy>/rules/<priority>}` |

The module outputs whole resources (the policy, in a list, and maps of
associations and rules); the outputs are each one's Terraform ID, the one
field consumers take (`docs/design.md`, "Outputs").

## Differences from the module

- **`disabled` and `enable_logging` are always rendered on a rule.** The
  module passes null when a rule leaves them out; Terraform's state records
  `false`, and the chart renders `false`, so an adopted rule's spec is what
  the state holds.
- **The policy is referred to by its name** (`firewallPolicyRef.external`),
  not by a reference to the policy object. Config Connector resolves a
  reference by object name to the policy's numeric ID
  (`networkFirewallPolicyId`), while Terraform records `firewall_policy` as
  the policy's name; an association's `firewall_policy` cannot change in
  place. The name is what the live offramp run adopted with no change.
  Config Connector retries an association or rule until the policy exists.
- **The target network is a self link.** Terraform records
  `attachment_target` as the network's self link whatever form it was given;
  the chart renders that self link. A target that is a plain name (not a
  VPC ID or self link) is refused.
- **Two target VPCs whose IDs end in the same name** give two associations
  of one name, which the cloud refuses, as with Terraform.

## From Terraform

A module block's arguments are the values, unchanged, plus `allow_alpha:
true` when it has rules. To adopt what Terraform made, keep the names (and
leave `namePrefix` empty): Config Connector acquires the policy by name,
each association by its name and each rule by its priority. Every name is
the caller's, so the chart has no `resource_ids`. Set `deletion_policy:
ABANDON` for the first apply, `terraform state rm` the module, then remove
`ABANDON` (`docs/design.md`, "From Terraform").

## Upstream

Ported from
[`modules/network-firewall-policy`](https://github.com/terraform-google-modules/terraform-google-network/tree/v18.3.1/modules/network-firewall-policy)
at v18.3.1 (`91352bed`, Apache-2.0). [`upstream.yaml`](upstream.yaml)
records the repository, path, release, commit, licence and the date last
synced, and the module is listed in
[`upstream/modules.yaml`](../../../upstream/modules.yaml) as
`gcp/network-network-firewall-policy`. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=network-firewall-policy`: render cases `basic`, `full`
(every ported rule field, both directions, two target VPCs), `target-vpcs`
(the deprecated list), `names`, `offramp` (the offramp fixture's module
call: `fixtures/shared-vpc`, `module.network_firewall_policy`) and `mock`,
each validated against Config Connector v1.160.0's CRD schemas, and the
refusals in `tests/*.fail.yaml`. `tests/mock.values.yaml` (the policy and
one association with the fake cloud's `default` network; no rules, which
are alpha) is for `hack/mock-apply.sh` (`task test-mock`); it has not run
yet, and whether mockgcp serves network firewall policies is not known.

## Changes

- **0.1.0** (2026-11-10): the port.
