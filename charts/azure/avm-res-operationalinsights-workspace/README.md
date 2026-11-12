# avm-res-operationalinsights-workspace

An Azure Log Analytics workspace with its lock, role assignments and
diagnostic settings, as Azure Service Operator (ASO) objects. A port of
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
| data exports, linked service, linked storage accounts, tables, Monitor Private Link Scope, network security perimeter association, private endpoints | when set | refused (below) |
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
| `log_analytics_workspace_data_exports` | `Microsoft.OperationalInsights/workspaces/dataExports` has no ASO or aso-extensions kind (gap) |
| `log_analytics_workspace_dedicated_cluster_resource_id` | the module links the cluster with `.../workspaces/linkedServices`, which has no kind (gap) |
| `log_analytics_workspace_linked_storage_accounts` | `.../workspaces/linkedStorageAccounts` has no kind (gap) |
| `log_analytics_workspace_tables`, `log_analytics_workspace_tables_update` | `.../workspaces/tables` has no kind (gap) |
| `monitor_private_link_scope`, `monitor_private_link_scoped_resource`, `monitor_private_link_scoped_service_name` | `Microsoft.Insights/privateLinkScopes` and their `scopedResources` have no kind (gap) |
| `network_security_perimeter_association` | `Microsoft.Network/networkSecurityPerimeters/resourceAssociations` has no kind (gap) |
| `private_endpoints`, `private_endpoint_extensions` | ASO has `PrivateEndpoint`; the chart does not map private endpoints yet (not ported) |
| `log_analytics_workspace_timeouts` | ASO has no per-request timeouts; Bundt sets a component's time limit |

## Outputs

| Output | From |
| --- | --- |
| `resource_id` | the workspace's `status.id` |
| `customer_id` | not a module output: the workspace ID agents and queries take (`status.customerId`), the field consumers read from the module's `resource` |

Not outputs: `resource` (the module's whole azurerm object, sensitive for
its shared keys) and `private_endpoints` (refused).

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
CRD schemas and aso-extensions' `ManagementLock` CRD, and the refusals in
`tests/*.fail.yaml`. `task test-live-azure`
applies it to the Azure sandbox with Azure Service Operator, evaluates the
outputs, deletes it and checks Azure no longer has it: passed on
2026-11-12. `task test-mock-azure` applies its `tests/mock.values.yaml` to aso-extensions'
fake cloud with stock ASO (`docs/azure.md`, "8. Charts").

## Changes

- **0.1.0** (2026-11-12): the port.
