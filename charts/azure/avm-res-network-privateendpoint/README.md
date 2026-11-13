# avm-res-network-privateendpoint

An Azure private endpoint with its private DNS zone group, lock and role
assignments, as Azure Service Operator (ASO) objects. A port of the Azure
Verified Module
[`avm-res-network-privateendpoint`](https://github.com/Azure/terraform-azurerm-avm-res-network-privateendpoint/tree/84e427dd16ca927f449b7659d8888f3685f38a7d)
at v0.3.1 (`84e427dd`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-network-privateendpoint`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

## Example

```yaml
name: pe-example
location: eastus2
parent_id: /subscriptions/<id>/resourceGroups/rg-example
network_interface_name: null
private_connection_resource_id: /subscriptions/<id>/resourceGroups/rg-example/providers/Microsoft.Storage/storageAccounts/stexample
subnet_resource_id: /subscriptions/<id>/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-pe
subresource_names: [blob]
```

renders a `PrivateEndpoint` `pe-example` to the storage account's blob
service, its connection named `pse-pe-example` (`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.this` (`Microsoft.Network/privateEndpoints@2025-07-01`) | always | `PrivateEndpoint` (`network.azure.com/v20250301`), `private_endpoint`, owned by `parent_id` |
| `module.private_dns_zone_group` (`privateEndpoints/privateDnsZoneGroups`) | `private_dns_zone_resource_ids` not empty | `PrivateEndpointsPrivateDnsZoneGroup` (`v20250301`), `private_dns_zone_group`, owned by the endpoint |
| `azapi_resource.lock` | `lock` set | `ManagementLock` (aso-extensions), `lock` |
| `azapi_resource.role_assignments` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `terraform_data.network_interface_id`, `data.azapi_resource.network_interface` | never | not needed: the endpoint's status lists its network interface and addresses |
| `data.azapi_resource_list.role_definitions` | never | not needed: ASO resolves a role by name (`wellKnownName`) |
| `time_sleep.wait_for_resource_destroy`, telemetry | never | not ported (ASO waits on its own) |

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`), and the module's validations stop
the render with its messages.

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` |
| `parent_id` (required) | `owner.armId`, a resource group's ID |
| `private_connection_resource_id` (required) | `privateLinkServiceConnections[0].privateLinkServiceReference.armId` |
| `subresource_names` | `privateLinkServiceConnections[0].groupIds` |
| `private_service_connection_name` | `privateLinkServiceConnections[0].name` (default `pse-<name>`) |
| `subnet_resource_id` (required) | `subnet.reference.armId` |
| `network_interface_name` (required, may be null) | `customNetworkInterfaceName` (Azure names the interface when null) |
| `ip_configurations` | `ipConfigurations`, in key order: `name`, `groupId` (`subresource_name`), `memberName` (default `default`), `privateIPAddress` |
| `application_security_group_association_ids` | `applicationSecurityGroups`, sorted |
| `private_dns_zone_resource_ids` | the zone group's `privateDnsZoneConfigs`, each named by the zone's last segment, as the submodule names them |
| `private_dns_zone_group_name` | the zone group's `azureName` (default `default`) |
| `tags` | `spec.tags` of the endpoint |
| `lock` | the AVM lock interface, with the module's notes |
| `role_assignments` | the AVM interface; `skip_service_principal_aad_check` without a `principal_type` sets `ServicePrincipal`, as the module does |
| `avm_managed_migration_enabled` | accepted, no effect: the module imports an existing zone group during an upgrade; ASO adopts one of the same name on its own |
| `enable_telemetry` | accepted; the chart sends no telemetry |
| `ignore_body_changes` | refused when a list is set (gap): ASO applies every property it is given |
| `resource_types` | refused when set (by design): ASO's kinds fix the API versions (2025-03-01) |
| `retry`, `timeouts` | refused when set (by design): ASO retries on its own; Bundt sets a component's time limit |

The module's precondition that a role name resolves is ASO's to check (it
resolves `wellKnownName` when it applies the assignment).

### Not module inputs

| Value | Renders |
| --- | --- |
| `names.privateEndpoint`, `names.networkInterface` | the endpoint's and its network interface's names in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name` and of `network_interface_name`, never of a name under `names`; checked against the 80-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

## Outputs

| Output | From |
| --- | --- |
| `name` | the endpoint's `azureName` |
| `resource_id` | the endpoint's `status.id` |
| `network_interface_ids` | the endpoint's `status.networkInterfaces[].id` (Azure makes one) |
| `application_security_group_association_ids` | the endpoint's `status.applicationSecurityGroups[].id` |
| `private_ip_addresses` | the addresses of the endpoint's `status.customDnsConfigs`. The module reads them from the network interface instead, which the chart does not render; they are the same addresses |

## From Terraform

A module block's arguments are the values. ASO adopts an endpoint and a
zone group that exist when an object with their names is applied, so keep
the names and leave `namePrefix` empty; set `deletion_policy: ABANDON` for
the first apply, `terraform state rm` the module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-network-privateendpoint`](https://github.com/Azure/terraform-azurerm-avm-res-network-privateendpoint/tree/v0.3.1)
at v0.3.1 (`84e427dd`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-network-privateendpoint`: render cases `basic`,
`full`, `names` and `mock`, each validated against ASO v2.22.0's CRD
schemas and aso-extensions' `ManagementLock` CRD, and the refusals in
`tests/*.fail.yaml` (the module's validations and the refused variables).
`task test-live-azure` (case `pe`) applies an endpoint to a storage
account's blob service, with a DNS zone group, in a subnet of a network the
case applies with it, to the Azure sandbox with Azure Service Operator,
evaluates the outputs, deletes it and checks Azure no longer has it:
passed on 2026-11-13 (run `cat11130308507d`, the private address read from
the endpoint's DNS configurations with the zone group in place).
`task test-mock-azure` applies `tests/mock.values.yaml` to aso-extensions'
fake cloud: passed on 2026-11-13, both objects Ready and deleted, the
outputs evaluated.

## Changes

- **0.1.0** (2026-11-13): the port.
