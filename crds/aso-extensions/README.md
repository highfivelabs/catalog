# aso-extensions CRDs

The CRDs of aso-extensions kinds the Azure charts render, copied from that
repository so the render tests (`hack/test.sh`) validate them with
`kubeconform -strict`, as they validate Azure Service Operator's own kinds
against its CRDs (`hack/aso.sh`).

| File | Kind | Copied from |
| --- | --- | --- |
| `authorization.azure.hfl.dev_managementlocks.yaml` | `ManagementLock` (`authorization.azure.hfl.dev/v1`): the Azure Verified Modules' `lock` | `config/crds/` at `5539c29cd63dbc353513e874a9d775fd209229dd` (2026-11-12) |
| `containerregistry.azure.hfl.dev_registriescredentialsets.yaml` | `RegistriesCredentialSet` (`containerregistry.azure.hfl.dev/v20251101`): the registry module's `credential_sets` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `containerregistry.azure.hfl.dev_registriesscopemaps.yaml` | `RegistriesScopeMap` (`containerregistry.azure.hfl.dev/v20251101`): the registry module's `scope_maps` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
| `containerregistry.azure.hfl.dev_registriestokens.yaml` | `RegistriesToken` (`containerregistry.azure.hfl.dev/v20251101`): a scope map's `registry_tokens` | `config/crds/` at `b9beb5baec80cb1723f00bbe88fc0d0d8348bc3c` (2026-11-12) |
