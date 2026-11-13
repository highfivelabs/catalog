# net-firewall-policy

A hierarchical, global or regional firewall policy with its rules, packet
mirroring rules and associations, as Config Connector and
config-connector-extensions objects. A port of Cloud Foundation Fabric's
[`modules/net-firewall-policy`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/net-firewall-policy)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-net-firewall-policy` (`package.yaml`). Checked against Config
Connector v1.160.0 and config-connector-extensions at `89806ec7`.

The module was `blocked` in the coverage (`docs/coverage`): Config
Connector has a global network policy's rule
(`ComputeNetworkFirewallPolicyRule`) only as `v1alpha1`, and no regional
policy or packet mirroring kinds. config-connector-extensions now provides
the rule as `compute.gcp.hfl.dev/v1beta1`, so a global policy's rules need
no `allow_alpha`; its regional policy, association and rule kinds and its
packet mirroring rule are `v1alpha1`, so a regional policy and mirroring
rules need `allow_alpha: true` (`docs/design.md`, "Alpha kinds"). The CRDs
are copied in `crds/config-connector-extensions`.

## Example

```yaml
name: test-1
parent_id: folders/1234567890
attachments: {test: folders/4567890123}
ingress_rules:
  icmp:
    priority: 1000
    match: {source_ranges: [0.0.0.0/0], layer4_configs: [{protocol: icmp}]}
```

renders a `ComputeFirewallPolicy` with short name `test-1` under the
folder, its association `test-1-test` and the rule
(`tests/golden/hierarchical.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.policy` | not a fabric variable: the policy's name in full (a hierarchical policy's short name), used as given (no `namePrefix`) and checked (63 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the derived policy name, and so the associations' names, start with `<namePrefix>-`; empty changes nothing |
| `labels`, `tags` | Kubernetes labels on every object; firewall policies take no Google Cloud labels |
| `allow_alpha` | not a fabric variable: accepts a regional policy and packet mirroring rules (config-connector-extensions' `v1alpha1` kinds) |
| `name`, `parent_id`, `region`, `description` | the policy: with `region` null a `ComputeFirewallPolicy` under `parent_id` (`folders/…` or `organizations/…`); with `global` a `ComputeNetworkFirewallPolicy` in project `parent_id`; with a region a `ComputeRegionNetworkFirewallPolicy` (`allow_alpha`) |
| `attachments` | an association per entry, named `<policy>-<key>`: a folder or the organization for a hierarchical policy, a VPC for a network policy (a VPC ID is rendered as its self link, as Terraform records it) |
| `ingress_rules`, `egress_rules` | a rule per entry, keyed `<direction>/<name>`, with fabric's defaults (ingress `allow`, egress `deny`, `disabled: false`, every protocol): ranges (distinct), address groups, FQDNs, region codes and threat intelligences on the source (ingress) or destination (egress) side, target service accounts, secure tags (network policies), target resources (hierarchical) |
| `ingress_mirroring_rules`, `egress_mirroring_rules` | a `ComputeNetworkFirewallPolicyPacketMirroringRule` (`allow_alpha`) per entry on a global policy, as fabric only makes them there: action (`mirror`), security profile group (a key of `security_profile_group_ids`, or as given), target secure tags, ranges and protocols |
| `security_profile_group_ids` | the security profile groups mirroring rules name by key |
| `factories_config`, `factories_data` | the factory: a chart cannot read the caller's files, so `factories_config` is accepted and ignored, and the files' contents go under `factories_data` (`cidrs`, `ingress_rules`, `egress_rules`, `ingress_mirroring_rules`, `egress_mirroring_rules`), with the CIDR file's names expanded in the factory's rules, as fabric does |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the policy, associations and rules |

**Refused**, with a message naming the gap:

- `context`: by design (Bundt's `${...}` expressions and `valueFrom`).
- `tag_bindings`: a network policy's tag binding names the policy by the
  number the cloud assigns, and `TagsLocationTagBinding` cannot reference a
  firewall policy object (gap).
- A rule's `tls_inspect`, `security_profile_group` and the action
  `apply_security_profile_group`: none of the rule kinds has `tlsInspect`
  or `securityProfileGroup` (gap). A mirroring rule's `tls_inspect` and
  `match.source_tags` (the kind has neither).
- On a hierarchical policy, a rule's `target_tags` and `match.source_tags`:
  `ComputeFirewallPolicyRule` has no secure tags (gap).

## Outputs

| Output | Value |
| --- | --- |
| `id` | `locations/global/firewallPolicies/<number>` for a hierarchical policy, `projects/<project>/global/firewallPolicies/<name>` or `projects/<project>/regions/<region>/firewallPolicies/<name>` for a network policy |

## Differences from the module

- **A global association refers to the policy by its name**
  (`firewallPolicyRef.external`), as `network-firewall-policy`'s chart
  does and Terraform records it; rules and the other associations refer to
  the policy object.
- **A rule's `disabled` is always rendered** (`false` unless set), as
  fabric passes it.

## From Terraform

A `module "x" { source = ".../modules/net-firewall-policy" ... }` block's
arguments become the values unchanged (`examples/net-firewall-policy/`).
Factory files become `factories_data`.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/net-firewall-policy`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-firewall-policy)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=net-firewall-policy`: render cases `hierarchical`,
`global`, `regional`, `mirroring`, `names` and `mock`, each validated
against Config Connector v1.160.0's and config-connector-extensions' CRD
schemas, and the refusals in `tests/*.fail.yaml`.

The fake-cloud case (`tests/mock.values.yaml`, `task test-mock
MOCK_CHARTS=net-firewall-policy`) applies a global network policy, which
is Config Connector's own kind. Its rules, the regional kinds and the
mirroring rules are render-tested only: the fake cloud's pin
(`CCE_COMMIT`) predates those config-connector-extensions kinds.
Hierarchical policies need an organization or folder and are not applied.

## Changes

- **0.1.0** (2026-11-12): the port.
