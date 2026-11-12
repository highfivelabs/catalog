# net-vpc-peering

A VPC network peering, and optionally its peer side, between two networks,
as Config Connector objects. A port of Cloud Foundation Fabric's
[`modules/net-vpc-peering`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/net-vpc-peering)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-net-vpc-peering` (`package.yaml`). Checked against Config Connector
v1.160.0.

## Example

```yaml
local_network: projects/my-project/global/networks/local
peer_network: projects/peer-project/global/networks/peer
```

renders the `ComputeNetworkPeering`s `local-peer` and `peer-local`
(`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.local`, `names.peer` | not fabric variables: the peerings' names in full, used as given (no `namePrefix`) and checked (63 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the peering names (fabric's `name` and the derived ones) start with `<namePrefix>-`; empty changes nothing |
| `labels`, `tags` | Kubernetes labels on every object; peerings take no Google Cloud labels |
| `local_network`, `peer_network` | `networkRef` and `peerNetworkRef` of each side (a `https://www.googleapis.com/compute/v1/` self link is shortened to the id) |
| `name`, `prefix` | the peerings' names: `name.local` and `name.peer`, else `<prefix>-<this network>-<other network>`, as fabric; fabric's 63-character check on the derived name |
| `peer_create_peering` | the peer side's `ComputeNetworkPeering` (true, the default) |
| `routes_config` | each side's `exportCustomRoutes` and `importCustomRoutes` (true unless set, as fabric) and the public-IP subnet route flags |
| `stack_type` | `stackType` on both sides |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the peerings |

Nothing is refused.

## Outputs

None: fabric's `local_network_peering` and `peer_network_peering` are
whole Terraform objects, which a Package does not output
(`docs/design.md`, "Outputs").

## From Terraform

A `module "x" { source = ".../modules/net-vpc-peering" ... }` block's
arguments become the values unchanged (`examples/net-vpc-peering/`). To
adopt existing peerings, keep their names: Config Connector acquires the
peerings of those names (`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/net-vpc-peering`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpc-peering)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=net-vpc-peering`: render cases `basic`, `full`,
`one-side` and `names`, each validated against Config Connector v1.160.0's
CRD schemas, and the refusals in `tests/*.fail.yaml`.

No fake-cloud case: the fake cloud's Compute Engine does not implement
`AddPeering` (a run on 2026-11-12 failed with `501 method AddPeering not
implemented`). Applied live instead on 2026-11-12 (`task test-live
LIVE_CHARTS=net-vpc-peering`, offload VM as `cce-live-tests`): both sides
between two networks made for the run, the local side not importing
routes: both peerings Ready, deleted with the networks, and gone from
Google Cloud.

## Changes

- **0.1.0** (2026-11-12): the port.
