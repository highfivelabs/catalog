# net-cloudnat

A Cloud NAT gateway and, optionally, the Cloud Router it runs on, as
Config Connector objects. A port of Cloud Foundation Fabric's
[`modules/net-cloudnat`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/net-cloudnat)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-net-cloudnat` (`package.yaml`). Checked against Config Connector
v1.160.0.

A team's first network on Google Cloud usually has private nodes (a
private GKE cluster, VMs without external addresses); this chart gives
them egress to the internet, next to `net-vpc`.

## Example

```yaml
project_id: my-project
region: europe-west8
name: default
router_network: my-vpc
```

renders the `ComputeRouter` `default-nat` on `my-vpc` and the
`ComputeRouterNAT` `default` on it, with automatically allocated addresses
for every subnet's ranges (`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `google_compute_router.router` | `router_create` (the default) | `ComputeRouter` (`compute.cnrm.cloud.google.com/v1beta1`), `router` |
| `google_compute_router_nat.nat` | always | `ComputeRouterNAT` (`v1beta1`), `nat`, on the router above or on the existing `router_name` |

## Values: module inputs to Config Connector

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`).

| Module input | Config Connector |
| --- | --- |
| `project_id` (required) | `cnrm.cloud.google.com/project-id` on both objects |
| `region` (required) | `spec.region` of both |
| `name` (required) | the NAT's `spec.resourceID` |
| `router_create` | whether the `ComputeRouter` is rendered |
| `router_name` | with `router_create`: the router's name (default `<name>-nat`, as fabric names it); without: the existing router, `routerRef.external` `projects/<project>/regions/<region>/routers/<router_name>` (a `projects/...` path is taken as is). Required then |
| `router_network` | the router's `networkRef.external`, the network's self link, as Terraform records it: a name is in `project_id`; a `projects/...` path or a self link is taken as is. Required with `router_create` |
| `router_asn` | the router's `bgp.asn` |
| `type` | `type` (`PUBLIC` or `PRIVATE`) |
| `addresses` | `natIps`, each `{external: <address>}`; `natIpAllocateOption` is `MANUAL_ONLY` with addresses, `AUTO_ONLY` without, and left out for a `PRIVATE` NAT, as the module sets it |
| `endpoint_types` | `endpointTypes` |
| `config_source_subnetworks` | `sourceSubnetworkIpRangesToNat` (`ALL_SUBNETWORKS_ALL_IP_RANGES`, `ALL_SUBNETWORKS_ALL_PRIMARY_IP_RANGES` with `primary_ranges_only`, `LIST_OF_SUBNETWORKS` with `all: false`) and, for a list, one `subnetwork` per entry: `subnetworkRef.external` (its `self_link`), `sourceIpRangesToNat` and `secondaryIpRangeNames` as the module computes them |
| `config_timeouts` | `icmpIdleTimeoutSec`, `tcpEstablishedIdleTimeoutSec`, `tcpTimeWaitTimeoutSec`, `tcpTransitoryIdleTimeoutSec`, `udpIdleTimeoutSec`, each when set |
| `config_port_allocation` | `enableEndpointIndependentMapping` (default `true` for `PUBLIC`, `false` for `PRIVATE`), `enableDynamicPortAllocation` (the reverse), `minPortsPerVm` when set, `maxPortsPerVm` (default 65536, always sent, as the module sends it) |
| `logging_filter` | `logConfig`: `enable` when set, `filter` it or `ALL` |
| `rules` | `rules`: `ruleNumber` (`rule_number`, else the entry's index), `description`, `match`, `action.sourceNatActiveIpsRefs` (`source_ips`) and `action.sourceNatActiveRangesRefs` (`source_ranges`), each `{external: ...}` |
| `context` | refused (below) |

The module's validations stop the render with the module's own messages:
dynamic port allocation without endpoint-independent mapping off,
endpoint-independent mapping on a `PRIVATE` NAT, a subnetwork entry with
both or neither of `all_ranges` and specific ranges, `all` or
`primary_ranges_only` together with a list, a `PRIVATE` NAT with primary
ranges only, a rule without `source_ips` or `source_ranges`, and two rules
with one resolved number.

### Not module inputs

| Value | Renders |
| --- | --- |
| `names.nat`, `names.router` | the NAT's and the router's cloud names in full, used as given; `names.router` only with `router_create` (it is refused otherwise: the existing router is `router_name`) |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of the NAT's name and of the name of the router the chart makes, never of a name under `names` nor of an existing router; checked against the 63-character limit and the leading letter |
| `labels` | Kubernetes labels on every object. Routers and NAT gateways have no Google Cloud labels |
| `tags` | accepted for the catalog's common interface; routers and NAT gateways have no labels, so they stay on the objects |
| `deletion_policy` | `DELETE` (default) or `ABANDON`: the NAT and the router stay in the cloud when the component is deleted. `PREVENT` is refused |

### Refused when set

| Variable | Why |
| --- | --- |
| `context` | use Bundt's `${...}` expressions and `valueFrom` |

## Outputs

| Output | From |
| --- | --- |
| `name` | the NAT's `spec.resourceID` |
| `region` | the NAT's `spec.region` |
| `router_name` | the router's `spec.resourceID`, or `router_name` without `router_create` |
| `id` | `<project>/<region>/<router>/<name>`, the `google_compute_router_nat`'s id |
| `nat_ip_allocate_option` | the NAT's `natIpAllocateOption`, null for a `PRIVATE` NAT |

`ComputeRouterNAT` reports no status but its conditions, so every output
comes from the spec, as Terraform computes it. Not an output: `router`,
fabric's whole `google_compute_router` object (`docs/design.md`,
"Outputs"); `router_name` is what consumers take from it.

## Differences from the module

- **The router's network is a self link.** Terraform records a router's
  `network` as the network's self link whatever form the module was given;
  the chart renders that self link. A `router_network` such as
  `global/networks/<name>` is refused.
- **References are given as the module takes them.** Addresses, subnets
  and the rules' sources are self links or `projects/...` paths in the
  values, and go to Config Connector as `external` references. A team that
  makes them in another component passes them through Bundt's expressions.

## From Terraform

A module block's arguments are the values, unchanged. To adopt the router
and NAT Terraform made, keep their names (and leave `namePrefix` empty):
Config Connector acquires a router and a NAT whose `resourceID` matches.
Set `deletion_policy: ABANDON` for the first apply, `terraform state rm` the
module, then remove `ABANDON` (`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/net-cloudnat`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-cloudnat)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
as `gcp/net-cloudnat`. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=net-cloudnat`: render cases `basic`, `full` (every input of
a public NAT on a router the chart makes), `private` (a `PRIVATE` NAT on an
existing router), `names` and `mock`, each validated against Config
Connector v1.160.0's CRD schemas, and the refusals in `tests/*.fail.yaml`
(the module's validations, names, `context`, `PREVENT`).
`tests/mock.values.yaml` (a router on the fake cloud's `default` network
and an automatic NAT) is for `hack/mock-apply.sh` (`task test-mock`); it
has not run yet, nor has the chart been applied to a real project.

## Changes

- **0.1.0** (2026-11-12): the port.
