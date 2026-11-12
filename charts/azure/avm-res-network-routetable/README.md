# avm-res-network-routetable

An Azure route table with its routes, and its lock and role assignments,
as Azure Service Operator (ASO) objects. A port of the Azure Verified
Module
[`avm-res-network-routetable`](https://github.com/Azure/terraform-azurerm-avm-res-network-routetable/tree/7482f30b5f92ef88d5abfeb62a4296aa4a474342)
at v0.6.0 (`7482f30b`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-network-routetable`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

## Example

```yaml
name: rt-example
location: eastus2
resource_group_name: rg-example
subscription_id: <id>
routes:
  route1:
    name: test-route-vnetlocal
    address_prefix: 10.2.0.0/32
    next_hop_type: VnetLocal
```

renders the ASO `RouteTable` `rt-example` in the group and its
`RouteTablesRoute` `test-route-vnetlocal` (`tests/golden/basic.yaml`). A
subnet takes the table by its `resource_id` output
(`avm-res-network-virtualnetwork`'s `subnets.<key>.route_table.id`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azurerm_route_table.this` | always | `RouteTable` (`network.azure.com/v20250301`), `route_table`, owned by the resource group |
| `module.routes` (`azapi_resource.route`, `Microsoft.Network/routeTables/routes`), or `azurerm_route.this` in legacy mode | one per `routes` entry | `RouteTablesRoute`, `route:<key>`, owned by the table |
| `azurerm_management_lock.this` | `lock` set | `ManagementLock` (aso-extensions), `lock` |
| `azurerm_role_assignment.this` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `azurerm_subnet_route_table_association.this` | `subnet_resource_ids` | refused (below) |
| telemetry | never | not ported |

ASO is at ARM API version 2025-03-01 for tables and routes, newer than the
route submodule's 2022-09-01.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`).

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` |
| `resource_group_name` (required) | `owner.armId`: `/subscriptions/<subscription_id>/resourceGroups/<resource_group_name>`, or `resource_group_name` itself when it is a resource group's ID |
| `bgp_route_propagation_enabled` | `disableBgpRoutePropagation` (its negation) |
| `tags` | `spec.tags` of the table |
| `routes` | one route each: `name` is `azureName`; `address_prefix`, `next_hop_type`, `next_hop_in_ip_address` (`nextHopIpAddress`) |
| `routes_legacy_mode` | accepted: azurerm's route and the submodule's are the same Azure route; it changes only the `routes` output's keys |
| `lock` | the AVM lock interface, with the module's notes for the kind |
| `role_assignments` | the AVM interface; `skip_service_principal_aad_check` without a `principal_type` sends `ServicePrincipal`, as azurerm does. The module's azurerm resource drops `description` and `principal_type`; ASO sends them |
| `enable_telemetry` | accepted; the chart sends no telemetry |
| `subnet_resource_ids` | refused (below) |

The module's validations stop the render with the module's messages:
unique route names, the next hop types, and a next hop address only for a
`VirtualAppliance`.

### Not module inputs

| Value | Renders |
| --- | --- |
| `subscription_id` | the subscription of `resource_group_name` when that is a name: the module's azurerm provider knows its subscription, ASO's owner is a resource ID |
| `names.routeTable` | the table's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name`, never of a name under `names` or a route's; checked against the 80-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

### Refused when set

| Variable | Why |
| --- | --- |
| `subnet_resource_ids` | an association is the `routeTable` property of an existing subnet, and ASO sets a subnet's properties only by owning the whole subnet (`VirtualNetworksSubnet`), which would overwrite the rest. Give the subnet's `route_table` in `avm-res-network-virtualnetwork` |

## Outputs

| Output | From |
| --- | --- |
| `name` | computed from the inputs, as the module sets it |
| `resource_id` | the table's `status.id` |
| `routes` | the route submodule's outputs per entry, `{name, resource_id}`, keyed like `routes`; in legacy mode keyed by the routes' names, each with `id` too |

Not an output: `resource`, the module's whole azurerm object.

## From Terraform

A module block's arguments are the values, plus `subscription_id` when
`resource_group_name` is a name. ASO adopts a table or route that exists
when an object with its name is applied, so keep the names and leave
`namePrefix` empty; set `deletion_policy: ABANDON` for the first apply,
`terraform state rm` the module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-network-routetable`](https://github.com/Azure/terraform-azurerm-avm-res-network-routetable/tree/v0.6.0)
at v0.6.0 (`7482f30b`, MIT), its `route` submodule included.
[`upstream.yaml`](upstream.yaml) records the repository, release, commit,
licence and the date last synced.

## Tests

`task test CHART=avm-res-network-routetable`: render cases `basic`,
`full`, `names` and `mock`, each validated against ASO v2.22.0's CRD
schemas and aso-extensions' `ManagementLock` CRD, and the refusals in
`tests/*.fail.yaml`. Not yet applied live or to the fake cloud
(`docs/azure.md`, "8. Charts").

## Changes

- **0.1.0** (2026-11-12): the port.
