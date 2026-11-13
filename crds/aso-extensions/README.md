# aso-extensions CRDs

The CRDs of aso-extensions kinds the Azure charts render, copied from that
repository so the render tests (`hack/test.sh`) validate them with
`kubeconform -strict`, as they validate Azure Service Operator's own kinds
against its CRDs (`hack/aso.sh`).

| File | Kind | Copied from |
| --- | --- | --- |
| `authorization.azure.hfl.dev_managementlocks.yaml` | `ManagementLock` (`authorization.azure.hfl.dev/v1`): the Azure Verified Modules' `lock` | `config/crds/` at `5539c29cd63dbc353513e874a9d775fd209229dd` (2026-11-12) |
| `insights.azure.hfl.dev_privatelinkscopesscopedresources.yaml` | `PrivateLinkScopesScopedResource` (`insights.azure.hfl.dev/v20210901`): `avm-res-insights-component`'s `monitor_private_link_scope` | `config/crds/` at `dcefae06573c4d1f995eefac747ea970498ee847` (2026-11-12) |
