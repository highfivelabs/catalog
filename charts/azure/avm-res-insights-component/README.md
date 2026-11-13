# avm-res-insights-component

A workspace-based Application Insights component with its pricing plan
(daily cap), its Azure Monitor private link scope connections, and its
lock, role assignments and diagnostic settings, as Azure Service Operator
(ASO) objects. A port of the Azure Verified Module
[`avm-res-insights-component`](https://github.com/Azure/terraform-azurerm-avm-res-insights-component/tree/8c75ae7771d672228595c19cefa6c216a8955d49)
at v0.5.0 (`8c75ae77`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-insights-component`
(`package.yaml`). Checked against ASO v2.22.0's CRDs and aso-extensions'
copied CRDs.

## Example

```yaml
name: appi-shop
location: eastus2
parent_id: /subscriptions/<id>/resourceGroups/rg-shop
workspace_id: /subscriptions/<id>/resourceGroups/rg-mon/providers/Microsoft.OperationalInsights/workspaces/law
daily_data_cap_in_gb: 1
retention_in_days: 30
```

renders the ASO `Component` `appi-shop` and its `PricingPlan`
(`tests/golden/mock.yaml` is the same shape). Applications take the
`connection_string` output.

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.this` (`Microsoft.Insights/components`) | always | `Component` (`insights.azure.com/v1api20200202`), `component`, owned by `parent_id` |
| `azapi_update_resource.pricing_plan` (`components/pricingPlans`, `current`) | always | `PricingPlan` (`insights.azure.com/v1api20171001`), `pricing_plan`, owned by the component: `cap`, `stopSendNotificationWhenHitCap`, and `planType: Basic` (the plan Azure makes; the module's update keeps it, ASO sends the whole body) |
| `azapi_resource.monitor_private_link_scope` | one per entry | `PrivateLinkScopesScopedResource` (aso-extensions, `insights.azure.hfl.dev/v20210901`), `monitor_private_link_scope:<key>`, owned by the scope, linking the component |
| `azapi_resource.linked_storage_account` | never | refused: no kind |
| `azapi_resource.lock` | `lock` set | `ManagementLock` (aso-extensions), `lock` (default name `lock-<name>`) |
| `azapi_resource.role_assignment` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `azapi_resource.diagnostic_settings` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>`; default name `diag-<name>`, and `allLogs` and `AllMetrics` when neither `logs` nor `metrics` is given, as the module's locals |
| telemetry | never | not ported |

## Values

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`). Refused when set, naming the gap:
`linked_storage_account` (`Microsoft.Insights/components/linkedStorageAccounts`
has no ASO or aso-extensions kind), `ignore_body_changes` (ASO cannot leave
a path to another writer), `resource_types`, `retry` and `timeouts` (ASO's
mechanics; Bundt sets a component's time limit). Accepted in part:
`application_type` `web` and `other` (ASO's `Component` enumerates no
other), and `monitor_private_link_scope` with kind `Resource` (the
aso-extensions kind's API, 2021-09-01, has no `kind` or
`subscriptionLocation`).

## Outputs

`package.yaml`: `resource_id`, `app_id`, `connection_string` and
`instrumentation_key` (ASO's status of the component) and `name`. The
module's deprecated `resource` is not an output.

## Names, labels and tags

`names.component` sets the component's name in full; otherwise
`namePrefix` goes in front of `name`. `labels` stay in Kubernetes; `tags`
are the component's Azure tags. `deletion_policy: ABANDON` keeps every
resource in Azure when the component is deleted.

## Tests

`tests/*.values.yaml` render to `tests/golden/` and pass `kubeconform
-strict`; `tests/*.fail.yaml` must be refused with the message on their
first line. `tests/mock.values.yaml` is applied to aso-extensions' fake
cloud (`task test-mock-azure`), and the `appi` case of `hack/azure-live.sh`
(with a workspace it makes) to the Azure sandbox (`docs/azure.md`,
"8. Charts", Testing).
