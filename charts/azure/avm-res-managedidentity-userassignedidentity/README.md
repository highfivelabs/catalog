# avm-res-managedidentity-userassignedidentity

An Azure user-assigned managed identity with its federated identity
credentials, outbound role assignments and lock, as Azure Service Operator
(ASO) objects. A port of the Azure Verified Module
[`avm-res-managedidentity-userassignedidentity`](https://github.com/Azure/terraform-azurerm-avm-res-managedidentity-userassignedidentity/tree/7a0c461789f0177a0b666378924cd5d33196ef8a)
at v0.6.0 (`7a0c4617`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package
`azure-avm-res-managedidentity-userassignedidentity` (`package.yaml`).
Checked against ASO v2.22.0's CRDs.

## Example

```yaml
name: uami-example
location: eastus2
resource_group_name: rg-example
subscription_id: <id>
```

renders the ASO `UserAssignedIdentity` `uami-example`
(`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azurerm_user_assigned_identity.this` | always | `UserAssignedIdentity` (`managedidentity.azure.com/v1api20230131`), `user_assigned_identity`, owned by the resource group; aso-extensions' `UserAssignedIdentity` (`managedidentity.azure.hfl.dev/v20241130`) in its place when `isolation_scope` is set (below) |
| `azurerm_federated_identity_credential.this` | one per `federated_identity_credentials` entry | `FederatedIdentityCredential`, `federated_identity_credential:<key>`, owned by the identity |
| `azurerm_role_assignment.this` | one per `outbound_role_assignments` entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `outbound_role_assignment:<key>`, owned by the entry's `scope` (by ARM ID); its principal the identity's, read with `principalIdFromConfig` from the ConfigMap `<release>-id-outputs` the identity exports (`operatorSpec.configMaps.principalId`) |
| `azurerm_management_lock.this` | `lock` set | `ManagementLock` (aso-extensions), `lock` |
| telemetry | never | not ported |

The identity's principal ID is known only once Azure has made it; ASO's
`principalIdFromConfig` waits for it, which is how the module's
`azurerm_user_assigned_identity.this.principal_id` reference is carried
without kro (`docs/azure.md`, "6. kro verdict").

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`).

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` |
| `resource_group_name` (required) | `owner.armId`: `/subscriptions/<subscription_id>/resourceGroups/<resource_group_name>`, or `resource_group_name` itself when it is a resource group's ID |
| `tags` | `spec.tags` of the identity |
| `federated_identity_credentials` | one credential each: `name` (`azureName`), `audience` (`audiences`), `issuer`, `subject` |
| `outbound_role_assignments` | one assignment each, owned by `scope`: `role_definition_id_or_name` (`armId` or `wellKnownName`), `condition`, `condition_version`, `delegated_managed_identity_resource_id`; `skip_service_principal_aad_check` sends `principalType: ServicePrincipal`, as azurerm does |
| `lock` | the AVM lock interface, with the module's notes for the kind |
| `enable_telemetry` | accepted; the chart sends no telemetry |
| `isolation_scope` | `isolationScope` (`Regional`, the module's only value) of aso-extensions' `UserAssignedIdentity` (`managedidentity.azure.hfl.dev/v20241130`, beside ASO's 2023-01-31 kind under its name; aso-extensions `docs/plan.md` §8 open question 11). Set, the chart renders that kind in place of ASO's: the principal ID goes to the same ConfigMap by a CEL expression (`operatorSpec.configMapExpressions`, `self.status.principalId`; the kind has no `configMaps`), and the federated credentials and the lock own the identity by its ARM ID (their kinds name ASO's `UserAssignedIdentity`). Setting or clearing it on a running identity replaces its Kubernetes object with the other kind's: give it `deletion_policy: ABANDON` for that apply, or the old object's delete deletes the identity (and its client and principal IDs) |

### Not module inputs

| Value | Renders |
| --- | --- |
| `subscription_id` | the subscription of `resource_group_name` when that is a name: the module's azurerm provider knows its subscription, ASO's owner is a resource ID |
| `names.userAssignedIdentity` | the identity's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name`, never of a name under `names` or a credential's; checked against the 128-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

Nothing is refused: every module variable is mapped.

## Outputs

| Output | From |
| --- | --- |
| `client_id`, `principal_id`, `tenant_id` | the identity's `status.clientId`, `status.principalId`, `status.tenantId` |
| `resource_id` | the identity's `status.id` |
| `resource_name` | computed from the inputs, as the module sets it |

Not an output: `resource`, the module's whole azurerm object.

## From Terraform

A module block's arguments are the values, plus `subscription_id` when
`resource_group_name` is a name. ASO adopts an identity or credential that
exists when an object with its name is applied (the identity keeps its
client and principal IDs), so keep the names and leave `namePrefix`
empty; set `deletion_policy: ABANDON` for the first apply, `terraform
state rm` the module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-managedidentity-userassignedidentity`](https://github.com/Azure/terraform-azurerm-avm-res-managedidentity-userassignedidentity/tree/v0.6.0)
at v0.6.0 (`7a0c4617`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-managedidentity-userassignedidentity`: render
cases `basic`, `full`, `names`, `isolation` (aso-extensions' kind), `mock` and
`mock-isolation`, each validated against ASO
v2.22.0's CRD schemas and aso-extensions' `ManagementLock` CRD, and the
refusals in `tests/*.fail.yaml`. `task test-live-azure`
applies it to the Azure sandbox with Azure Service Operator, evaluates the
outputs, deletes it and checks Azure no longer has it: passed on
2026-11-12. `task test-mock-azure` applies its `tests/mock.values.yaml` to aso-extensions'
fake cloud with stock ASO (`docs/azure.md`, "8. Charts").

## Changes

- **0.2.0** (2026-11-13): `isolation_scope` is mapped: set, it renders
  aso-extensions' `UserAssignedIdentity` (`managedidentity.azure.hfl.dev/v20241130`,
  aso-extensions `8d7f8c2`) in place of ASO's.
- **0.1.0** (2026-11-12): the port.
