# firewall-rules

VPC firewall rules on one network, as Config Connector `ComputeFirewall`
objects. A port of terraform-google-modules'
[`network`](https://registry.terraform.io/modules/terraform-google-modules/network/google)
module's
[`modules/firewall-rules`](https://github.com/terraform-google-modules/terraform-google-network/tree/91352bed3014ddbfb323d979b6413a90e7253acf/modules/firewall-rules)
submodule at v18.3.1 (`91352bed`), Apache-2.0, Copyright Google LLC.
Bundt Package `gcp-firewall-rules` (`package.yaml`). Checked against Config
Connector v1.160.0.

The network module's root calls this submodule for its `ingress_rules`,
`egress_rules` and `firewall_rules` inputs; a module block of the root
module converts to a network chart and this chart.

## What it renders

One `ComputeFirewall` (`compute.cnrm.cloud.google.com/v1beta1`) per rule,
as the module makes one `google_compute_firewall` per rule:

| Module resource | When | Objects (`hfl.dev/id`) |
| --- | --- | --- |
| `google_compute_firewall.rules[<name>]` | `rules` (deprecated) is not empty | `rules:<name>` |
| `google_compute_firewall.rules_ingress_egress[<name>]` | `rules` is empty | `rules_ingress_egress:<name>`, from `ingress_rules` and `egress_rules` |

As in the module, a non-empty `rules` makes `ingress_rules` and
`egress_rules` ignored, and an `egress_rules` entry wins over an
`ingress_rules` entry of the same name (the module's `merge`). Two entries
of one name in one list are refused, as Terraform refuses the duplicate
key.

## Values: module inputs to Config Connector

| Module input | Config Connector (`ComputeFirewall`) |
| --- | --- |
| `project_id` (required) | `cnrm.cloud.google.com/project-id` on every object; the network's project when `network_name` is a name |
| `network_name` (required) | `spec.networkRef.external`, the network's self link (`https://www.googleapis.com/compute/v1/projects/<project>/global/networks/<name>`): a name is in `project_id`; a `projects/...` path or a self link is taken as is |
| rule `name` | `spec.resourceID` (with the `namePrefix` in front when set) |
| `description` | `description` (left out when null or empty) |
| `direction` (`rules` only; default `INGRESS`), or the list | `direction` |
| `disabled` | `disabled`; null is rendered `false`, what Terraform records |
| `priority` | `priority`; null is rendered `1000`, the provider's default and what Terraform records |
| `ranges` (`rules` only) | `sourceRanges` for `INGRESS`, `destinationRanges` for `EGRESS` |
| `source_ranges`, `destination_ranges` (`ingress_rules`, `egress_rules`) | `sourceRanges`, `destinationRanges`, whatever the direction, as the module passes them |
| `source_tags`, `target_tags` | `sourceTags`, `targetTags` |
| `source_service_accounts`, `target_service_accounts` | `sourceServiceAccounts`, `targetServiceAccounts`, each `{external: <email>}` |
| `allow`, `deny` (`protocol`, `ports`) | `allow`, `deny` (`ports` as strings, left out when null) |
| `log_config.metadata` | `logConfig.metadata` |

A list that is empty or null is left out: the module sends an empty list
as no value, and Terraform records it as empty or null.

### Not module inputs

| Value | Renders |
| --- | --- |
| `names` | takes no key: the chart gives no singular resource a name; every rule names itself in its entry |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of every rule's name, checked against the 63-character limit and the leading letter |
| `labels` | Kubernetes labels on every object. Firewall rules have no Google Cloud labels |
| `tags` | accepted for the catalog's common interface; firewall rules have no labels, so they stay on the objects |
| `deletion_policy` | `DELETE` (default) or `ABANDON`: every rule stays in the cloud when the component is deleted. `PREVENT` is refused |

### Refused when set

Nothing: `ComputeFirewall` carries every attribute the module sets.

## Outputs

| Output | From |
| --- | --- |
| `firewall_rules` | `{<name>: <self link>}` of the `rules` objects (`status.selfLink`) |
| `firewall_rules_ingress_egress` | `{<name>: <self link>}` of the `ingress_rules` and `egress_rules` objects |

The module outputs maps of whole `google_compute_firewall` resources, keyed
by rule name; the outputs are the same maps of each rule's self link, the
one field consumers take (`docs/design.md`, "Outputs"). A rule not yet
ready has `''`.

## Differences from the module

- **`disabled` and `priority` are always rendered.** The module passes
  null when an entry leaves them out; the provider then sends no
  `disabled` (the API's default is `false`) and its default priority
  `1000`, and Terraform's state records `false` and `1000`. The chart
  renders those values, so an adopted rule's spec is what the state holds
  and nothing is sent that differs.
- **The network is a self link.** Terraform records `network` as the
  network's self link whatever form the module was given; the chart
  renders that self link as `networkRef.external`. A `network_name` such as
  `global/networks/<name>` (neither a name, a `projects/...` path nor a self
  link) is refused.
- **`allow` and `deny` keep the order of the values.** They are sets in
  Terraform and in Config Connector's `ComputeFirewall` (a Terraform-based
  kind), so the order changes nothing in the cloud; Terraform's state lists
  them in its own order.
- `enableLogging` (deprecated) is never rendered: the module does not set
  it; `log_config` is how it enables logging.

## From Terraform

A module block's arguments are the values, unchanged. To adopt the rules
Terraform made, keep their names (and leave `namePrefix` empty): Config
Connector acquires a firewall rule whose `resourceID` matches. Set
`deletion_policy: ABANDON` for the first apply, `terraform state rm` the
module, then remove `ABANDON` (`docs/design.md`, "From Terraform"). No
resource has a server-assigned name, so the chart has no `resource_ids`.

## Upstream

Ported from
[`modules/firewall-rules`](https://github.com/terraform-google-modules/terraform-google-network/tree/v18.3.1/modules/firewall-rules)
at v18.3.1 (`91352bed`, Apache-2.0). [`upstream.yaml`](upstream.yaml)
records the repository, path, release, commit, licence and the date last
synced, and the module is listed in
[`upstream/modules.yaml`](../../../upstream/modules.yaml) as
`gcp/network-firewall-rules`. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=firewall-rules`: render cases `basic`, `full` (every input
of `ingress_rules` and `egress_rules`, and a name in both lists), `legacy`
(the deprecated `rules`, with `ingress_rules` ignored), `names`, `offramp`
(the offramp fixture's module call: `fixtures/shared-vpc`, `module.vpc`'s
firewall rules) and `mock`, each validated against Config Connector
v1.160.0's CRD schemas, and the refusals in `tests/*.fail.yaml`.
`tests/mock.values.yaml` (two rules on the fake cloud's `default` network)
is for `hack/mock-apply.sh` (`task test-mock`); it has not run yet.

## Changes

- **0.1.0** (2026-11-10): the port.

### Fake cloud, 2026-11-11

`task test-mock` on an offload VM (run `off-catalog-1111013211-26916`, config-connector-extensions `1de95478`): both rules Ready (UpToDate) and deleted. Live: the offramp's shared-vpc run `ofr-11110129-7049` adopted the three rules of `tests/offramp.values.yaml`'s call in hfl-dev-514205 with zero mutating calls (`offramp/results/` on branch `tf-offramp-charts`).
