# hierarchical-firewall-policy

A hierarchical firewall policy on an organization or a folder, its rules,
and its associations with folders and the organization, as Config
Connector objects. A port of terraform-google-modules'
[`network`](https://registry.terraform.io/modules/terraform-google-modules/network/google)
module at v18.3.1 (`91352bed`), Apache-2.0, Copyright Google LLC:
[`modules/hierarchical-firewall-policy`](https://github.com/terraform-google-modules/terraform-google-network/tree/91352bed3014ddbfb323d979b6413a90e7253acf/modules/hierarchical-firewall-policy).
Bundt Package `gcp-hierarchical-firewall-policy` (`package.yaml`). Checked
against Config Connector v1.160.0.

A hierarchical firewall policy belongs to an organization or a folder, so
this Package runs only where the platform team's identity does
(`docs/design.md`, "Organization, folders and Config Connector's scope").

## Example

The offramp fixture, as values (`tests/offramp.values.yaml`):

```yaml
parent_node: folders/111111111111
policy_name: ofr-test-baseline
description: "offramp fixture: baseline rules for every project below"
target_folders: ["folders/333333333333", "folders/444444444444"]
rules:
  - priority: 1000
    direction: INGRESS
    action: allow
    rule_name: allow-iap
    match:
      src_ip_ranges: ["35.235.240.0/20"]
      layer4_configs: [{ip_protocol: tcp, ports: ["22", "3389"]}]
  # ... 2000 goto_next, 65000 deny
```

renders a `ComputeFirewallPolicy` (`shortName: ofr-test-baseline` on
`folders/111111111111`), two `ComputeFirewallPolicyAssociation`s and three
`ComputeFirewallPolicyRule`s (`tests/golden/offramp.yaml`). The module
README's example is `tests/basic.values.yaml`.

## Objects

| Terraform resource | Object (all `v1beta1`) | `hfl.dev/id` | Cloud identity (`resourceID`) |
| --- | --- | --- | --- |
| `google_compute_firewall_policy.fw_policy` | `ComputeFirewallPolicy`, named after the component | `policy` | the number the cloud assigns: empty to create, `resource_ids.policy` to adopt |
| `google_compute_firewall_policy_association.target_associations[<target>]` | `ComputeFirewallPolicyAssociation` `<component>-association-<target>` | `association:<target>` | the module's name: the target's last path element (`folders/333` → `333`) |
| `google_compute_firewall_policy_rule.rules[<priority>]` | `ComputeFirewallPolicyRule` `<component>-rule-<priority>` | `rule:<priority>` | none: a rule is its policy's rule at `priority` |

Rules and associations refer to the policy by its object's name
(`firewallPolicyRef.name`), so Config Connector resolves the number.

## Values: module inputs to Config Connector

Every module input is a value of the same name (`values.yaml`,
`values.schema.json`).

### Not module inputs

| Value | Renders |
| --- | --- |
| `names.policy` | the policy's `shortName` in full, used as given (no `namePrefix`), under the module's rule for `policy_name`; not set, it is `policy_name` |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `policy_name` (checked against the 63-character limit and a leading letter). Rules and associations take none (`tests/name-prefix.yaml`) |
| `labels` | Kubernetes labels on every object. Firewall policies have no cloud labels |
| `tags` | Kubernetes labels on every object (no cloud labels to carry them to) |
| `deletion_policy` | `DELETE` (default) or `ABANDON`: the policy, its rules and associations stay when the component is deleted. `PREVENT` is refused |
| `resource_ids` | `{policy: "<number>"}` adopts an existing policy (below); another key is refused |

### The policy and its associations

| Module input | Config Connector |
| --- | --- |
| `parent_node` (required) | `organizationRef` or `folderRef`, `external: <parent_node>` (`organizations/<id>` or `folders/<id>`) |
| `policy_name` (required) | `shortName` (or `names.policy`), under the module's validation `^[a-z][a-z0-9-]{0,62}$` |
| `description` | `description`, when set |
| `target_folders` | one association per entry on `folders/<entry>`, named `<entry>`: the module writes `formatlist("folders/%s", target_folders)`, so entries are folder numbers |
| `target_org` | one association on `organizations/<target_org>`, named `<target_org>` |

### A rule

| Rule key | `ComputeFirewallPolicyRule` |
| --- | --- |
| `priority` (a number, or a numeric string as the module's README writes it) | `priority`; two rules with one priority are refused, as Terraform's `for_each` key refuses them |
| `direction`, `action` | `direction`, `action` |
| `description`, `disabled`, `enable_logging` | the same in lower camel case, when set (left out when null, as the module leaves them) |
| `target_service_accounts` | `targetServiceAccounts[].external`: the emails |
| `target_resources` | `targetResources[].external`: `https://www.googleapis.com/compute/v1/<entry>`, as the module's `formatlist` writes them |
| `match.src_ip_ranges`, `match.dest_ip_ranges` | `match.srcIPRanges`, `match.destIPRanges` |
| `match.src_fqdns`, `src_region_codes`, `src_threat_intelligences`, `src_address_groups` | `match.srcFqdns`, ... on an `INGRESS` rule; dropped on any other, as the module drops them |
| `match.dest_fqdns`, `dest_region_codes`, `dest_threat_intelligences`, `dest_address_groups` | `match.destFqdns`, ... on an `EGRESS` rule; dropped on any other |
| `match.layer4_configs` | `match.layer4Configs`: `ipProtocol` (default `all`) and `ports` when not empty; the module's default, one config for `all`, when not set |
| `rule_name` | nothing: the module takes it and does not use it |

Empty lists are not sent, as the provider does not send them.

### Refused when set

| Input | Why |
| --- | --- |
| `rules[].match.src_networks`, `src_network_scope`, `dest_network_scope` | `ComputeFirewallPolicyRule`'s match has no `srcNetworks`, `srcNetworkScope` or `destNetworkScope` at v1.160.0 (a gap; `rules`, partial, in `upstream.yaml`) |
| two rules with one `priority` | Terraform refuses the duplicate key |
| `resource_ids` other than `policy` | only the policy has a number the cloud assigns |
| `deletion_policy: PREVENT` | no Config Connector equivalent |

## Adopting existing resources

The cloud names a hierarchical firewall policy with a number
(`locations/global/firewallPolicies/<number>`). Config Connector creates a
new policy unless `spec.resourceID` holds that number, so to adopt a policy
Terraform made, give its number under the policy object's id:

```yaml
resource_ids:
  policy: "123456789012"   # google_compute_firewall_policy.fw_policy.name
```

It is rendered as the policy's `spec.resourceID`. Empty (the default)
creates a new policy. The offramp converter fills it from the Terraform
state. Rules (found by policy and priority) and associations (by policy and
name) need nothing: their identities are inputs.

## Outputs

The module's three outputs are whole Terraform objects; each is the one
field consumers take (`docs/design.md`, "Outputs").

| Output | From |
| --- | --- |
| `fw_policy` | the policy's number (`name` in Terraform): `spec.resourceID`, else `status.id` |
| `target_associations` | `{<attachment target>: <association name>}` |
| `rules` | `{<priority>: <rule's resource name>}` (`status.externalRef`) |

## Differences from the module

- **`target_folders` as `folders/<id>`.** The module prefixes every entry
  with `folders/`, so an entry already written `folders/333` becomes the
  attachment target `folders/folders/333` (named `333`), which the API
  refuses. The chart does the same, so a module call converts to identical
  values and an identical render; the offramp fixture is such a call.
- **Unset optional rule fields** (`description`, `disabled`,
  `enable_logging`) are left out, not sent as `false` or `""`; the cloud's
  defaults are the same.
- **`resource_ids`** is not a module input (above).

## Upstream

Ported from
[`modules/hierarchical-firewall-policy`](https://github.com/terraform-google-modules/terraform-google-network/tree/v18.3.1/modules/hierarchical-firewall-policy)
at v18.3.1 (`91352bed`, Apache-2.0). [`upstream.yaml`](upstream.yaml)
records the repository, path, release, commit, licence and the date last
synced, and the module is listed in
[`upstream/modules.yaml`](../../../upstream/modules.yaml) as
`gcp/network-hierarchical-firewall-policy`. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=hierarchical-firewall-policy`: five render cases
(`basic`, `full`, `names`, `offramp`, `mock`), each validated against
Config Connector v1.160.0's CRD schemas, and the refusals in
`tests/*.fail.yaml`. `tests/mock.values.yaml` (a policy with one rule on a
placeholder folder, no association: the policy has no project, and mockgcp
takes any parent) is for `hack/mock-apply.sh` (`task test-mock`); it has
not run yet.

## Changes

- **0.1.0** (2026-11-10): the port.
