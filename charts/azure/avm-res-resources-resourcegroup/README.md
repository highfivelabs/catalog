# avm-res-resources-resourcegroup

An Azure resource group, its lock and its role assignments, as Azure
Service Operator (ASO) objects. A port of the Azure Verified Module
[`avm-res-resources-resourcegroup`](https://github.com/Azure/terraform-azurerm-avm-res-resources-resourcegroup/tree/4c7e926d9aa11000d7c31a6b4c26100371b2ac62)
at v0.5.0 (`4c7e926d`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-resources-resourcegroup`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

## Example

```yaml
name: rg-example
location: eastus2
```

renders the ASO `ResourceGroup` `rg-example` in `eastus2`
(`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.this` (`Microsoft.Resources/resourceGroups`) | always | `ResourceGroup` (`resources.azure.com/v1api20200601`), `resource_group` |
| `azapi_resource.lock` (`Microsoft.Authorization/locks`) | `lock` set | `ManagementLock` (aso-extensions, `authorization.azure.hfl.dev/v1`), `lock`, owned by the group |
| `azapi_resource.role_assignments` | one per `role_assignments` entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>`, owned by the group |
| `azapi_resource.telemetry` (a `Microsoft.Resources/deployments`) | never | the module's usage telemetry is not ported |

ASO's `ResourceGroup` is at ARM API version 2020-06-01, older than the
module's 2025-04-01; the properties the module sets (`location`,
`managedBy`, `tags`) are the same in both.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`).

| Module input | ASO |
| --- | --- |
| `name` (required) | the group's `spec.azureName` |
| `location` (required) | `spec.location` |
| `managed_by` | `spec.managedBy` |
| `tags` | `spec.tags` |
| `lock` | a `ManagementLock`: `level` is `kind`, `azureName` is `name`, else `lock-<kind>` as the module names it |
| `role_assignments` | a `RoleAssignment` each: `principalId`, `principalType`, `description`, `condition`, `conditionVersion`, `delegatedManagedIdentityResourceReference.armId`; `role_definition_id_or_name` is `roleDefinitionReference.armId` when it is a role definition ID, else `roleDefinitionReference.wellKnownName` (ASO looks the name up, as the module does); `name` (a GUID) is `azureName`, and without one ASO gives the assignment a stable UUID where the module makes a random one; `skip_service_principal_aad_check` is accepted and does nothing, as in the module's azapi resources |
| `enable_telemetry` | accepted; the chart sends no telemetry |
| `ignore_tag_changes`, `retry`, `timeouts` | refused (below) |

The module's validations stop the render with the module's messages: the
group name's pattern, the lock's kind, `managed_by` as a resource ID, a
role assignment's role and GUID name.

### Not module inputs

| Value | Renders |
| --- | --- |
| `names.resourceGroup` | the group's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name`, never of a name under `names`; checked against the 90-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure: Azure tags are `tags` |
| `deletion_policy` | `DELETE` (default) or `ABANDON`: every object gets ASO's `serviceoperator.azure.com/reconcile-policy: detach-on-delete`, so the group, its lock and its role assignments stay in Azure when the component is deleted. `PREVENT` is refused: a `CanNotDelete` lock is Azure's way |

### Refused when set

| Variable | Why |
| --- | --- |
| `ignore_tag_changes` | ASO applies every tag it is given; it cannot leave the tags to another writer |
| `retry` | ASO retries every failed request itself, with backoff |
| `timeouts` | ASO has no per-request timeouts; Bundt sets a component's time limit |

## Outputs

| Output | From |
| --- | --- |
| `name` | computed from the inputs, as the module sets it (`names.resourceGroup`, else `name` with the `namePrefix`) |
| `location` | `location` |
| `resource_id` | the group's `status.id` |

Not an output: `resource`, the module's whole azapi object
(`docs/design.md`, "Outputs").

## From Terraform

A module block's arguments are the values, unchanged. ASO adopts a group
that exists when an object with its name is applied (a PUT of the same
properties), so keep `name` and leave `namePrefix` empty. Set
`deletion_policy: ABANDON` for the first apply, `terraform state rm` the
module, then remove `ABANDON`. A role assignment the module made with a
random name keeps it only if its `name` is set to that GUID; otherwise ASO
makes a second assignment of the same role (Azure refuses a duplicate, so
set the name).

## Upstream

Ported from the Azure Verified Module
[`avm-res-resources-resourcegroup`](https://github.com/Azure/terraform-azurerm-avm-res-resources-resourcegroup/tree/v0.5.0)
at v0.5.0 (`4c7e926d`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced, and the
module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
as `azure/avm-res-resources-resourcegroup`.

## Tests

`task test CHART=avm-res-resources-resourcegroup`: render cases `basic`,
`full`, `names`, `abandon` and `mock`, each validated against ASO
v2.22.0's CRD schemas (`hack/aso.sh`) and, for the lock, aso-extensions'
CRD (`crds/aso-extensions`); the refusals in `tests/*.fail.yaml`. Not applied to Azure yet: the live identity cannot make a resource group
(a subscription-scope action). `task test-mock-azure` applies its
`tests/mock.values.yaml` to aso-extensions' fake cloud with stock ASO:
passed on 2026-11-12 (`docs/azure.md`, "8. Charts").

## Changes

- **0.1.0** (2026-11-12): the port.
