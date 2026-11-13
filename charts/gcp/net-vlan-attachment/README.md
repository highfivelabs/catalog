# net-vlan-attachment

A Partner Interconnect VLAN attachment, the Cloud Router it is on
(encrypted, with the IPsec address pool, for IPsec over Interconnect) and
the router's BGP route policies, as Config Connector objects. A port of
Cloud Foundation Fabric's
[`modules/net-vlan-attachment`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/net-vlan-attachment)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-net-vlan-attachment` (`package.yaml`). Checked against Config
Connector v1.160.0 and config-connector-extensions (route policies).
Dedicated Interconnect attachments are refused (below).

## Example

```yaml
project_id: my-project
region: europe-west8
network: projects/my-project/global/networks/my-network
name: vlan-604-x
description: vlan-604-x
peer_asn: "65000"
partner_interconnect_config: {edge_availability_domain: AVAILABILITY_DOMAIN_1}
router_config: {create: true, asn: 16550, name: router-1}
```

renders the `ComputeInterconnectAttachment` `vlan-604-x` (`PARTNER`) on
the `ComputeRouter` `router-1` (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.attachment`, `names.router`, `names.address` | not fabric variables: the attachment's, the router's and the IPsec address pool's names in full, used as given (no `namePrefix`) and checked (63 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every name the chart derives starts with `<namePrefix>-`; empty changes nothing |
| `labels`, `tags` | Kubernetes labels on every object; unprefixed ones and `tags` reach the resources that take Google Cloud labels |
| `allow_alpha` | not a fabric variable: accepts the v1alpha1 kind route policies need (`docs/design.md`, "Alpha kinds") |
| `name`, `description`, `project_id`, `region`, `network` | the attachment's name and description, the resources' project and region; the router's and address pool's `networkRef` |
| `admin_enabled`, `mtu` | the attachment's `adminEnabled` and `mtu` (left unset with IPsec, as fabric does) |
| `partner_interconnect_config` | the attachment's `edgeAvailabilityDomain`; the attachment is always `PARTNER` |
| `vpn_gateways_ip_range` | IPsec over Interconnect: the address pool, an `INTERNAL` `IPSEC_INTERCONNECT` `ComputeAddress` `pool-<name>` of that range; the attachment's `encryption: IPSEC` and `ipsecInternalAddresses`; and an encrypted router, `<name>-underlay` |
| `ipsec_gateway_ip_ranges` | the ranges the encrypted router advertises (fabric's map of description to range) |
| `router_config` | `create` (default true) makes the `ComputeRouter`: without IPsec `name` (fabric's default `router`), with `asn` (default 65001), `keepalive` and `custom_advertise`; with IPsec the encrypted router (`asn` only, as fabric). `create: false` puts the attachment on the router `name` names. `route_policies` need `allow_alpha` (below). `md5_authentication_key` is refused: it configures a dedicated attachment's BGP peer, and `ComputeRouterPeer` has no `md5AuthenticationKey` |
| `route_policies` in `router_config` | one config-connector-extensions `ComputeRouterRoutePolicy` (`compute.gcp.hfl.dev/v1alpha1`) per key, named by it, on the router: `IMPORT` or `EXPORT`, its terms with their match and actions; fabric's checks (priority range, unique priorities, the type) |
| `bgp_peer`, `peer_asn` | accepted; fabric uses them only for a dedicated attachment's BGP peer, so on a partner attachment they change nothing, as in fabric |
| `dedicated_interconnect_config` | refused, a gap: fabric gives a dedicated attachment a router interface and a BGP peer whose addresses are the attachment's assigned `cloudRouterIpAddress` and `customerRouterIpAddress`. Config Connector cannot pass a status field into another object in one render, and `ComputeInterconnectAttachment` has no `candidateCloudRouterIpAddress` or `candidateCustomerRouterIpAddress` to fix them beforehand; `ComputeRouterPeer` also has no `md5AuthenticationKey`, `importPolicies`, `exportPolicies` or `customLearnedIpRanges` |
| `context` | refused, by design: Bundt replaces fabric's `$context` lookups with `${...}` expressions in the component's inputs |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the cloud resources |

## Outputs

`id`, `name` and `pairing_key` of the attachment (the key a partner
provisions it with), `router_name` (the router the attachment is on) and
`route_policies` (each policy's ID, keyed as fabric keys them). Not
outputs: `md5_configuration` (a dedicated peer's secret), and fabric's
whole objects (`attachment`, `router`, `router_interface`;
`docs/design.md`, "Outputs").

## From Terraform

A `module "x" { source = ".../modules/net-vlan-attachment" ... }` block's
arguments become the values unchanged for a partner attachment. To adopt
an existing attachment and router, keep their names: Config Connector
acquires the resources of those names (`docs/design.md`, "From
Terraform").

## Config Connector gaps

Found porting this module, for config-connector-extensions:

- `ComputeInterconnectAttachment` (v1.160.0) has no
  `candidateCloudRouterIpAddress` or `candidateCustomerRouterIpAddress`.
- `ComputeRouterPeer` has no `exportPolicies`/`importPolicies` (so route
  policies cannot be attached to a peer), `md5AuthenticationKey` or
  `customLearnedIpRanges`.
- mockgcp has no interconnect attachments, so this chart has no
  fake-cloud case.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/net-vlan-attachment`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vlan-attachment)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=net-vlan-attachment`: render cases `basic` and `ipsec`
(fabric's README partner examples), `full` (every value the chart
carries), `existing-router` and `names`, validated against Config
Connector v1.160.0's CRD schemas and config-connector-extensions'
(`ComputeRouterRoutePolicy`), and the refusals in `tests/*.fail.yaml`.

Not applied to the fake cloud: mockgcp (at config-connector-extensions'
pin) has no interconnect attachments. Not applied live: live runs are
pending KEYLIVE.

## Changes

- **0.1.0** (2026-11-13): the port: a partner VLAN attachment, its router
  (encrypted, with the IPsec address pool, for IPsec over Interconnect)
  and its route policies.
