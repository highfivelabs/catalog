# net-cloud-armor

A Cloud Armor security policy, global or regional, with its rules, as a
Config Connector object. A port of Cloud Foundation Fabric's
[`modules/net-cloud-armor`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/net-cloud-armor)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-net-cloud-armor` (`package.yaml`). Checked against Config Connector
v1.160.0.

## Example

```yaml
name: test-premium
parent_id: {project_id: my-project}
rules:
  deny-ip: {priority: 1000, action: deny(403), match: {src_ip_ranges: [10.0.0.0/8]}}
  sqli:
    priority: 2000
    action: deny(403)
    match: {expression: "evaluatePreconfiguredExpr('sqli-v33-stable')"}
```

renders the `ComputeSecurityPolicy` `test-premium` with the two rules and
the default rule (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.policy` | not a fabric variable: the policy's name in full, used as given (no `namePrefix`) and checked (63 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the policy's name starts with `<namePrefix>-`; empty changes nothing |
| `tags` | not a fabric variable: cloud labels on the policy |
| `name`, `description`, `type` | the policy's `resourceID`, description and type |
| `parent_id` | `project_id`: the project the policy is in. `organization_id` and `folder_id` (a hierarchical policy) are refused (below). fabric's check: exactly one is set |
| `region` | null or `global`: a global policy; a region: a regional policy (`spec.region`) |
| `labels` | fabric's policy labels, with the catalog's meaning: Kubernetes labels on the object, and unprefixed ones Google Cloud labels on the policy; global policies only, as fabric checks |
| `adaptive_protection_config` | `adaptiveProtectionConfig.layer7DdosDefenseConfig` (`enable`, true unless set, and `ruleVisibility`); `threshold_configs` is refused |
| `advanced_options_config` | `advancedOptionsConfig` (JSON parsing and custom content types, log level, user IP headers); `request_body_inspection_size` is refused |
| `recaptcha_options_config` | `recaptchaOptionsConfig.redirectSiteKeyRef` |
| `rules` | one `spec.rule` each, ordered by priority: match (source ranges as `SRC_IPS_V1`, or an expression), header action, WAF exclusions, rate limit (with `conformAction: allow`, as fabric), redirect. fabric's rule checks, with its messages, stop the render. `network_match` and `match.recaptcha_options` are refused |
| `default_rule_config` | the default rule at priority 2147483647, matching `*` (action `allow`, description `Default rule.`, preview false unless set) |
| `factories_config`, `factories_data` | a chart cannot read the caller's files: `factories_config` is accepted and ignored, and the rules file's contents go under `factories_data.rules`, merged with `rules` as fabric merges them (a key in both takes `rules`) |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the policy |

Refused (the render stops, naming the gap):

| Variable | Why |
| --- | --- |
| `context` | by design: Bundt expressions (`${...}`) and `valueFrom` replace fabric's `$context` lookups |
| `parent_id.organization_id`, `parent_id.folder_id`, `attachments` | a hierarchical policy: config-connector-extensions' `ComputeOrganizationSecurityPolicyRule` (`v1beta1`) is the firewall shape of the API. It requires a layer-4 match and has no expression match, header action, WAF configuration or redirect, so a Cloud Armor rule cannot be expressed. Config Connector's own organization security policy kinds are `v1alpha1` and the same shape |
| `type: CLOUD_ARMOR_NETWORK`, `ddos_protection`, `user_defined_fields`, `rules.*.network_match` | `ComputeSecurityPolicy` has no network match, DDoS protection or user-defined fields |
| `adaptive_protection_config.layer_7_ddos_defense.threshold_configs` | `ComputeSecurityPolicy`'s `layer7DdosDefenseConfig` has only `enable` and `ruleVisibility` |
| `advanced_options_config.request_body_inspection_size` | `ComputeSecurityPolicy`'s `advancedOptionsConfig` has no such field |
| `rules.*.match.recaptcha_options` | `ComputeSecurityPolicy`'s rules have no `exprOptions` |

## Outputs

| Output | Value |
| --- | --- |
| `id` | `projects/<p>/global/securityPolicies/<name>` (or `regions/<r>`), as the provider computes it |
| `name` | the policy's name |
| `self_link` | the policy's self link, which Config Connector reports |

## From Terraform

A `module "x" { source = ".../modules/net-cloud-armor" ... }` block's
arguments become the values unchanged (`examples/net-cloud-armor/`), with
the rules file's contents under `factories_data.rules`. To adopt an
existing policy, keep its name: Config Connector acquires the policy of
that name (`docs/design.md`, "From Terraform"). Rules are part of the
policy object here, where Terraform has a resource per rule.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/net-cloud-armor`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-cloud-armor)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=net-cloud-armor`: render cases `basic`, `full`,
`regional`, `names` and `mock`, each validated against Config Connector
v1.160.0's CRD schemas, and the refusals in `tests/*.fail.yaml` (fabric's
policy and rule checks among them).

Fake cloud (`task test-mock MOCK_CHARTS=net-cloud-armor`, offload run
`off-catalog-1112231922-19269`, 2026-11-12): a global policy with an IP
rule and a rate limit Ready, the outputs evaluated, deleted and gone.

Live (`task test-live LIVE_CHARTS=net-cloud-armor`, offload run
`off-catalog-1112233146-19468` acting as `cce-live-tests`, which has
`roles/compute.securityAdmin`, 2026-11-12): the same global policy with a
`catalog-run` label Ready, the outputs evaluated (its `id`, `name` and
`self_link`), deleted and gone from Google Cloud; nothing left in the
project. Regional policies are render-tested only.

## Changes

- **0.1.0** (2026-11-12): the port.
