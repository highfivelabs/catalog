# aso-extensions CRDs

The CRDs of aso-extensions kinds the Azure charts render, copied from that
repository so the render tests (`hack/test.sh`) validate them with
`kubeconform -strict`, as they validate Azure Service Operator's own kinds
against its CRDs (`hack/aso.sh`).

| File | Kind | Copied from |
| --- | --- | --- |
| `authorization.azure.hfl.dev_managementlocks.yaml` | `ManagementLock` (`authorization.azure.hfl.dev/v1`): the Azure Verified Modules' `lock` | `config/crds/` at `5539c29cd63dbc353513e874a9d775fd209229dd` (2026-11-12) |
| `operationalinsights.azure.hfl.dev_workspacesdataexports.yaml` | `WorkspacesDataExport` (`operationalinsights.azure.hfl.dev/v20250701`): the workspace module's `log_analytics_workspace_data_exports` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `operationalinsights.azure.hfl.dev_workspaceslinkedservices.yaml` | `WorkspacesLinkedService` (`operationalinsights.azure.hfl.dev/v20250701`): the workspace module's `log_analytics_workspace_dedicated_cluster_resource_id` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `operationalinsights.azure.hfl.dev_workspaceslinkedstorageaccounts.yaml` | `WorkspacesLinkedStorageAccount` (`operationalinsights.azure.hfl.dev/v20250701`): the workspace module's `log_analytics_workspace_linked_storage_accounts` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `operationalinsights.azure.hfl.dev_workspacestables.yaml` | `WorkspacesTable` (`operationalinsights.azure.hfl.dev/v20250701`): the workspace module's `log_analytics_workspace_tables` and `_tables_update` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `insights.azure.hfl.dev_privatelinkscopes.yaml` | `PrivateLinkScope` (`insights.azure.hfl.dev/v20210901`): the workspace module's `monitor_private_link_scope` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `insights.azure.hfl.dev_privatelinkscopesscopedresources.yaml` | `PrivateLinkScopesScopedResource` (`insights.azure.hfl.dev/v20210901`): the workspace module's scoped resources | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `network.azure.hfl.dev_networksecurityperimetersresourceassociations.yaml` | `NetworkSecurityPerimetersResourceAssociation` (`network.azure.hfl.dev/v20250501`): the workspace module's `network_security_perimeter_association` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
