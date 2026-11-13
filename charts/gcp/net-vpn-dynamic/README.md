# net-vpn-dynamic

A Classic VPN gateway with its external address and the ESP, UDP 500 and
UDP 4500 forwarding rules that bring IPsec traffic to it, a Cloud Router
for its BGP sessions and the router's BGP route policies, as Config
Connector objects. A port of Cloud Foundation Fabric's
[`modules/net-vpn-dynamic`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/net-vpn-dynamic)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-net-vpn-dynamic` (`package.yaml`). Checked against Config Connector
v1.160.0 and config-connector-extensions (route policies).

## Example

```yaml
project_id: my-project
region: europe-west1
network: projects/my-project/global/networks/my-network
name: gateway-1
router_config: {asn: 64514}
```

renders the `ComputeTargetVPNGateway` `gateway-1`, the `ComputeAddress`
`vpn-gateway-1`, the `ComputeForwardingRule`s `vpn-gateway-1-esp`,
`-udp-500` and `-udp-4500` and the `ComputeRouter` `vpn-gateway-1`
(`tests/golden/basic.yaml`): the module README's example without its
tunnel.

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.gateway`, `names.address`, `names.router` | not fabric variables: the gateway's, its address's and the router's names in full, used as given (no `namePrefix`) and checked (63 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every name the chart derives starts with `<namePrefix>-`; empty changes nothing |
| `labels`, `tags` | Kubernetes labels on every object; unprefixed ones and `tags` reach the resources that take Google Cloud labels (the address, the forwarding rules) |
| `allow_alpha` | not a fabric variable: accepts the v1alpha1 kind route policies need (`docs/design.md`, "Alpha kinds") |
| `name`, `project_id`, `region`, `network` | the gateway (`name`), the address (`vpn-<name>`) and forwarding rules (`vpn-<name>-esp`, `-udp-500`, `-udp-4500`), their project and region; the gateway's and router's `networkRef` |
| `gateway_address_create`, `gateway_address` | the `ComputeAddress` the forwarding rules use (true, the default), or the given address (false) |
| `router_config` | required, as in fabric. `create` (default true) makes the `ComputeRouter`, `name` or `vpn-<name>`, with `asn` (required, as in fabric), `keepalive` and `custom_advertise` (a `CUSTOM` advertise mode with `ALL_SUBNETS` and the ranges); `create: false` reuses the router `name` names. `route_policies` need `allow_alpha` (below) |
| `route_policies` in `router_config` | one config-connector-extensions `ComputeRouterRoutePolicy` (`compute.gcp.hfl.dev/v1alpha1`) per key, named by it, on the router: `IMPORT` or `EXPORT`, its terms with their match and actions; fabric's checks (priority range, unique priorities, the type) |
| `tunnels` | refused, not ported yet: a tunnel needs a shared secret, and one given here would be in the rendered manifest while fabric's generated one (`random_id`) has no Config Connector equivalent. `ComputeVPNTunnel` takes its secret from a Kubernetes Secret (`sharedSecret.valueFrom`), which the chart does not take yet: the builder's open SECV question, as for net-vpn-static. Fabric makes one router interface and one BGP peer per tunnel, so there are none of those either. Gaps that would remain: `ComputeVPNTunnel` has no `cipherSuite`, and `ComputeRouterPeer` has no `importPolicies` or `exportPolicies` |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the cloud resources |

## Outputs

`address` (the created address, else `gateway_address`), `id`, `name` and
`self_link` of the gateway, `router_name` (the new router's, else
`router_config.name`) and `route_policies` (each policy's ID, keyed as
fabric keys them). Not outputs: `random_secret` (the chart makes no
secret), `tunnel_names` and `tunnel_self_links` (no tunnels), and fabric's
whole objects (`gateway`, `router`, `tunnels`; `docs/design.md`,
"Outputs").

## From Terraform

A `module "x" { source = ".../modules/net-vpn-dynamic" ... }` block's
arguments become the values unchanged, but for `tunnels`. To adopt an
existing gateway, keep its names: Config Connector acquires the resources
of those names (`docs/design.md`, "From Terraform").

## Config Connector gaps

Found porting this module, for config-connector-extensions:
`ComputeRouterPeer` (v1.160.0) has no `exportPolicies`/`importPolicies`,
so route policies cannot be attached to a BGP peer, the only reason fabric
makes them; `ComputeVPNTunnel` has no `cipherSuite`.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/net-vpn-dynamic`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpn-dynamic)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=net-vpn-dynamic`: render cases `basic` (fabric's README
example without its tunnel), `full` (every value the chart carries),
`existing-router`, `names` and `mock`, validated against Config Connector
v1.160.0's CRD schemas and config-connector-extensions'
(`ComputeRouterRoutePolicy`), and the refusals in `tests/*.fail.yaml`.

Applied to the fake cloud on 2026-11-13 on an offload VM (`task test-mock
MOCK_CHARTS=net-vpn-dynamic`, run `off-catalog-1113152746-28240`, at
config-connector-extensions `d54a2075`, whose fake cloud runs its
`ComputeRouterRoutePolicy` controller): the gateway, its address, its three forwarding rules, the router and an export route policy (`allow_alpha`) on a network from `tests/mock.needs.yaml`: all 7 objects Ready, the outputs evaluated, all deleted.

Not applied live: live runs are pending KEYLIVE.

## Changes

- **0.1.0** (2026-11-13): the port: the gateway, its address and
  forwarding rules, the router and its route policies.
