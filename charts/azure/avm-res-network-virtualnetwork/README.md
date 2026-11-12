# avm-res-network-virtualnetwork

An Azure virtual network with its subnets and peerings, and its lock, role
assignments and diagnostic settings, as Azure Service Operator (ASO)
objects. A port of the Azure Verified Module
[`avm-res-network-virtualnetwork`](https://github.com/Azure/terraform-azurerm-avm-res-network-virtualnetwork/tree/874b2d1ce38cd59ca0759d416cb3e174c2543ffb)
at v0.23.0 (`874b2d1c`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-network-virtualnetwork`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

## Example

```yaml
name: vnet-example
location: eastus2
parent_id: /subscriptions/<id>/resourceGroups/rg-example
address_space: [10.0.0.0/16]
subnets:
  subnet1:
    name: subnet1
    address_prefixes: [10.0.0.0/24]
```

renders the ASO `VirtualNetwork` `vnet-example` in the group and its
`VirtualNetworksSubnet` `subnet1` (`tests/golden/basic.yaml`). The group
can come from the `avm-res-resources-resourcegroup` chart's `resource_id`
output.

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.vnet` (`Microsoft.Network/virtualNetworks`) | always | `VirtualNetwork` (`network.azure.com/v20250301`), `virtual_network`, owned by `parent_id` |
| `module.subnet` (`.../subnets`) | one per `subnets` entry | `VirtualNetworksSubnet`, `subnet:<key>`, owned by the network |
| `module.subnet`'s `role_assignments` | one per entry's assignment | `RoleAssignment`, `subnet:<key>/role-assignment-<k>`, owned by the subnet |
| `module.peering` (`.../virtualNetworkPeerings`: full, address space or subnet peering) | one per `peerings` entry | `VirtualNetworksVirtualNetworkPeering`, `peering:<key>`, owned by the network |
| `module.peering`'s reverse peering | `create_reverse_peering` | `VirtualNetworksVirtualNetworkPeering`, `reverse-peering:<key>`, owned by the remote network (by ARM ID), its remote network this chart's by reference |
| `azapi_resource.lock` | `lock` set | `ManagementLock` (aso-extensions), `lock` |
| `azapi_resource.role_assignments` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `azapi_resource.diagnostic_settings` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` |
| telemetry | never | not ported |

ASO is at ARM API version 2025-03-01 for networks, subnets and peerings,
newer than the module's 2024-07-01, so every property the module sends
exists.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`).

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` |
| `parent_id` (required) | `owner.armId` |
| `address_space` | `addressSpace.addressPrefixes` (sorted, as Terraform's set) |
| `ipam_pools` | `addressSpace.ipamPoolPrefixAllocations`: `reference.armId` and `numberOfIpAddresses`, given or computed from `prefix_length` as the module computes it |
| `bgp_community` | `bgpCommunities.virtualNetworkCommunity` |
| `dns_servers` | `dhcpOptions.dnsServers` |
| `ddos_protection_plan` | `ddosProtectionPlan.reference.armId` and `enableDdosProtection` (`false` when unset, as the module sends it) |
| `enable_vm_protection`, `encryption`, `extended_location`, `flow_timeout_in_minutes` | `enableVmProtection`, `encryption`, `extendedLocation`, `flowTimeoutInMinutes` |
| `tags` | `spec.tags` of the network |
| `subnets` | one subnet each: `name` is `azureName`; `address_prefix`, `address_prefixes`, `ipam_pools` (`ipamPoolPrefixAllocations`), `delegations` (`name`, `serviceName`), `default_outbound_access_enabled` (`defaultOutboundAccess`), `nat_gateway`, `network_security_group`, `route_table` (`reference.armId`), `private_link_service_network_policies_enabled` (`Enabled` or `Disabled`), `private_endpoint_network_policies` when `private_endpoint_network_policies_enabled`, `service_endpoints` (sorted), `service_endpoint_policies`, `sharing_scope`, `role_assignments`. `allocation_type` is accepted and, as in the module, not sent. `ignore_body_changes`, `retry`, `timeouts` are refused |
| `peerings` | one peering each, shaped as the module shapes it (`peer_complete_vnets`; address spaces; subnet names), with the seven traffic settings always sent; `create_reverse_peering` adds the reverse with the `reverse_*` settings. `sync_remote_address_space_enabled`, `sync_remote_address_space_triggers`, `retry`, `timeouts` are refused |
| `lock`, `role_assignments`, `diagnostic_settings` | the AVM interfaces (`docs/azure.md`, "8. Charts"); a diagnostic setting without a name is `diag-<name>`, as the module names it |
| `enable_telemetry` | accepted; the chart sends no telemetry |
| `ignore_body_changes`, `retry`, `timeouts` | refused (below) |

The module's validations stop the render with the module's messages:
`address_space` or `ipam_pools` but not both, the IPAM pools' sizes and
counts, a subnet's address (one of `ipam_pools`, `address_prefix`,
`address_prefixes`), `service_endpoints_with_location`, CIDR blocks,
`parent_id`, encryption enforcement, the extended location type and the
diagnostic settings' destination. A peering whose settings make none of
the module's three shapes (and so no resource in Terraform) is refused
with a message saying what to give.

### Not module inputs

| Value | Renders |
| --- | --- |
| `names.virtualNetwork` | the network's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name`, never of a name under `names`, a subnet's or a peering's; checked against the 64-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

Subnets and peerings take their entries' names as given, with no
`namePrefix`: they are named inside the network, and Azure fixes some
subnet names (`GatewaySubnet`, `AzureFirewallSubnet`,
`AzureBastionSubnet`).

### Refused when set

| Variable | Why |
| --- | --- |
| `ignore_body_changes` (any non-empty list), a subnet's `ignore_body_changes` | ASO applies every property it is given; it cannot leave a path to another writer |
| `retry`, `timeouts`, and a subnet's or peering's | ASO retries every failed request itself; Bundt sets a component's time limit |
| a peering's `sync_remote_address_space_enabled`, `sync_remote_address_space_triggers` | the sync is a PUT with `?syncRemoteAddressSpace=true`, which ASO cannot send |

## Outputs

| Output | From |
| --- | --- |
| `name` | computed from the inputs, as the module sets it |
| `resource_id` | the network's `status.id` |
| `address_spaces` | `address_space`, or with IPAM the network's `status.addressSpace.addressPrefixes` |
| `subnets` | `{<key>: <subnet ARM ID>}`: the module's map of subnet submodule objects, reduced to the field consumers take |
| `peerings` | `{<key>: <peering ARM ID>}`, likewise |

Not an output: `resource`, the module's whole azapi object.

## From Terraform

A module block's arguments are the values, unchanged. ASO adopts a
network, subnet or peering that exists when an object with its name is
applied, so keep the names and leave `namePrefix` empty; set
`deletion_policy: ABANDON` for the first apply, `terraform state rm` the
module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-network-virtualnetwork`](https://github.com/Azure/terraform-azurerm-avm-res-network-virtualnetwork/tree/v0.23.0)
at v0.23.0 (`874b2d1c`, MIT), its `subnet` and `peering` submodules
included. [`upstream.yaml`](upstream.yaml) records the repository, release,
commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-network-virtualnetwork`: render cases `basic`,
`full`, `ipam`, `names` and `mock`, each validated against ASO v2.22.0's
CRD schemas and aso-extensions' `ManagementLock` CRD, and the refusals in
`tests/*.fail.yaml`. Not yet applied to the fake cloud or to Azure
(`docs/azure.md`, "8. Charts").

## Changes

- **0.1.0** (2026-11-12): the port.
