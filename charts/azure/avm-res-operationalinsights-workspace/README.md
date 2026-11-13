# avm-res-operationalinsights-workspace

An Azure Log Analytics workspace with its data exports, linked service
and storage, tables, Monitor Private Link Scopes, network security
perimeter association, private endpoints, lock, role assignments and
diagnostic settings, as
Azure Service Operator (ASO) and aso-extensions objects. A port of
the Azure Verified Module
[`avm-res-operationalinsights-workspace`](https://github.com/Azure/terraform-azurerm-avm-res-operationalinsights-workspace/tree/b4ffa3ff87ac09ff6de3b7014c44b4d213aa302b)
at v0.5.1 (`b4ffa3ff`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-operationalinsights-workspace`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

## Example

```yaml
name: law-example
location: eastus2
resource_group_name: rg-example
subscription_id: <id>
```

renders the ASO `Workspace` `law-example`: PerGB2018, public ingestion
and query disabled as the module defaults them (`tests/golden/basic.yaml`).
Its `resource_id` output is what other charts' `diagnostic_settings` take
as `workspace_resource_id`.

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azurerm_log_analytics_workspace.this`, `azapi_update_resource.this` (the `SecuredByPerimeter` access modes) | always | `Workspace` (`operationalinsights.azure.com/v20250701`), `workspace`, owned by the resource group |
| `azurerm_management_lock.this` | `lock` set | `ManagementLock` (aso-extensions), `lock` |
| `azurerm_role_assignment.this` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `azurerm_monitor_diagnostic_setting.this` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` |
| `azapi_resource.data_export` | one per `log_analytics_workspace_data_exports` entry | `WorkspacesDataExport` (aso-extensions, `operationalinsights.azure.hfl.dev/v20250701`), `data_export:<key>` |
| `azurerm_log_analytics_linked_service.this` | `log_analytics_workspace_dedicated_cluster_resource_id` set | `WorkspacesLinkedService` (aso-extensions) `Cluster`, `linked_service` |
| `azurerm_log_analytics_linked_storage_account.this` | one per `log_analytics_workspace_linked_storage_accounts` entry | `WorkspacesLinkedStorageAccount` (aso-extensions), named for its data source type, `linked_storage_account:<key>` |
| `azapi_resource.tables` | one per `log_analytics_workspace_tables` entry | `WorkspacesTable` (aso-extensions), `table:<key>` |
| `azapi_update_resource.tables` | one per `log_analytics_workspace_tables_update` entry | `WorkspacesTable`, `table_update:<key>`, with `detach-on-delete`: deleting it leaves the table, as removing an update resource does |
| `azapi_resource.amplscope`, `azapi_update_resource.amplscope_update`, `azurerm_monitor_private_link_scoped_service.this`, `azurerm_management_lock.amplscope` | one per `monitor_private_link_scope` entry | `PrivateLinkScope` (aso-extensions, `insights.azure.hfl.dev/v20210901`), `monitor_private_link_scope:<key>`, its exclusions in its spec; a `PrivateLinkScopesScopedResource` linking the workspace, `monitor_private_link_scope:<key>:scoped_service`; its `ManagementLock`, `monitor_private_link_scope:<key>:lock` |
| `azapi_resource.ampls` | one per `monitor_private_link_scoped_resource` entry | `PrivateLinkScopesScopedResource` in the existing scope, `monitor_private_link_scoped_resource:<key>` |
| `azapi_resource.nsp_association` | `network_security_perimeter_association` set | `NetworkSecurityPerimetersResourceAssociation` (aso-extensions, `network.azure.hfl.dev/v20250501`) `nsp-assoc-<name>`, `network_security_perimeter_association` |
| `azurerm_private_endpoint.this` (or `this_unmanaged`) | one per `private_endpoints` entry | `PrivateEndpoint` (`network.azure.com/v20250301`), `private_endpoint:<key>`: `pep-<name>` unless named, owned by the workspace's resource group or the entry's `resource_group_name`, connected (`azuremonitor`) to its Monitor Private Link Scope by ARM ID |
| its `private_dns_zone_group` block | an entry with `private_dns_zone_resource_ids`, unless its extension's `manage_dns_zone_group` is false | `PrivateEndpointsPrivateDnsZoneGroup`, `private_endpoint:<key>/dns_zone_group`, one zone configuration per zone, named for it |
| `azurerm_private_endpoint_application_security_group_association.this` | per association | the endpoint's `applicationSecurityGroups` |
| the exclusions `azapi_update_resource.amplscope_update` adds for endpoints on a scope the chart makes | an endpoint on such a scope, unless its extension sets `exclude: false` | not sent when they equal the scope's access modes (they change nothing); refused otherwise (below) |
| an existing scope's exclusions (`azapi_update_resource.amplscope_update_existing`) | when set | refused (below) |
| telemetry | never | not ported |

ASO's Workspace is at ARM API version 2025-07-01, newer than the module's
azurerm resource and its 2023-09-01 update, so `SecuredByPerimeter` is
set on the workspace itself.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`).

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` |
| `resource_group_name` (required) | `owner.armId`: `/subscriptions/<subscription_id>/resourceGroups/<resource_group_name>`, or `resource_group_name` itself when it is a resource group's ID |
| `log_analytics_workspace_sku` | `sku.name` (`PerGB2018` when unset, azurerm's default) |
| `log_analytics_workspace_reservation_capacity_in_gb_per_day` | `sku.capacityReservationLevel` |
| `log_analytics_workspace_retention_in_days` | `retentionInDays` |
| `log_analytics_workspace_daily_quota_gb` | `workspaceCapping.dailyQuotaGb` |
| `log_analytics_workspace_internet_ingestion_enabled`, `..._internet_query_enabled` | `publicNetworkAccessForIngestion`, `publicNetworkAccessForQuery`: `"true"` Enabled, `"false"` Disabled, `SecuredByPerimeter` |
| `log_analytics_workspace_local_authentication_enabled` | `features.disableLocalAuth` (its negation) |
| `log_analytics_workspace_allow_resource_only_permissions` | `features.enableLogAccessUsingOnlyResourcePermissions` |
| `log_analytics_workspace_cmk_for_query_forced` | `forceCmkForQuery` |
| `log_analytics_workspace_identity` | `identity` (`type`, `userAssignedIdentities` by `armId`) |
| `tags` | `spec.tags` |
| `lock` | the AVM lock interface, with the module's notes for the kind |
| `role_assignments` | the AVM interface; `skip_service_principal_aad_check` without a `principal_type` sends `ServicePrincipal`, as azurerm does |
| `diagnostic_settings` | the AVM interface; a setting naming no destination goes to this workspace (`workspaceReference` to its object), as the module sends it; `Dedicated` is left to Azure; a setting without a name is `diag-<name>` |
| `log_analytics_workspace_data_exports` | `name` (`azureName`, the module's pattern checked), `table_names`, `enabled` (`enable`), `destination_resource_id`: an event hub's ID becomes its namespace's with the hub as `eventHubName`, unless `event_hub_name` is given, as the module does |
| `log_analytics_workspace_dedicated_cluster_resource_id` | the linked service `Cluster`'s `writeAccessResourceReference`, as azurerm sends it |
| `log_analytics_workspace_linked_storage_accounts` | `data_source_type` (the linked storage account's name), `storage_account_ids` (`storageAccountReferences`) |
| `log_analytics_workspace_tables`, `log_analytics_workspace_tables_update` | `name`, `retention_in_days`, `total_retention_in_days`, `plan`, `schema` (`name`, `description`, `columns`; a column's type in Azure's spelling, `datetime` as `dateTime`); `resource_id` puts the table in another workspace (its `owner.armId`) |
| `monitor_private_link_scope` | `name` (default `law_pl_scope`, with the namePrefix), `resource_id` (the scope's resource group), `ingestion_access_mode`, `query_access_mode`, `exclusions` (the scope's `accessModeSettings`), `lock` (named `<scope>-lock` unless named); location `global` |
| `monitor_private_link_scoped_service_name` | the workspace's scoped resource's name in each created scope; required with `monitor_private_link_scope`, as azurerm requires it |
| `monitor_private_link_scoped_resource` | `resource_id` (the existing scope, `owner.armId`), `name` (default the workspace's) |
| `private_endpoints` | per entry: `subnet.reference.armId`, `customNetworkInterfaceName`, one `privateLinkServiceConnections` entry (`pse-<name>` unless named, `groupIds: [azuremonitor]`, the scope by `armId`: a chart scope's computed ID, or an existing scope's `resource_id`), `ipConfigurations` (group and member `privatelink`, as the module sets them), `applicationSecurityGroups`, `location`, `tags`; the zone group above. An entry's `role_assignments` and `lock` are accepted and ignored, as the module ignores them |
| `private_endpoint_extensions` | per endpoint: `monitor_private_link_scope_key` (the scope, a key of `monitor_private_link_scope` or `monitor_private_link_scoped_resource`; else the endpoint's own key, else the only scope, as the module picks; none stops the render), `manage_dns_zone_group`, `monitor_private_link_scope_exclusion` (see the refusal) |
| `network_security_perimeter_association` | `resource_id` (the perimeter, `owner.armId`), `profile_name` (`profile.reference.armId`), `access_mode` |
| `customer_managed_key` | accepted: the module declares it and uses it nowhere, nor does the chart |
| `enable_telemetry` | accepted; the chart sends no telemetry |

### Not module inputs

| Value | Renders |
| --- | --- |
| `subscription_id` | the subscription of `resource_group_name` when that is a name: the module's azurerm provider knows its subscription, ASO's owner is a resource ID |
| `names.workspace` | the workspace's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name`, never of a name under `names`; checked against the 63-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

### Refused when set

| Variable | Why |
| --- | --- |
| `monitor_private_link_scoped_resource.<key>.exclusions` | they update an existing scope's access mode settings, which the module reads first; the chart does not own that scope (not ported) |
| `private_endpoint_extensions.<key>.monitor_private_link_scope_exclusion`, when it changes the access modes of the chart's scope for the endpoint (the default exclusion, `PrivateOnly` for both, on a scope with an `Open` mode) | the module names the exclusion by the scope's private endpoint connection, which Azure names and reads back; a render cannot. Set `exclude: false`, or the scope's own access modes (not ported) |
| `log_analytics_workspace_timeouts` | ASO has no per-request timeouts; Bundt sets a component's time limit |

The children that point at the workspace from elsewhere (a scoped
resource, the perimeter association) name it by the ARM ID it will have,
computed from the group's ID and its name: ASO cannot reference another
operator's object by name. They retry until the workspace exists.

## Outputs

| Output | From |
| --- | --- |
| `resource_id` | the workspace's `status.id` |
| `customer_id` | not a module output: the workspace ID agents and queries take (`status.customerId`), the field consumers read from the module's `resource` |
| `private_endpoints` | `{<key>: {id, name, location, subnet_id}}`, from each endpoint (the module gives the whole azurerm object) |

Not output: `resource` (the module's whole azurerm object, sensitive for
its shared keys).

## From Terraform

A module block's arguments are the values, plus `subscription_id` when
`resource_group_name` is a name. ASO adopts a workspace that exists when
an object with its name is applied (its data is kept), so keep the name
and leave `namePrefix` empty; set `deletion_policy: ABANDON` for the first
apply, `terraform state rm` the module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-operationalinsights-workspace`](https://github.com/Azure/terraform-azurerm-avm-res-operationalinsights-workspace/tree/v0.5.1)
at v0.5.1 (`b4ffa3ff`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-operationalinsights-workspace`: render cases
`basic`, `full`, `names` and `mock`, each validated against ASO v2.22.0's
CRD schemas and the aso-extensions CRDs it renders (`crds/aso-extensions`),
and the refusals in `tests/*.fail.yaml`. `task test-live-azure`
applies it to the Azure sandbox with Azure Service Operator, evaluates the
outputs, deletes it and checks Azure no longer has it: passed on
2026-11-12. `tests/mock.values.yaml` (a
table, a table update, a data export, linked storage, a Monitor Private
Link Scope and a private endpoint to it) is applied to the fake cloud with aso-extensions' manager
beside ASO (`docs/azure.md`, "8. Charts").

0.2.0 against the fake cloud (stock ASO v2.22.0, aso-extensions' manager
at `b9beb5ba`), run `off-catalog-1113104327-27737` (2026-11-13): the workspace, its tables, export, linked storage, scope, scoped resource, private endpoint and its DNS zone group
Ready and deleted, the outputs evaluated.

## Changes

- **0.2.0** (2026-11-13): `private_endpoints` and
  `private_endpoint_extensions` render ASO `PrivateEndpoint` and
  `PrivateEndpointsPrivateDnsZoneGroup`, connected to the module's Monitor
  Private Link Scope; an exclusion that would change a scope's access
  modes stays refused. New output `private_endpoints`.
- **0.1.0** (2026-11-12): the port.
