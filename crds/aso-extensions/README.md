# aso-extensions CRDs

The CRDs of aso-extensions kinds the Azure charts render, copied from that
repository so the render tests (`hack/test.sh`) validate them with
`kubeconform -strict`, as they validate Azure Service Operator's own kinds
against its CRDs (`hack/aso.sh`).

| File | Kind | Copied from |
| --- | --- | --- |
| `authorization.azure.hfl.dev_managementlocks.yaml` | `ManagementLock` (`authorization.azure.hfl.dev/v1`): the Azure Verified Modules' `lock` | `config/crds/` at `5539c29cd63dbc353513e874a9d775fd209229dd` (2026-11-12) |
| `network.azure.hfl.dev_privatednszonessoarecords.yaml` | `PrivateDnsZonesSOARecord` (`network.azure.hfl.dev/v20240601`): the private DNS zone module's `soa_record` | `config/crds/` at `e3b4177ba6a2ef5c52747a9886c158e9cd8c7134` (2026-11-12) |
| `containerservice.azure.hfl.dev_managedclustersmanagednamespaces.yaml` | `ManagedClustersManagedNamespace` (`containerservice.azure.hfl.dev/v20260501`): the AKS module's `namespace` | `config/crds/` at `e3b4177ba6a2ef5c52747a9886c158e9cd8c7134` (2026-11-12) |
| `insights.azure.hfl.dev_privatelinkscopesscopedresources.yaml` | `PrivateLinkScopesScopedResource` (`insights.azure.hfl.dev/v20210901`): the workspace module's scoped resources and `avm-res-insights-component`'s `monitor_private_link_scope` | `config/crds/` at `dcefae06573c4d1f995eefac747ea970498ee847` (2026-11-12) |
| `containerregistry.azure.hfl.dev_registriescredentialsets.yaml` | `RegistriesCredentialSet` (`containerregistry.azure.hfl.dev/v20251101`): the registry module's `credential_sets` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `containerregistry.azure.hfl.dev_registriesscopemaps.yaml` | `RegistriesScopeMap` (`containerregistry.azure.hfl.dev/v20251101`): the registry module's `scope_maps` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `containerregistry.azure.hfl.dev_registriestokens.yaml` | `RegistriesToken` (`containerregistry.azure.hfl.dev/v20251101`): a scope map's `registry_tokens` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `operationalinsights.azure.hfl.dev_workspacesdataexports.yaml` | `WorkspacesDataExport` (`operationalinsights.azure.hfl.dev/v20250701`): the workspace module's `log_analytics_workspace_data_exports` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `operationalinsights.azure.hfl.dev_workspaceslinkedservices.yaml` | `WorkspacesLinkedService` (`operationalinsights.azure.hfl.dev/v20250701`): the workspace module's `log_analytics_workspace_dedicated_cluster_resource_id` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `operationalinsights.azure.hfl.dev_workspaceslinkedstorageaccounts.yaml` | `WorkspacesLinkedStorageAccount` (`operationalinsights.azure.hfl.dev/v20250701`): the workspace module's `log_analytics_workspace_linked_storage_accounts` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `operationalinsights.azure.hfl.dev_workspacestables.yaml` | `WorkspacesTable` (`operationalinsights.azure.hfl.dev/v20250701`): the workspace module's `log_analytics_workspace_tables` and `_tables_update` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `insights.azure.hfl.dev_privatelinkscopes.yaml` | `PrivateLinkScope` (`insights.azure.hfl.dev/v20210901`): the workspace module's `monitor_private_link_scope` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `network.azure.hfl.dev_networksecurityperimetersresourceassociations.yaml` | `NetworkSecurityPerimetersResourceAssociation` (`network.azure.hfl.dev/v20250501`): the workspace module's `network_security_perimeter_association` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `storage.azure.hfl.dev_storageaccountslocalusers.yaml` | `StorageAccountsLocalUser` (`storage.azure.hfl.dev/v20260601`): the storage account module's `local_user` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `cognitiveservices.azure.hfl.dev_accountsraipolicies.yaml` | `AccountsRaiPolicy` (`cognitiveservices.azure.hfl.dev/v20250601`): `avm-res-cognitiveservices-account`'s `rai_policies` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-13) |
