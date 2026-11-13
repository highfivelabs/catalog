# avm-res-web-serverfarm

An Azure App Service plan (server farm) with its lock, role assignments and
diagnostic settings, as Azure Service Operator (ASO) objects. A port of the
Azure Verified Module
[`avm-res-web-serverfarm`](https://github.com/Azure/terraform-azurerm-avm-res-web-serverfarm/tree/077bbb36ea58ae8e2ead058848c551db0c664544)
at v2.0.8 (`077bbb36`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-web-serverfarm`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

## Example

```yaml
name: asp-linux
location: eastus2
parent_id: /subscriptions/<id>/resourceGroups/rg-example
os_type: Linux
sku_name: B1
worker_count: 1
zone_balancing_enabled: false
```

renders one ASO `ServerFarm` `asp-linux`, a Linux B1 plan with one worker
(`tests/golden/linux.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.this` | always | `ServerFarm` (`web.azure.com/v20250501`; the module sends 2025-03-01), `server_farm`, owned by the resource group `parent_id` names |
| `azapi_resource.lock` | `lock` set | `ManagementLock` (aso-extensions), `lock`, named `lock-<kind>` by default |
| `azapi_resource.role_assignment` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `azapi_resource.diagnostic_setting` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` |
| telemetry | never | not ported |

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`). The plan's shape is derived as the
module derives it (`locals.tf`):

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` |
| `parent_id` (required) | `owner.armId` |
| `os_type` (required) | `kind` (`linux` or `windows`; `functionapp` for FC1 and `elastic` for WS whatever the OS), `reserved` (Linux), `hyperV` (WindowsContainer), `isCustomMode` (WindowsManagedInstance) |
| `sku_name` | `sku.name`; FC1 has capacity 0, WS always elastic scale |
| `worker_count` | `sku.capacity`, and `maximumElasticWorkerCount` outside EP, WS and FC; null leaves both to an external autoscale setting |
| `maximum_elastic_worker_count` | `maximumElasticWorkerCount` on EP and WS (not on FC1, as in the module) |
| `premium_plan_auto_scale_enabled` | `elasticScaleEnabled` on EP and P SKUs (always on WS, off otherwise) |
| `zone_balancing_enabled`, `per_site_scaling_enabled`, `async_scaling_enabled` | `zoneRedundant`, `perSiteScaling`, `asyncScalingEnabled` (when set) |
| `app_service_environment_id` | `hostingEnvironmentProfile.reference.armId` |
| `virtual_network_subnet_id` | `network.virtualNetworkSubnetReference.armId` |
| `managed_identities` | `identity`: `type` and `userAssignedIdentities` by ARM ID |
| `install_scripts`, `storage_mounts`, `plan_default_identity`, `rdp_enabled`, `registry_adapters` | on a `WindowsManagedInstance` plan only, as in the module: `installScripts`, `storageMounts`, `planDefaultIdentity`, `rdpEnabled`, `registryAdapters` (a type `DWORD` is ARM's `DWord`). A Key Vault reference is the secret's URI, which the plan reads with its identity; no secret value passes through the chart |
| `tags` | `spec.tags` |
| `lock`, `role_assignments`, `diagnostic_settings` | the AVM interfaces (avm-utl-interfaces 0.6.0; diagnostic settings v2, each needing a name) |
| `enable_telemetry` | accepted; the chart sends no telemetry |
| `server_farm_resource_type` | accepted at its default only (below) |

Not ported: the module's early check that a zone-redundant Flex
Consumption plan's region offers it (a `geoRegions` query at plan time);
Azure refuses such a plan where it is not offered.

### Not module inputs

| Value | Renders |
| --- | --- |
| `names.serverFarm` | the plan's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name`, never of a name under `names`; checked against the 60-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

### Refused when set

| Variable | Kind | Why |
| --- | --- | --- |
| `retry`, `timeouts` | by-design | ASO retries itself; Bundt sets a component's time limit |
| `server_farm_resource_type` | by-design (in part) | any value but the default: the API version is the ASO kind's (2025-05-01) |

## Outputs

| Output | From |
| --- | --- |
| `name` | the plan's `azureName` |
| `resource_id` | the plan's `status.id` |

## From Terraform

A module block's arguments are the values. ASO adopts a plan that exists
when an object with its name is applied, so keep the name and leave
`namePrefix` empty; set `deletion_policy: ABANDON` for the first apply,
`terraform state rm` the module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-web-serverfarm`](https://github.com/Azure/terraform-azurerm-avm-res-web-serverfarm/tree/v2.0.8)
at v2.0.8 (`077bbb36`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-web-serverfarm`: render cases `basic`, `linux`,
`flex`, `elastic`, `workflow`, `full`, `names` and `mock`, each validated
against ASO v2.22.0's CRD schemas and aso-extensions' `ManagementLock` CRD,
and the refusals in `tests/*.fail.yaml`. `task test-live-azure` (case
`asp`, only when named) applies a Linux B1 plan with one worker to the
Azure sandbox, evaluates the outputs, deletes it and checks Azure no longer
has it. It has not passed: the sandbox's App Service quota is 0 (B1 and F1),
and Azure refused the plan (docs/azure.md, "8. Charts"). `task
test-mock-azure` applies `tests/mock.values.yaml` to aso-extensions' fake
cloud: passed on 2026-11-13, the plan Ready and deleted, the outputs
evaluated.

## Changes

- **0.1.0** (2026-11-12): the port.
