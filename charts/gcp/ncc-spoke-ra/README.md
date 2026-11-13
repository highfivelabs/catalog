# ncc-spoke-ra

A Network Connectivity Center router appliance spoke, its Cloud Router with
two redundant interfaces and a pair of BGP peers per appliance, and
optionally its hub and route policies, as Config Connector objects. A port
of Cloud Foundation Fabric's
[`modules/ncc-spoke-ra`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/ncc-spoke-ra)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-ncc-spoke-ra` (`package.yaml`). Checked against Config Connector
v1.160.0 and config-connector-extensions at `89806ec7`.

The module was `blocked` in the coverage (`docs/coverage`): Config
Connector has no kind for a router's route policies. config-connector-extensions
now provides `ComputeRouterRoutePolicy` (`compute.gcp.hfl.dev/v1alpha1`),
so the chart renders route policies with `allow_alpha: true`
(`docs/design.md`, "Alpha kinds"; the CRD is copied in
`crds/config-connector-extensions`). Everything else is Config Connector's
own `v1beta1` kinds.

## Example

```yaml
hub: {id: projects/my-project/locations/global/hubs/hub}
name: spoke-ra
project_id: my-project
region: europe-west1
router_appliances:
  - {internal_ip: 10.0.0.3, vm_self_link: projects/my-project/zones/europe-west1-b/instances/router-app-a}
router_config: {asn: 65000, ip_interface0: 10.0.0.14, ip_interface1: 10.0.0.15, peer_asn: 65001}
vpc_config: {network_name: my-vpc, subnet_self_link: projects/my-project/regions/europe-west1/subnetworks/subnet}
```

renders the spoke `spoke-ra`, the router `spoke-ra-cr`, its interfaces
`spoke-ra-cr-intf0` and `-intf1`, and the peers
`spoke-ra-cr-router-app-a-peer1` and `-peer2` (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.spoke`, `names.router`, `names.hub` | not fabric variables: the spoke's, router's and new hub's names in full, used as given (no `namePrefix`) and checked (63 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every derived name starts with `<namePrefix>-` (the interfaces and peers take it from the router's name); empty changes nothing |
| `labels`, `tags` | Kubernetes labels on every object; unprefixed ones, and `tags`, become Google Cloud labels on the hub and the spoke |
| `allow_alpha` | not a fabric variable: accepts route policies (config-connector-extensions' `v1alpha1` kind) |
| `hub` | with `create`, a `NetworkConnectivityHub` named `hub.name`, which the spoke refers to; else the spoke's `hubRef` is `hub.id`. fabric's validation, with its message |
| `name`, `project_id`, `region` | the spoke's name, project and location; the router is `<name>-cr` |
| `data_transfer` | the spoke's `siteToSiteDataTransfer` |
| `router_appliances` | the spoke's linked instances, and two `ComputeRouterPeer`s per appliance (`<router>-<vm>-peer1` and `-peer2`), one on each interface |
| `router_config` | the router's ASN, advertisement (`CUSTOM` with `custom_advertise`, its groups and ranges) and keepalive; the interfaces' IPs; the peers' ASN and route priority (100 unless set); `route_policies` as `ComputeRouterRoutePolicy`s (`allow_alpha`), with fabric's validations |
| `vpc_config` | the router's network (a bare name is taken in `project_id`) and the interfaces' subnet |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the hub, spoke, router and policies |

**Refused**, with a message naming the gap: an appliance's
`import_policies` and `export_policies`, since `ComputeRouterPeer` has no
`importPolicies` or `exportPolicies` field, so a route policy cannot be
attached to a peer yet.

## Outputs

| Output | Value |
| --- | --- |
| `id` | the new hub's ID, `projects/<p>/locations/global/hubs/<name>`; null with an existing hub, as fabric's |
| `route_policies` | `{key: projects/<p>/regions/<r>/routers/<router>/routePolicies/<name>}` |

Not outputs: `hub`, `router` and `spoke_ra`, whole Terraform objects
(`docs/design.md`, "Outputs").

## From Terraform

A `module "x" { source = ".../modules/ncc-spoke-ra" ... }` block's
arguments become the values unchanged (`examples/ncc-spoke-ra/`).

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/ncc-spoke-ra`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/ncc-spoke-ra)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=ncc-spoke-ra`: render cases `basic`, `full` and `names`,
each validated against Config Connector v1.160.0's and
config-connector-extensions' CRD schemas, and the refusals in
`tests/*.fail.yaml`. Render-tested only: a spoke needs a router appliance
VM, which the live tests do not make (no VMs), and route policies'
extension kind is newer than the fake cloud's pin (`CCE_COMMIT`).

## Changes

- **0.1.0** (2026-11-12): the port.
