# aso-extensions CRDs

The CRDs of aso-extensions kinds the Azure charts render, copied from that
repository so the render tests (`hack/test.sh`) validate them with
`kubeconform -strict`, as they validate Azure Service Operator's own kinds
against its CRDs (`hack/aso.sh`).

| File | Kind | Copied from |
| --- | --- | --- |
| `authorization.azure.hfl.dev_managementlocks.yaml` | `ManagementLock` (`authorization.azure.hfl.dev/v1`): the Azure Verified Modules' `lock` | `config/crds/` at `5539c29cd63dbc353513e874a9d775fd209229dd` (2026-11-12) |
| `compute.azure.hfl.dev_virtualmachinesruncommands.yaml` | `VirtualMachinesRunCommand` (`compute.azure.hfl.dev/v20220301`): the virtual machine module's `run_commands` | `config/crds/` at `dcefae06573c4d1f995eefac747ea970498ee847` (2026-11-12) |
| `devtestlab.azure.hfl.dev_schedules.yaml` | `Schedule` (`devtestlab.azure.hfl.dev/v20180915`): the virtual machine module's `shutdown_schedules` | `config/crds/` at `dcefae06573c4d1f995eefac747ea970498ee847` (2026-11-12) |
| `maintenance.azure.hfl.dev_configurationassignments.yaml` | `ConfigurationAssignment` (`maintenance.azure.hfl.dev/v20230401`): the virtual machine module's `maintenance_configuration_resource_ids` | `config/crds/` at `dcefae06573c4d1f995eefac747ea970498ee847` (2026-11-12) |
