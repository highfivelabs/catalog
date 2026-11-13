# secops-rules

Google SecOps detection rules, their deployments and reference lists, as
config-connector-extensions objects. A port of Cloud Foundation Fabric's
[`modules/secops-rules`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/secops-rules)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-secops-rules` (`package.yaml`). Checked against
config-connector-extensions' CRDs (`crds/config-connector-extensions`):
`ChronicleRule` and `ChronicleReferenceList` (`chronicle.gcp.hfl.dev/v1beta1`)
and `ChronicleRuleDeployment` (`v1alpha1`).

**Rules need `allow_alpha: true`.** Fabric deploys every rule it makes,
and the deployment's kind is `v1alpha1` (`docs/design.md`, "Alpha kinds").
Reference lists alone need no alpha kind.

## Example

```yaml
allow_alpha: true
project_id: my-project
tenant_config: {customer_id: 3fb9b8b0-6a5a-4b0b-8a6f-b1a7b1f6c1d2, region: europe}
reference_lists_config:
  private_ip_ranges: {description: "Private IP ranges", type: CIDR}
rules_config:
  network_traffic_to_specific_country: {enabled: true, alerting: true, run_frequency: LIVE}
factories_data:
  reference_lists:
    private_ip_ranges: |-
      10.0.0.0/8
      172.16.0.0/12
  rules:
    network_traffic_to_specific_country: |
      rule network_traffic_to_specific_country { ... }
```

renders the reference list, the rule and its deployment
(`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `project_id`, `tenant_config` | every object's project, and the SecOps instance (`customer_id`) and its location (`region`) |
| `reference_lists_config` | a `ChronicleReferenceList` per entry, its ID the key (rules name it so, `%key`), with `description` and `type` (`CIDR`, `STRING`, `REGEX`; fabric's check), its entries the lines of `factories_data.reference_lists.<key>` |
| `rules_config` | a `ChronicleRule` per entry, its text `factories_data.rules.<key>`, deleted with `FORCE` as fabric's, and its `ChronicleRuleDeployment` with `enabled` (default true), `alerting`, `archived` and `run_frequency` (`LIVE`, `HOURLY` or `DAILY`; fabric's check, with fabric's message). Needs `allow_alpha` |
| `factories_config` | `rules_defs` and `reference_lists_defs` only name the folders in messages; `rules` and `reference_lists` (YAML files) are refused, by design: a chart cannot read the caller's files, so their content goes in `rules_config` and `reference_lists_config` |
| `factories_data` | not a Terraform variable: the files of the `_defs` folders, as data (`docs/design.md`, "Submodules and factories"). `rules`: `{RULE: YARA-L text}` (was `<rules_defs>/RULE.yaral`); `reference_lists`: `{LIST: text}`, one entry per line as fabric splits it, or a list of entries (was `<reference_lists_defs>/LIST.txt`). A rule or list without its data stops the render, naming the file |
| `allow_alpha`, `deletion_policy`, `names`, `namePrefix`, `labels`, `tags` | not fabric variables. The chart gives no derived names (a list's ID is its key, a rule's the API's), so `names` and `namePrefix` change nothing; rules and lists take no cloud labels |

## Outputs

Fabric's module declares none.

## From Terraform

A `module "x" { source = ".../modules/secops-rules" ... }` block's
arguments become the values unchanged, with `allow_alpha: true` for
rules; the files under `data/rules` and `data/reference_lists` go in
`factories_data`, one entry per file, and the `rules` and
`reference_lists` YAML files' content in `rules_config` and
`reference_lists_config`. A reference list keeps its ID, so it adopts the
list Terraform made; a rule's ID is the API's, so adopting a rule needs
its `ru_...` ID (`ChronicleRule`'s `resourceID`), which the chart does
not take yet.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/secops-rules`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/secops-rules)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=secops-rules`: render cases `basic` (the module's README
example), `lists` (reference lists only, no alpha kind) and `mock`,
validated against config-connector-extensions' CRDs, and the refusals in
`tests/*.fail.yaml`. Not applied live: live runs are pending KEYLIVE.

## Changes

- **0.1.0** (2026-11-13): the port: reference lists, rules and their
  deployments.
