# net-vpn-ha

An HA VPN gateway, the external peer gateways it connects to, a Cloud
Router and the router's BGP route policies, as Config Connector objects. A
port of Cloud Foundation Fabric's
[`modules/net-vpn-ha`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/net-vpn-ha)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-net-vpn-ha` (`package.yaml`). Checked against Config Connector
v1.160.0 and config-connector-extensions (route policies).

## Example

```yaml
project_id: my-project
region: europe-west1
network: projects/my-project/global/networks/my-network
name: mynet-to-onprem
peer_gateways:
  default:
    external:
      redundancy_type: SINGLE_IP_INTERNALLY_REDUNDANT
      interfaces: [8.8.8.8]
router_config: {asn: 64514}
```

renders the `ComputeVPNGateway` `mynet-to-onprem`, the
`ComputeExternalVPNGateway` `mynet-to-onprem-default` and the
`ComputeRouter` `vpn-mynet-to-onprem` (`tests/golden/basic.yaml`): the
module README's GCP-to-on-premises example without its tunnels.

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.gateway`, `names.router` | not fabric variables: the gateway's and the router's names in full, used as given (no `namePrefix`) and checked (63 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every name the chart derives starts with `<namePrefix>-`; empty changes nothing |
| `labels`, `tags` | Kubernetes labels on every object; unprefixed ones and `tags` reach the resources that take Google Cloud labels |
| `allow_alpha` | not a fabric variable: accepts the v1alpha1 kind route policies need (`docs/design.md`, "Alpha kinds") |
| `name`, `project_id`, `region`, `network` | the gateway's name (and the prefix of the router's and external gateways' names), their project and region; the gateway's and router's `networkRef` |
| `vpn_gateway_create` | the `ComputeVPNGateway` with its `description` (fabric's default, `Terraform managed external VPN gateway`) and `stackType` (`IPV4_IPV6` with `ipv6`, else `IPV4_ONLY`); `null` makes none |
| `vpn_gateway` | an existing gateway's self link, used when `vpn_gateway_create` is `null`: the `self_link` output |
| `peer_gateways` | each `external` entry is a `ComputeExternalVPNGateway`, `name` or `<name>-<key>`, with its redundancy type, description and interfaces (numbered from 0, as fabric's); a `gcp` entry makes nothing (fabric uses it only in tunnels); exactly one of the two, as fabric checks |
| `router_config` | required, as in fabric. `create` (default true) makes the `ComputeRouter`, `name` or `vpn-<name>`, with `asn` (required to create one), `keepalive` and `custom_advertise` (a `CUSTOM` advertise mode with `ALL_SUBNETS` and the ranges); `create: false` reuses the router `name` names. `route_policies` need `allow_alpha` (below). `override_name` is accepted and, as in fabric, unused |
| `route_policies` in `router_config` | one config-connector-extensions `ComputeRouterRoutePolicy` (`compute.gcp.hfl.dev/v1alpha1`) per key, named by it, on the router: `IMPORT` or `EXPORT`, its terms with their match and actions; fabric's checks (priority range, unique priorities, the type) |
| `context` | refused, by design: Bundt replaces fabric's `$context` lookups with `${...}` expressions in the component's inputs |
| `tunnels` | refused, not ported yet: a tunnel needs a shared secret, and one given here would be in the rendered manifest while fabric's generated one (`random_id`) has no Config Connector equivalent. `ComputeVPNTunnel` takes its secret from a Kubernetes Secret (`sharedSecret.valueFrom`), which the chart does not take yet: the builder's open SECV question, as for net-vpn-static. Fabric makes one router interface and one BGP peer per tunnel, so there are none of those either. Gaps that would remain: `ComputeVPNTunnel` has no `cipherSuite`, and `ComputeRouterPeer` has no `md5AuthenticationKey`, `importPolicies`, `exportPolicies`, `customLearnedIpRanges` or `customLearnedRoutePriority`, so a peer could not use the route policies this chart makes |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the cloud resources |

## Outputs

`id` (`projects/<project>/regions/<region>/vpnGateways/<name>`, as fabric
builds it), `name` (the new gateway's, else null), `self_link` (the new
gateway's, else `vpn_gateway`), `router_name` (the new router's, else
`router_config.name`) and `route_policies` (each policy's ID, keyed as
fabric keys them). Not outputs: `md5_keys`, `random_secret`,
`shared_secrets`, `tunnel_names` and `tunnel_self_links` (no tunnels, no
secrets), and fabric's whole objects (`bgp_peers`, `external_gateway`,
`gateway`, `router`, `tunnels`; `docs/design.md`, "Outputs").

## From Terraform

A `module "x" { source = ".../modules/net-vpn-ha" ... }` block's arguments
become the values unchanged, but for `tunnels` and `context`. To adopt an
existing gateway and router, keep their names: Config Connector acquires
the resources of those names (`docs/design.md`, "From Terraform").

## Config Connector gaps

Found porting this module, for config-connector-extensions:

- `ComputeRouterPeer` (v1.160.0) has no `exportPolicies`/`importPolicies`,
  so route policies cannot be attached to a BGP peer, the only reason
  fabric makes them; no `md5AuthenticationKey`, `customLearnedIpRanges`,
  `customLearnedRoutePriority` or `zeroCustomLearnedRoutePriority`.
- `ComputeVPNTunnel` has no `cipherSuite`.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/net-vpn-ha`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpn-ha)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=net-vpn-ha`: render cases `basic` and `gcp-to-gcp`
(fabric's README examples without tunnels), `full` (every value the chart
carries), `existing` (an existing gateway and router), `names` and `mock`,
validated against Config Connector v1.160.0's CRD schemas and
config-connector-extensions' (`ComputeRouterRoutePolicy`), and the
refusals in `tests/*.fail.yaml`.

FAKE_CLOUD_RESULT

Not applied live: live runs are pending KEYLIVE.

## Changes

- **0.1.0** (2026-11-13): the port: the HA VPN gateway, external peer
  gateways, the router and its route policies.
