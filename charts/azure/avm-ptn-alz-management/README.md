# avm-ptn-alz-management

The Azure landing zone's management resources: a resource group, a Log
Analytics workspace, an Automation account linked to it, Log Analytics
solutions, Microsoft Sentinel onboarding, three data collection rules
(change tracking, VM insights, Defender for SQL) and a user-assigned
identity for the Azure Monitor Agent, as Azure Service Operator (ASO) and
aso-extensions objects. A port of the Azure Verified Module pattern
[`avm-ptn-alz-management`](https://github.com/Azure/terraform-azurerm-avm-ptn-alz-management/tree/3026684f8aa489dd9f88f637afdf859cb1bcee27)
at v0.10.0 (`3026684f`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-ptn-alz-management`
(`package.yaml`). Checked against ASO v2.22.0's CRDs and aso-extensions'
at `b9beb5b`.

Coverage: 29 of the module's 30 variables (only `timeouts` is refused) and
6 of its 8 outputs (the two `*_keys` outputs are secrets).

## Example

```yaml
automation_account_name: aa-management
location: eastus2
resource_group_name: rg-management
subscription_id: <id>
log_analytics_workspace_name: law-management
```

renders, as the module's defaults do, the resource group `rg-management`,
the workspace `law-management` (PerGB2018, 30 days), the solutions
`ContainerInsights(law-management)` and `VMInsights(law-management)`, the
rules `dcr-change-tracking`, `dcr-vm-insights` and `dcr-defender-sql`
writing to the workspace, and the identity `uami-ama`
(`tests/golden/basic.yaml`). No Automation account:
`linked_automation_account_creation_enabled` defaults to false.

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azurerm_resource_group.management` | `resource_group_creation_enabled` (default) | `ResourceGroup` (`resources.azure.com/v1api20200601`), `resource_group`; the other group-level objects are owned by it by name |
| `azurerm_log_analytics_workspace.management` | `log_analytics_workspace_creation_enabled` (default) | `Workspace` (`operationalinsights.azure.com/v20250701`), `log_analytics_workspace` |
| `azurerm_automation_account.management` | `linked_automation_account_creation_enabled` | `AutomationAccount` (aso-extensions, `automation.azure.hfl.dev/v20241023`), `automation_account` |
| `azurerm_log_analytics_linked_service.management` | `linked_automation_account_creation_enabled` | `WorkspacesLinkedService` (aso-extensions) `Automation` (azurerm's name for a read access link) in the workspace, `log_analytics_linked_service` |
| `azurerm_log_analytics_solution.management` | one per `log_analytics_solution_plans` entry | `Solution` (aso-extensions, `operationsmanagement.azure.hfl.dev/v20151101preview`) `<product's last segment>(<workspace>)`, as azurerm names it and its plan, `log_analytics_solution:<publisher>/<product>` |
| `azapi_resource.sentinel_onboarding` | `sentinel_onboarding` not null | `OnboardingState` (aso-extensions, `securityinsights.azure.hfl.dev/v20250901`) on the workspace, `sentinel_onboarding` |
| `azurerm_user_assigned_identity.management` | `user_assigned_managed_identities.ama.enabled` (default) | `UserAssignedIdentity` (`managedidentity.azure.com/v1api20230131`), `user_assigned_identity:ama` |
| `azapi_resource.data_collection_rule` | one per enabled rule (all three by default) | `DataCollectionRule` (`insights.azure.com/v1api20240311`), `data_collection_rule:<change_tracking, vm_insights, defender_sql>`, the module's bodies transcribed |
| telemetry, the `moved`/`removed` blocks | never | not ported |

ASO's `DataCollectionRule` is at ARM API version 2024-03-11; the module
sends 2021-04-01. The VM insights rule's performance counter carries
`scheduledTransferPeriod: PT1M` in the module, which sends that rule with
schema validation off: the property is in neither API version, and the
chart does not send it.

A reference from an aso-extensions object (the linked service's
Automation account, a solution's workspace) is the ARM ID the resource
will have, computed from the group's ID and its name, so the chart needs
the subscription (`subscription_id`, or `resource_group_name` as an ID)
even when it makes the group; the object retries until the resource
exists. ASO's own objects (a rule's destination workspace) and owners
reference the chart's objects by name.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`).

| Module input | ASO |
| --- | --- |
| `resource_group_name` (required), `location` (required) | the group's `azureName` and `location` when made; otherwise every group-level object's `owner.armId` (`/subscriptions/<subscription_id>/resourceGroups/<name>`, or `resource_group_name` itself when it is an ID) |
| `resource_group_creation_enabled` | whether the `ResourceGroup` is rendered |
| `tags` | `spec.tags` of the group, workspace, Automation account and solutions, and of a rule or the identity without its own |
| `log_analytics_workspace_creation_enabled`, `log_analytics_workspace_name` | whether the `Workspace` is rendered, its `azureName` (required when made, the module's message) |
| `log_analytics_workspace_id` | the existing workspace (required and checked when not made, the module's message): the linked service's and Sentinel's `owner.armId`, the solutions' `workspaceResourceReference`, the rules' destination; solutions take its name from the ID |
| `log_analytics_workspace_sku`, `..._reservation_capacity_in_gb_per_day` | `sku.name`, `sku.capacityReservationLevel` |
| `log_analytics_workspace_retention_in_days` | `retentionInDays` |
| `log_analytics_workspace_daily_quota_gb` | `workspaceCapping.dailyQuotaGb` |
| `log_analytics_workspace_internet_ingestion_enabled`, `..._internet_query_enabled` | `publicNetworkAccessForIngestion`, `publicNetworkAccessForQuery` (`Enabled`, `Disabled`) |
| `log_analytics_workspace_local_authentication_enabled` | `features.disableLocalAuth` (its negation) |
| `log_analytics_workspace_allow_resource_only_permissions` | `features.enableLogAccessUsingOnlyResourcePermissions` |
| `log_analytics_workspace_cmk_for_query_forced` | `forceCmkForQuery` |
| `linked_automation_account_creation_enabled` | whether the `AutomationAccount` and the linked service are rendered |
| `automation_account_name` (required, as in the module) | the account's `azureName` (6 to 50 characters, checked) |
| `automation_account_location` | `location` (default `location`) |
| `automation_account_sku_name` | `sku.name` (`Basic`, `Free`) |
| `automation_account_local_authentication_enabled` | `disableLocalAuth` (its negation) |
| `automation_account_public_network_access_enabled` | `publicNetworkAccess` |
| `automation_account_encryption` | `encryption`: `keySource: Microsoft.Keyvault`, `key_vault_key_id` parsed as azurerm parses it into `keyVaultProperties` (`keyvaultUri`, `keyName`, `keyVersion` when given), `user_assigned_identity_id` as `identity.userAssignedIdentity` |
| `automation_account_identity` | `identity` (`type`, `userAssignedIdentities` by `armId`) |
| `log_analytics_solution_plans` | `product` (`plan.product`, its last segment the solution's name), `publisher` (`plan.publisher`, default `Microsoft`); location `location`; an entry listed twice is refused, as Terraform's `for_each` refuses a duplicate key |
| `sentinel_onboarding` | null: nothing; an object (`{}` for the defaults): `name` (`azureName`, default `default`), `customer_managed_key_enabled` (`customerManagedKey`, default false) |
| `user_assigned_managed_identities` | `ama`: `enabled`, `name`, `location` (default `location`), `tags` (default `tags`; the identity's own replace them, as in the module) |
| `data_collection_rules` | `change_tracking`, `vm_insights`, `defender_sql`: `enabled`, `name`, `location` (default `location`), `tags` (default `tags`, replaced by the rule's own); `defender_sql`'s `enable_collection_of_sql_queries_for_security_research` |
| `enable_telemetry` | accepted; the chart sends no telemetry |

### Not module inputs

| Value | Renders |
| --- | --- |
| `subscription_id` | the subscription of `resource_group_name` when that is a name: the module's providers know their subscription, ASO's owner is a resource ID |
| `names.resourceGroup`, `names.workspace`, `names.automationAccount` | those names in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of every name the chart gives (the group, workspace, Automation account, rules and identity), never of a name under `names`; the solutions take the workspace's name |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused |

### Refused when set

| Variable | Kind | Why |
| --- | --- | --- |
| `timeouts` | by-design | ASO has no per-request timeouts; Bundt sets a component's time limit |

## Outputs

| Output | From |
| --- | --- |
| `automation_account` | `{dsc_server_endpoint, hybrid_service_url, id, name, identity: {tenant_id, principal_id}}` from the account's status; all null without the account. `dsc_server_endpoint` is derived from `status.automationHybridServiceUrl` (`.jrds.` becomes `.agentsvc.`, `/automationAccounts/` becomes `/accounts/`), the endpoint azurerm reads from the account's `agentRegistrationInformation`; aso-extensions' `AutomationAccount` can export it to a ConfigMap (`operatorSpec.configMaps.dscServerEndpoint`), which outputs do not read |
| `data_collection_rule_ids` | `{<rule>: {id}}` from each rule's `status.id` |
| `log_analytics_workspace` | `{id, name, workspace_id}` (`status.id`, `azureName`, `status.customerId`); null fields with an existing workspace, as in the module |
| `resource_group` | `{id, name}`: the made group's, or the existing group's from the inputs |
| `resource_id` | the made workspace's `status.id` (null with an existing workspace) |
| `user_assigned_identity_ids` | `{ama: {id}}` from the identity's `status.id` |

Not outputs: `automation_account_dsc_keys` and
`log_analytics_workspace_keys` (secret values, sensitive in the module,
which do not belong in a component's outputs).

## From Terraform

A module block's arguments are the values, plus `subscription_id` when
`resource_group_name` is a name. ASO adopts resources that exist when an
object with their name is applied, so keep the names and leave
`namePrefix` empty; set `deletion_policy: ABANDON` for the first apply,
`terraform state rm` the module, then remove `ABANDON`. A Sentinel
onboarding the module made with the deprecated `SecurityInsights` solution
plan is not adopted: list it in neither.

## Upstream

Ported from the Azure Verified Module
[`avm-ptn-alz-management`](https://github.com/Azure/terraform-azurerm-avm-ptn-alz-management/tree/v0.10.0)
at v0.10.0 (`3026684f`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-ptn-alz-management`: render cases `basic` (the
module's defaults), `full` (every input, the group by ID), `byo` (an
existing group and workspace, the module's `bring_your_own_law`), `names`
and `mock`, each validated against ASO v2.22.0's CRD schemas and the
aso-extensions CRDs it renders (`crds/aso-extensions`), and the refusals
in `tests/*.fail.yaml`.

**Fake cloud** (`tests/mock.values.yaml`: a resource group of its own
made by the chart, the workspace, the Automation account linked to it, the
VM insights solution, Sentinel onboarding, the three rules and the AMA
identity), stock ASO and aso-extensions' manager at `b9beb5b` against
aso-extensions' fakearm, offload run `off-catalog-1113080555-1354` on
2026-11-13: 10 objects Ready and deleted, outputs evaluated. Again with
aso-extensions `3d9ba27`, run `off-catalog-1113155314-18721`: 10 objects Ready and deleted, the
outputs evaluated, `automation_account.dsc_server_endpoint` derived from
the fake's hybrid service URL
(`https://<id>.agentsvc.eastus2.azure-automation.net/accounts/<id>`).

**Live** (`task test-live-azure`, case `alz`), in the sandbox resource
group with `resource_group_creation_enabled: false` (the live identity
cannot make a resource group): the workspace (PerGB2018, 30 days, the
smallest retention it takes), a Basic Automation account linked to it, the
VM insights rule (the other two off) and the AMA identity. Run
`cat11130835bf36` (offload `off-catalog-1113083141-27307`, 2026-11-13): 5
objects Ready, outputs evaluated (the account's hybrid service URL and the
workspace's customer ID among them), deleted, Azure answering 404, nothing
left. Not applied live:

- the solutions: the sandbox subscription has not registered
  `Microsoft.OperationsManagement`, and registering a provider is a
  subscription-scope action the identity may not take. Run
  `cat111308090228` (offload `off-catalog-1113080555-31338`) applied the
  VM insights solution and Azure refused it: `403 AuthorizationFailed`,
  "does not have authorization to perform action
  'Microsoft.OperationsManagement/register/action' over scope
  '/subscriptions/...'"; nothing was made (that run's other objects
  became Ready and were deleted; the run then stopped on a bug in
  `hack/azure-live.sh`'s report, fixed here);
- Sentinel onboarding: it turns a paid SIEM on for the workspace;
- the resource group (subscription scope).

## Changes

- **0.2.0** (2026-11-13): `automation_account.dsc_server_endpoint` is
  derived from the account's hybrid service URL instead of null.
- **0.1.0** (2026-11-13): the port.
