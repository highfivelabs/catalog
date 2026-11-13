# avm-res-authorization-roleassignment

Azure role assignments, at resources, resource groups, subscriptions,
management groups or any scope, and Microsoft Entra directory role
assignments, to principals given by object ID, as Azure Service Operator
(ASO) and aso-extensions objects. A port of the Azure Verified Module
[`avm-res-authorization-roleassignment`](https://github.com/Azure/terraform-azurerm-avm-res-authorization-roleassignment/tree/8f90a2110e81def1c63f8f81f44e60554793e50e)
at v0.3.1 (`8f90a211`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-authorization-roleassignment`
(`package.yaml`). Checked against ASO v2.22.0's CRDs and aso-extensions'
`DirectoryRoleAssignment` CRD (`b9beb5b`).

## Example

```yaml
subscription_id: <subscription id>
users_by_object_id:
  my-user-1: <object id>
groups_by_object_id:
  my-group-1: <object id>
role_definitions:
  reader:
    name: Reader
role_assignments_for_resource_groups:
  example:
    resource_group_name: rg-example
    role_assignments:
      read:
        role_definition: reader
        users: [my-user-1]
        groups: [my-group-1]
```

renders two `RoleAssignment`s of Reader (by name, which ASO resolves) on
`rg-example`, `resourcegroup-user-example-read-my-user-1` and
`resourcegroup-group-example-read-my-group-1`, as the module keys them
(`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azurerm_role_assignment.this` | one per principal of each role assignment of `role_assignments_for_resources`, `_for_resource_groups`, `_for_subscriptions`, `_for_management_groups` and `_for_scopes` | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<module key>`, owned by the scope's ARM ID (`owner.armId`; a role assignment is an extension resource) |
| `azurerm_role_assignment.basic` | one per `role_assignments_azure_resource_manager` entry | `RoleAssignment`, `arm:role-assignment-<key>`, owned by its `scope` |
| `azuread_directory_role_assignment.this` | one per principal of each role assignment of `role_assignments_for_entra_id` | `DirectoryRoleAssignment` (aso-extensions, `entra.azure.hfl.dev/v1`; Microsoft Graph's `roleManagement/directory/roleAssignments`), `entra-role-assignment-<module key>` |
| `azuread_directory_role_assignment.basic` | one per `role_assignments_entra_id` entry | `DirectoryRoleAssignment`, `entra-basic:<key>` |
| `azuread_directory_role.entra_id_role_definitions_by_name` | never | not needed: Graph's role management API assigns a directory role by its template ID without activating it first |
| `data.azurerm_role_definition` | never | a role by ID becomes `roleDefinitionReference.armId`, with the scope's subscription in front as the module formats it (none at a management group); a role by name becomes `wellKnownName`, which ASO resolves |
| `data.azuread_user`, `azuread_group`, `azuread_application`, `azuread_service_principal`, `data.azurerm_user_assigned_identity` | never | lookups in Entra and Resource Manager a render cannot make: principals are taken by object ID; the lookups by name are refused (below) |
| `data.azurerm_resources`, `data.azurerm_management_group` | never | a resource's ID is made from `resource_type` (a chart field) and its name; a management group's from its ID |
| `data.azurerm_client_config` | never | the subscription is the chart's `subscription_id` |
| telemetry | never | not ported |

ASO has no Entra directory role kind; aso-extensions' `DirectoryRoleAssignment`
(at `b9beb5b`, the commit the fake and live runs install; its CRD is copied in
`crds/aso-extensions`) is one. ASO's own Entra kinds (`Application`,
`SecurityGroup`, `ServicePrincipal`) create what they name and look nothing up,
so no kind resolves a principal by name.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`).

| Module input | ASO |
| --- | --- |
| `users_by_object_id`, `groups_by_object_id`, `app_registrations_by_principal_id`, `system_assigned_managed_identities_by_principal_id`, `user_assigned_managed_identities_by_principal_id` | the principals: each value an object ID (a GUID, checked), the assignments' `principalId`. The module's data sources only check that these exist; Azure and Graph check that when they assign |
| `role_definitions` | `id` (a role definition GUID, or an ID ending in one) → `roleDefinitionReference.armId`; `name` → `wellKnownName`. An entry with both takes `id`, as the data source does. `scope` is refused (gap): ASO resolves a name itself, with no lookup scope |
| `role_assignments_for_resource_groups` | owner `/subscriptions/<subscription_id or the chart's>/resourceGroups/<resource_group_name>` |
| `role_assignments_for_subscriptions` | owner `/subscriptions/<subscription_id or the chart's>` |
| `role_assignments_for_resources` | owner `/subscriptions/<the chart's subscription_id>/resourceGroups/<resource_group_name>/providers/<resource_type>/<resource_name>`. `resource_type` is not a module field; an entry without it is refused (gap): the module finds the resource by name in Resource Manager's resource list |
| `role_assignments_for_management_groups` | owner `/providers/Microsoft.Management/managementGroups/<management_group_id>`, the role by ID without a subscription, as the module sends it. `management_group_display_name` alone is refused (gap) |
| `role_assignments_for_scopes` | owner `scope` (a management group's, a subscription's or anything in one; checked) |
| a role assignment's `users`, `groups`, `app_registrations`, `system_assigned_managed_identities`, `user_assigned_managed_identities` | one assignment per principal, `principalType` `User`, `Group` or `ServicePrincipal` as the module sets it |
| a role assignment's `any_principals` | one assignment per principal, from any of the maps (a later map winning a key, as the module merges them), with no `principalType` |
| a role assignment's `skip_service_principal_aad_check` | accepted, no effect: ASO has no such check to skip |
| `role_assignments_azure_resource_manager` | `role_definition_id` (checked to be a role definition ID) → `armId`, or `role_definition_name` → `wellKnownName` (not both); `principal_id`, `principal_type`, `condition`, `condition_version`, `description`, `delegated_managed_identity_resource_id`; `skip_service_principal_aad_check` without a `principal_type` sends `ServicePrincipal`, as azurerm does |
| `entra_id_role_definitions` | `template_id` → `roleDefinitionId`. `display_name` alone is refused (gap): the module finds the directory role by display name |
| `role_assignments_for_entra_id` | one `DirectoryRoleAssignment` per principal, at the whole directory (`directoryScopeId: /`), as the module's assignment |
| `role_assignments_entra_id` | `principal_object_id` → `principalId`, `role_id` → `roleDefinitionId`, `app_scope_id` or `directory_scope_id` (not both); neither sends `/`, the whole directory, as the azuread provider does |
| `skip_service_principal_aad_check` | deprecated and unused in the module; accepted, no effect |
| `enable_telemetry` | accepted; the chart sends no telemetry |
| `users_by_user_principal_name`, `users_by_mail`, `users_by_mail_nickname`, `users_by_employee_id` | refused when set (gap): Entra lookups; give `users_by_object_id` |
| `groups_by_display_name`, `groups_by_mail_nickname` | refused when set (gap): give `groups_by_object_id` |
| `app_registrations_by_client_id`, `app_registrations_by_display_name`, `app_registrations_by_object_id` | refused when set (gap): give the service principal's object ID in `app_registrations_by_principal_id` |
| `system_assigned_managed_identities_by_client_id`, `_by_display_name` | refused when set (gap): give `system_assigned_managed_identities_by_principal_id` |
| `user_assigned_managed_identities_by_client_id`, `_by_display_name`, `_by_resource_group_and_name` | refused when set (gap): give `user_assigned_managed_identities_by_principal_id` (the identity chart's `principal_id` output) |

A role assignment that names a role definition or a principal key the maps
do not have stops the render, as the module's lookups fail.

### Not module inputs

| Value | Renders |
| --- | --- |
| `subscription_id` | the module's provider subscription: of `role_assignments_for_resources`, and of resource group and subscription entries that give none (a GUID, checked; required when one of those needs it) |
| a `role_assignments_for_resources` entry's `resource_type` | the resource's type (`Microsoft.Storage/storageAccounts`) |
| `names` | none: the chart names no Azure resource, so any key is refused |
| `namePrefix` | accepted, no effect: the chart names no Azure resource |
| `tags` | refused when set: role assignments take no Azure tags |
| `labels` | Kubernetes labels on every object |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` annotation on every object). `PREVENT` is refused |

## Outputs

| Output | From |
| --- | --- |
| `users`, `groups`, `app_registrations`, `system_assigned_managed_identities`, `user_assigned_managed_identities` | the object ID maps given (the module's lookups return the same IDs) |
| `all_principals` | their merge, each `{principal_id, type}`, a later map winning a key |
| `role_assignments` | each module-made assignment by its key: `key`, `role_definition_id` (Azure's, `status.roleDefinitionId`), `principal_id`, `scope` (the owner), `principal_type` |
| `role_defintions` (the module's spelling) | each definition's `id` without a subscription: from the `id` given, or for a name, from an assignment that resolved it (null if none did). The module's `scopes` (assignable scopes) are not given: no object holds them |
| `entra_id_role_definitions` | each definition's template ID, as `id` |
| `entra_id_role_assignments` | each module-made directory role assignment by its key: `key`, `role_definition_id`, `principal_id` |
| `resource_id` | null, as in the module |

## From Terraform

A module block's arguments are the values, once principals are given by
object ID (`terraform output -json all_principals` lists them) and a
resource's type is added. ASO adopts an Azure role assignment only by its
name, a GUID: the module lets azurerm pick a random one, and ASO makes a
stable UUID of its own, so an existing assignment is not adopted (Azure
answers `RoleAssignmentExists`): `terraform state rm` and delete the
module's assignments, then apply. A `DirectoryRoleAssignment` adopts an
existing assignment of the same role, principal and scope by default
(`creationMode: AdoptOrCreate`).

## Upstream

Ported from the Azure Verified Module
[`avm-res-authorization-roleassignment`](https://github.com/Azure/terraform-azurerm-avm-res-authorization-roleassignment/tree/v0.3.1)
at v0.3.1 (`8f90a211`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-authorization-roleassignment`: render cases
`basic`, `full` and `mock`, each validated against ASO v2.22.0's CRD
schemas and aso-extensions' `DirectoryRoleAssignment` CRD, and the refusals
in `tests/*.fail.yaml` (the refused variables, the lookups that do not
resolve and the module's argument conflicts).

**Not applied live.** The live rules forbid role assignments in the
sandbox, and the live identity (Contributor on one resource group) cannot
write them (`Microsoft.Authorization/roleAssignments/write`); directory role
assignments need a Graph role the identity does not hold either. So this
chart has no `hack/azure-live.sh` case.

`task test-mock-azure` applies `tests/mock.values.yaml` to aso-extensions'
fake cloud: Reader by name on the fake resource group (ASO resolves the
name against the fake's built-in roles), Contributor by ID there, and
Directory Readers for the same user through the fake Microsoft Graph
(`hack/azure-mock.sh` runs aso-extensions' `fakegraph` for it, with the
user in its directory). Passed on 2026-11-13 (run
`off-catalog-1113081928-18333`, stock ASO and aso-extensions' manager at
`b9beb5b`): 3 objects Ready and deleted, the outputs evaluated (the first
run, `off-catalog-1113080807-19037`, had every object Ready and deleted but
found `role_defintions` reading the directory role assignments too; fixed).

## Changes

- **0.1.0** (2026-11-13): the port.
