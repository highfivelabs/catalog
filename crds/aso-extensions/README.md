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
| `insights.azure.hfl.dev_privatelinkscopesscopedresources.yaml` | `PrivateLinkScopesScopedResource` (`insights.azure.hfl.dev/v20210901`): `avm-res-insights-component`'s `monitor_private_link_scope` | `config/crds/` at `dcefae06573c4d1f995eefac747ea970498ee847` (2026-11-12) |
