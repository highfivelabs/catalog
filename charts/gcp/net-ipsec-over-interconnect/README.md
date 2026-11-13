# net-ipsec-over-interconnect

An HA VPN gateway whose two interfaces are on two VLAN attachments (IPsec
over Cloud Interconnect), the external peer gateway it connects to, a
Cloud Router and the router's BGP route policies, as Config Connector
objects. A port of Cloud Foundation Fabric's
[`modules/net-ipsec-over-interconnect`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/net-ipsec-over-interconnect)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-net-ipsec-over-interconnect` (`package.yaml`). Checked against
Config Connector v1.160.0 and config-connector-extensions (route
policies). The VLAN attachments come from the `net-vlan-attachment`
chart (its `id` output), as in fabric.

## Example

```yaml
project_id: my-project
region: europe-west8
network: projects/my-project/global/networks/my-network
name: vpn-ipsec
interconnect_attachments:
  a: projects/my-project/regions/europe-west8/interconnectAttachments/vlan-a
  b: projects/my-project/regions/europe-west8/interconnectAttachments/vlan-b
peer_gateway_config:
  create: true
  interfaces: [172.16.0.1, 172.16.0.2]
router_config: {asn: 64514}
```

renders the `ComputeVPNGateway` `vpn-gw-vpn-ipsec` on the two
attachments, the `ComputeExternalVPNGateway` `peer-vpn-gw-vpn-ipsec` and
the `ComputeRouter` `router-vpn-ipsec` (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.gateway`, `names.peer_gateway`, `names.router` | not fabric variables: the gateway's, the peer gateway's and the router's names in full, used as given (no `namePrefix`) and checked (63 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every name the chart derives starts with `<namePrefix>-`; empty changes nothing |
| `labels`, `tags` | Kubernetes labels on every object; unprefixed ones and `tags` reach the resources that take Google Cloud labels |
| `allow_alpha` | not a fabric variable: accepts the v1alpha1 kind route policies need (`docs/design.md`, "Alpha kinds") |
| `name`, `project_id`, `region`, `network` | the gateway (`vpn-gw-<name>`), the peer gateway (`peer-vpn-gw-<name>`) and router (`router-<name>`), their project and region; the gateway's and router's `networkRef` |
| `interconnect_attachments` | the gateway's `vpnInterfaces` 0 and 1, on attachments `a` and `b` (IDs or self links) |
| `peer_gateway_config` | `create: true` makes the `ComputeExternalVPNGateway`, `name` or `peer-vpn-gw-<name>`, with its description (fabric's default) and one or two `interfaces` (`SINGLE_IP_INTERNALLY_REDUNDANT` or `TWO_IPS_REDUNDANCY`); otherwise `id` names an existing one (fabric's check, with its message) |
| `router_config` | required, as in fabric. `create` (default true) makes the `ComputeRouter`, `name` or `router-<name>`, with `asn` (required to create one), `keepalive` and `custom_advertise` (a `CUSTOM` advertise mode with `ALL_SUBNETS` and the ranges); `create: false` reuses the router `name` names. `route_policies` need `allow_alpha` (below) |
| `route_policies` in `router_config` | one config-connector-extensions `ComputeRouterRoutePolicy` (`compute.gcp.hfl.dev/v1alpha1`) per key, named by it, on the router: `IMPORT` or `EXPORT`, its terms with their match and actions; fabric's checks (priority range, unique priorities, the type) |
| `tunnels` | refused, not ported yet: a tunnel needs a shared secret, and one given here would be in the rendered manifest while fabric's generated one (`random_id`) has no Config Connector equivalent. `ComputeVPNTunnel` takes its secret from a Kubernetes Secret (`sharedSecret.valueFrom`), which the chart does not take yet: the builder's open SECV question, as for net-vpn-static. Fabric makes one router interface and one BGP peer per tunnel, so there are none of those either. Gaps that would remain: `ComputeRouterPeer` has no `md5AuthenticationKey`, `importPolicies` or `exportPolicies` |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the cloud resources |

## Outputs

`id` and `self_link` of the HA VPN gateway, `router_name` (the new
router's, else `router_config.name`) and `route_policies` (each policy's
ID, keyed as fabric keys them). Not outputs: `random_secret` (the chart
makes no secret), `tunnels` (none), and fabric's whole objects
(`bgp_peers`, `external_gateway`, `router`; `docs/design.md`, "Outputs").

## From Terraform

A `module "x" { source = ".../modules/net-ipsec-over-interconnect" ... }`
block's arguments become the values unchanged, but for `tunnels`. To adopt
an existing gateway, keep its names: Config Connector acquires the
resources of those names (`docs/design.md`, "From Terraform").

## Config Connector gaps

Found porting this module, for config-connector-extensions:
`ComputeRouterPeer` (v1.160.0) has no `exportPolicies`/`importPolicies`,
so route policies cannot be attached to a BGP peer, the only reason fabric
makes them, and no `md5AuthenticationKey`. `ComputeVPNGateway`'s
`vpnInterfaces[].interconnectAttachmentRef.external` is documented as an
attachment's `name`, where the API takes the attachment's URL; the chart
passes fabric's value (an ID or self link) unchanged, which a live run
must confirm.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/net-ipsec-over-interconnect`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-ipsec-over-interconnect)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=net-ipsec-over-interconnect`: render cases `basic`
(fabric's README example without its tunnels), `full` (every value the
chart carries), `existing` (an existing peer gateway and router), `names`
and `mock`, validated against Config Connector v1.160.0's CRD schemas and
config-connector-extensions' (`ComputeRouterRoutePolicy`), and the
refusals in `tests/*.fail.yaml`.

FAKE_CLOUD_RESULT

Not applied live: live runs are pending KEYLIVE.

## Changes

- **0.1.0** (2026-11-13): the port: the HA VPN gateway on two VLAN
  attachments, the external peer gateway, the router and its route
  policies.
