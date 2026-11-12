# net-vpc-firewall

VPC firewall rules for an existing network, custom and fabric's default
rules, as Config Connector objects. A port of Cloud Foundation Fabric's
[`modules/net-vpc-firewall`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/net-vpc-firewall)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-net-vpc-firewall` (`package.yaml`). Checked against Config Connector
v1.160.0. It pairs with `net-vpc`: `network` names the network.

## Example

```yaml
project_id: my-project
network: my-network
ingress_rules:
  allow-ingress-ntp:
    targets: [ntp-svc]
    rules: [{protocol: udp, ports: ["123"]}]
```

renders the `ComputeFirewall` `allow-ingress-ntp` and fabric's three
default rules (`my-network-ingress-tag-http`, `-https`, `-ssh`)
(`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.admins`, `names.http`, `names.https`, `names.ssh` | not fabric variables: the default rules' names in full, used as given (no `namePrefix`); unset, `<network>-ingress-admins`, `-tag-http`, `-tag-https`, `-tag-ssh`, as fabric names them (`docs/design.md`, "Names, labels and tags"). Custom rules are named by their keys |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every rule name the chart derives starts with `<namePrefix>-`; empty changes nothing |
| `labels`, `tags` | Kubernetes labels on every object; firewall rules take no Google Cloud labels |
| `project_id`, `network` | the project annotation and `networkRef` (a name becomes `projects/<project>/global/networks/<name>`; a self link is used as given) |
| `ingress_rules`, `egress_rules` | one `ComputeFirewall` each, named by its key, with fabric's defaults: ingress allows and egress denies, all protocols, priority 1000; `0.0.0.0/0` for an ingress rule's missing source ranges (without `sources`) and an egress rule's missing destination ranges; `sources` and `targets` are tags, or service accounts with `use_service_accounts`; `enable_logging` is `logConfig` |
| `named_ranges` | names usable in a rule's ranges, expanded |
| `default_rules_config` | fabric's convenience rules: admin ranges to everything, HTTP, HTTPS and SSH from their ranges to their tags; `disabled`, or an empty list, turns one off |
| `factories_config` | accepted and ignored: a chart cannot read the caller's files (`docs/design.md`, "Submodules and factories") |
| `factories_data` | not a fabric variable: the files' contents. `rules`, by file, each `{ingress: {NAME: rule}, egress: {NAME: rule}}` as the module's `rules_folder` holds it (factory rules allow by default, as fabric); `cidr_tpl`, the `cidr_tpl_file`'s named ranges, under `named_ranges` |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the rules |

Refused when set:

| Variable | Why |
| --- | --- |
| `context` | use Bundt's `${...}` expressions and `valueFrom` |

## Outputs

None: fabric's `default_rules` and `rules` are maps of whole Terraform
objects, which a Package does not output (`docs/design.md`, "Outputs").

## Differences from the module

- `disabled: false` is rendered on every custom rule, as fabric sends it.
- A rule whose name is in more than one of the factory files, `egress_rules`
  and `ingress_rules` is the last one's, as fabric's `merge` makes it.

## From Terraform

A `module "x" { source = ".../modules/net-vpc-firewall" ... }` block's
arguments become the values unchanged; a rules folder's files go under
`factories_data.rules` (`examples/net-vpc-firewall/`). To adopt existing
rules, keep their names: Config Connector acquires the rules of those
names (`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/net-vpc-firewall`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpc-firewall)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=net-vpc-firewall`: render cases `basic`, `full` (every
field the chart carries), `no-defaults`, `names` and `mock`, each validated
against Config Connector v1.160.0's CRD schemas, and the refusals in
`tests/*.fail.yaml`.

Applied to the fake cloud on 2026-11-12 on an offload VM (`task test-mock
MOCK_CHARTS=net-vpc-firewall`): `tests/mock.values.yaml`, the SSH default
rule, a custom ingress rule and a custom egress rule on the network in
`tests/mock.needs.yaml`: all 3 objects Ready, all deleted.

Applied live on 2026-11-12 (`task test-live LIVE_CHARTS=net-vpc-firewall`,
offload VM as `cce-live-tests`, which has `roles/compute.securityAdmin`):
the SSH default rule, an ingress rule with a named range and an egress
rule with logging, on a network made for the run: all Ready, deleted with
the network, and gone from Google Cloud.

## Changes

- **0.1.0** (2026-11-12): the port: custom, factory and default rules.
