# avm-ptn-alz

An Azure landing zone architecture: management groups and their
hierarchy settings, policy definitions, policy set definitions, policy
assignments with the role assignments their identities need, role
definitions, management group role assignments and subscription
placement, as Azure Service Operator (ASO) and aso-extensions objects. A
port of the Azure Verified Module pattern
[`avm-ptn-alz`](https://github.com/Azure/terraform-azurerm-avm-ptn-alz/tree/e2a318c3eba91967c4ce3cd2738b2b2569db994e)
at v0.22.0 (`e2a318c3`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-ptn-alz` (`package.yaml`).
Checked against ASO v2.22.0's CRDs and aso-extensions' at `b9beb5b`.

Coverage: 18 of the module's 26 variables, 4 of them in part; 7 of 7
outputs. The 8 refused whole are the alz provider's resolution arguments
(4), the azapi mechanics (`resource_types`, `retries`, `timeouts`) and a
destroy-time move (`subscription_placement_destroy_custom_target_management_group_id`).

**The architecture is given resolved.** The module does not list its
resources: it reads them from the alz provider's library, through the
`alz_architecture` data source, which fetches the library and resolves
`architecture_name` (with `policy_assignments_to_modify`,
`policy_default_values`, the non-compliance message settings and the
`assignPermissions` overrides) when Terraform plans. A render fetches
nothing and the chart does not vendor the library. So the chart takes that
data source's result as the value `architecture` (not a module variable):
`{name, management_groups: [{id, display_name, parent_id, exists, level,
policy_definitions, policy_set_definitions, policy_assignments,
role_definitions}], policy_role_assignments: [{management_group_id,
policy_assignment_name, role_definition_id, scope}]}`, each policy or role
resource as the data source gives it (a JSON string) or as an object.
`terraform console` prints it for a module call
(`data.alz_architecture.<name>` with the module's arguments, or
`jsonencode(...)` of it). The data source's arguments are then refused
when set; `architecture_name` is checked against the architecture's name;
`policy_assignments_to_modify`'s `creation_enabled` and
`role_assignments_enabled`, which the module applies itself, are applied.

## Example

`tests/basic.values.yaml`: an architecture `alz-small` with an
intermediate root `alz` under the tenant root and `landingzones` beneath
it; at `alz` a custom policy definition, a set of it, an assignment of the
set with a system-assigned identity and the role assignment the provider
computed for it, and a custom role definition. It renders two
`ManagementGroup`s, a `PolicyDefinition`, `PolicySetDefinition`,
`PolicyAssignment`, `RoleDefinition` and the policy's `RoleAssignment`
(`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `data.alz_architecture.this` | | not ported: the `architecture` value is its result |
| `azapi_resource.management_groups_level_0`..`_6` | each management group of the architecture not marked `exists` | `ManagementGroup` (aso-extensions, `management.azure.hfl.dev/v20230401`), `management_group:<id>`: `azureName` the ID, `displayName`, `details.parent` the chart's group by reference or the parent's ID; none when the parent is the tenant root group (`tenant_id`), where a group without a parent goes |
| `azapi_resource.hierarchy_settings`, `azapi_update_resource.hierarchy_settings` | `management_group_hierarchy_settings` | `ManagementGroupsSetting` (aso-extensions) on the tenant root group, `hierarchy_settings`; with `update_existing` always detached on delete, as the module's update leaves them |
| `azapi_resource.policy_definitions` | each management group's `policy_definitions` | `PolicyDefinition` (aso-extensions, `authorization.azure.hfl.dev/v20260701`; the module sends 2023-04-01), `policy_definition:<group>/<key>`: the properties transcribed, a parameter's metadata keys other than `assignPermissions`, `description`, `displayName` and `strongType` under its `additionalProperties`, where the ARM type keeps them |
| `azapi_resource.policy_set_definitions` | `policy_set_definitions` | `PolicySetDefinition` (aso-extensions, 2026-07-01), `policy_set_definition:<group>/<key>`: `policyDefinitionId` as `policyDefinitionReference.armId`, a group's `additionalMetadataId` as `additionalMetadataReference.armId` |
| `azapi_resource.policy_assignments` | `policy_assignments`, unless `policy_assignments_to_modify` disables one | `PolicyAssignment` (aso-extensions, 2026-07-01; the module sends 2024-04-01), `policy_assignment:<group>/<key>`: `location`, the properties the module sends (`definitionVersion` default `1.*.*`, `metadata` with the module's blank `createdBy`/`createdOn`/`updatedBy`/`updatedOn`), the identity; with an identity, its principal exported to a ConfigMap (`configMapExpressions`) |
| `azapi_resource.role_definitions` | `role_definitions` | `RoleDefinition` (`authorization.azure.com/v20220401`), `role_definition:<group>/<key>`, owned by the group's ID |
| `azapi_resource.policy_role_assignments` | `policy_role_assignments`, except at the all-zero subscription and where `policy_assignments_to_modify` disables the assignment or its role assignments | `RoleAssignment` (`authorization.azure.com/v20220401`), `policy_role_assignment:<key>`, named by the module's key (`uuidv5` of assignment name, scope, group and role), a role at a subscription scope prefixed with the subscription as the module does, its principal from the assignment's ConfigMap (`principalIdFromConfig`): the system-assigned identity's, or its user-assigned identity's from the assignment's status, where the module reads that identity |
| `azapi_resource.management_group_role_assignments` | `management_group_role_assignments` | `RoleAssignment`, `management_group_role_assignment:<key>`, avm-utl-interfaces' body; named by its deterministic `uuidv5` of principal and role definition ID for a role by ID (ASO's stable UUID with `role_assignment_name_use_random_uuid`, or for a role by name, which ASO resolves as `wellKnownName`) |
| `azapi_resource.subscription_placement` | `subscription_placement` with the default destroy behavior | `ManagementGroupsSubscription` (aso-extensions), `subscription_placement:<key>` |
| `azapi_resource_action.subscription_placement_create`/`_delete` | another destroy behavior | refused: a PUT at destroy |
| `time_sleep`, `terraform_data`, `data.azapi_resource.policy_user_assigned_identities`, `data.azapi_client_config`, telemetry | | not ported (ASO retries until what an object needs exists; the identity's principal comes from the assignment's status; the tenant is `tenant_id`) |

aso-extensions' kinds own and reference the chart's management groups by
object, so ASO waits for them; ASO's own `RoleDefinition` and
`RoleAssignment` cannot resolve an aso-extensions kind and take the
group's ID, retrying until it exists.

## Values: module inputs to ASO

| Module input | ASO |
| --- | --- |
| `architecture_name` (required) | checked against `architecture.name` (in part: the resolution is refused) |
| `location` (required) | every policy assignment's `location` |
| `parent_resource_id` (required) | the parent of an architecture management group that names none (checked as the module checks it) |
| `management_group_hierarchy_settings` | the `ManagementGroupsSetting`: `default_management_group_name` (checked as the module checks it), `require_authorization_for_group_creation` (default true), `update_existing` |
| `management_group_role_assignments` | the `RoleAssignment`s: every field |
| `role_assignment_definition_lookup_enabled` | false: a role by name is refused, as the module's lookup would fail |
| `role_assignment_name_use_random_uuid` | true: no `azureName` (ASO's stable UUID) |
| `subscription_placement` | the `ManagementGroupsSubscription`s (UUIDs, each once, checked as the module checks them) |
| `subscription_placement_destroy_behavior` | `default`, and `intermediate_root` when the architecture has no existing level-0 group (the module then falls back to `default`); others refused |
| `policy_assignments_to_modify` | `creation_enabled`, `role_assignments_enabled` (in part: the other fields refused) |
| `parent_id_overrides` | accepted, no effect: ASO addresses an owner by object or ID and does not replace a resource over the case of its parent's ID |
| `delays`, `management_groups_dependencies`, `policy_assignments_dependencies`, `policy_role_assignments_dependencies` | accepted, no effect: ASO retries until what an object needs exists, and Bundt orders components |
| `schema_validation_enabled` | `true` accepted, no effect; `false` refused (in part) |
| `enable_telemetry`, `telemetry_additional_content` | accepted; the chart sends no telemetry |

### Not module inputs

| Value | Renders |
| --- | --- |
| `architecture` (required) | everything above: the `alz_architecture` data source's result |
| `tenant_id` | the tenant root group's name: where the hierarchy settings go (required with them), and the parent that a group is made without |
| `names` | none: the names are the architecture's; any key is refused |
| `tags` | refused when set: none of these resources takes Azure tags |
| `namePrefix` | accepted, no effect: a management group's ID is named in the architecture's own resource IDs (policy definition IDs, scopes, assignable scopes) |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused |

### Refused when set

| Variable | Kind | Why |
| --- | --- | --- |
| `override_policy_definition_parameter_assign_permissions_set`, `_unset` | gap | arguments of the alz provider's resolution, which a render cannot run; the given architecture is resolved (the module's default list applies there) |
| `policy_default_values` | gap | the same |
| `policy_assignment_non_compliance_message_settings` | gap | the same (the provider's default message is in a resolved architecture already) |
| `policy_assignments_to_modify` (in part) | gap | every field but `creation_enabled` and `role_assignments_enabled`: the same |
| `architecture_name` (in part) | gap | the resolution from the library |
| `subscription_placement_destroy_behavior` (in part), `subscription_placement_destroy_custom_target_management_group_id` | gap | a move of the subscription with a PUT at destroy, which ASO cannot make; deleting the placement moves it to the tenant's default group |
| `resource_types` | by-design | the kinds fix the API versions |
| `retries` | by-design | ASO retries itself |
| `timeouts` | by-design | Bundt sets a component's time limit |
| `schema_validation_enabled` (in part) | by-design | `false`: the CRD schemas always validate |

## Outputs

| Output | From |
| --- | --- |
| `management_group_resource_ids` | `{<id>: status.id}` of the groups the chart makes |
| `policy_definition_resource_ids`, `policy_set_definition_resource_ids`, `policy_assignment_resource_ids`, `role_definition_resource_ids` | `{<group>/<key>: status.id}` |
| `policy_role_assignment_resource_ids` | `{<module key>: status.id}` |
| `policy_assignment_identity_ids` | `{<group>/<key>: principal}` for each assignment with an identity: its `status.identity.principalId`, or its user-assigned identity's from `status.identity.userAssignedIdentities` |

## From Terraform

Print the module's resolved architecture (`terraform console`, the
`alz_architecture` data source with the module call's arguments) into
`architecture`; the other arguments are the values, plus `tenant_id`. ASO
adopts resources that exist when an object with their name is applied,
so set `deletion_policy: ABANDON` for the first apply, `terraform state
rm` the module, then remove `ABANDON`. Management group role assignments
given by role name get a new name; remove the module's first.

## Upstream

Ported from the Azure Verified Module
[`avm-ptn-alz`](https://github.com/Azure/terraform-azurerm-avm-ptn-alz/tree/v0.22.0)
at v0.22.0 (`e2a318c3`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-ptn-alz`: render cases `basic`, `full` (every input:
an existing intermediate root, user-assigned identities, disabled
assignments and role assignments, a subscription-scope policy role
assignment, hierarchy settings, management group role assignments by ID
and name, placement) and `mock`, each validated against ASO v2.22.0's CRD
schemas and the aso-extensions CRDs it renders (`crds/aso-extensions`), and
the refusals in `tests/*.fail.yaml`.

**Fake cloud** (`tests/mock.values.yaml`: one management group under the
fake tenant's root, a policy definition, set definition and role
definition at it, an assignment of the set, a management group role
assignment and the fake's subscription placed in it), stock ASO and
aso-extensions' manager at `b9beb5b` against aso-extensions' fakearm,
offload run `off-catalog-1113111130-6616` on 2026-11-13: 7 objects Ready
and deleted, outputs evaluated.

The first run (`off-catalog-1113104126-12280`, with two levels of groups
and an assignment with a system-assigned identity and its policy role
assignment) found two gaps of aso-extensions at `b9beb5b`, which the mock
now leaves out; the chart renders both as the module does:

- **A child management group is not retried.** aso-extensions'
  `ManagementGroup` resolves its parent reference to the parent's ID
  without waiting for the parent to exist; the fake answers the first PUT
  `400 ParentGroupNotFound`, the controller records it as a Warning and
  does not retry, so the child (and what it owns: a placement, a role
  assignment there) never becomes Ready. Terraform orders the levels
  (`management_groups_level_0`..`_6`); the kind should wait for, or retry
  on, a parent it references.
- **A policy assignment cannot export its principal.** The manager's
  ClusterRole (`config/rbac/role.yaml`) has only get, list and watch on
  ConfigMaps, so `operatorSpec.configMapExpressions` fails ("configmaps is
  forbidden ... cannot create resource"), and the policy role assignment
  that reads the principal (`principalIdFromConfig`) waits for a ConfigMap
  that never comes. The manager needs create and update on ConfigMaps
  (and Secrets, for `secretExpressions`).

Not run against the fake: hierarchy settings (the fake Resource Manager
has no tenant root group, which the settings belong to).

**Not applied live.** Every resource is tenant or management group scope
(management groups, their settings, policy and role definitions, policy
and role assignments at management groups, subscription placement); the
live rules allow none of them, and the sandbox identity is Contributor on
one resource group.

## Changes

- **0.1.0** (2026-11-13): the port.
