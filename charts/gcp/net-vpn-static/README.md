# net-vpn-static

A Classic VPN gateway with its external address and the ESP, UDP 500 and
UDP 4500 forwarding rules that bring IPsec traffic to it, as Config
Connector objects. A port of Cloud Foundation Fabric's
[`modules/net-vpn-static`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/net-vpn-static)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-net-vpn-static` (`package.yaml`). Checked against Config Connector
v1.160.0.

## Example

```yaml
project_id: my-project
region: europe-west1
name: vpn-test
network: projects/my-project/global/networks/my-network
```

renders the `ComputeTargetVPNGateway` `vpn-test`, the `ComputeAddress`
`vpn-vpn-test` and the `ComputeForwardingRule`s `vpn-vpn-test-esp`,
`-udp-500` and `-udp-4500` (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.gateway`, `names.address` | not fabric variables: the gateway's and its address's names in full, used as given (no `namePrefix`) and checked (63 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every name the chart derives starts with `<namePrefix>-`; empty changes nothing |
| `labels`, `tags` | Kubernetes labels on every object; unprefixed ones and `tags` reach the resources that take Google Cloud labels (the address, the forwarding rules) |
| `name`, `project_id`, `region`, `network` | the gateway (`name`), the address (`vpn-<name>`) and forwarding rules (`vpn-<name>-esp`, `-udp-500`, `-udp-4500`), their project and region; the gateway's `networkRef` |
| `gateway_address_create`, `gateway_address` | the `ComputeAddress` the forwarding rules use (true, the default), or the given address (false) |
| `remote_ranges`, `route_priority` | accepted: fabric routes each range through each tunnel, and with no tunnels there are no routes |
| `tunnels` | refused, not ported yet: a tunnel needs a shared secret, and one given here would be in the rendered manifest while fabric's generated one (`random_id`) has no Config Connector equivalent. `ComputeVPNTunnel` takes its secret from a Kubernetes Secret (`sharedSecret.valueFrom`), which the chart does not take yet: the same open question as cloudsql-instance's `root_password`. `ComputeVPNTunnel` also has no `cipherSuite` field (a gap) |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the cloud resources |

## Outputs

`address` (the created address, else `gateway_address`), `id`, `name` and
`self_link` of the gateway. Not outputs: `random_secret` (the chart makes
no secret), `tunnel_names` and `tunnel_self_links` (no tunnels), and
fabric's whole objects (`gateway`, `tunnels`; `docs/design.md`,
"Outputs").

## From Terraform

A `module "x" { source = ".../modules/net-vpn-static" ... }` block's
arguments become the values unchanged, but for `tunnels`
(`examples/net-vpn-static/`). To adopt an existing gateway, keep its names:
Config Connector acquires the resources of those names (`docs/design.md`,
"From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/net-vpn-static`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpn-static)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=net-vpn-static`: render cases `basic`, `address` and
`names`, each validated against Config Connector v1.160.0's CRD schemas,
and the refusals in `tests/*.fail.yaml`.

Fake cloud (`task test-mock MOCK_CHARTS=net-vpn-static`, 2026-11-12): the
gateway, its address and its three forwarding rules on a network from
`tests/mock.needs.yaml`: every object Ready, the outputs evaluated, every
object deleted.

## Changes

- **0.1.0** (2026-11-12): the port.
