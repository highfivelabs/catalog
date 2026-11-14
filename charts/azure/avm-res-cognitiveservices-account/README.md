# avm-res-cognitiveservices-account

An Azure AI services (Cognitive Services) account with its model
deployments, RAI policies, private endpoints, lock, role assignments and
diagnostic settings, as Azure Service Operator (ASO) objects, with
aso-extensions' `AccountsRaiPolicy` for the RAI policies ASO lacks. A port
of the Azure Verified Module
[`avm-res-cognitiveservices-account`](https://github.com/Azure/terraform-azurerm-avm-res-cognitiveservices-account/tree/02ac1c992bbadd4286d36171cfd43792a513c375)
at v0.11.1 (`02ac1c99`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-cognitiveservices-account`
(`package.yaml`). Checked against ASO v2.22.0's CRDs and aso-extensions'.

## Example

```yaml
name: cog-example
location: eastus2
parent_id: /subscriptions/<id>/resourceGroups/rg-example
kind: TextAnalytics
sku_name: F0
```

renders a free Language `Account` `cog-example` with the custom subdomain
`azure-cognitive-<5 characters of the account ID's SHA-256>`
(`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.this` (`Microsoft.CognitiveServices/accounts@2025-06-01`) | `kind` other than AIServices | `Account` (`cognitiveservices.azure.com/v20250601`), `account`, owned by `parent_id` |
| `azapi_resource.ai_service` | `kind: AIServices` | the same `Account`, with the AIServices body (AML workspace, network injection, RAI monitor, projects; no API properties) |
| `azurerm_cognitive_account_customer_managed_key.this`, `azapi_update_resource.ai_service_hsm_key` | `customer_managed_key` set | the account's `encryption` (a managed HSM key on AIServices only, as the module does) |
| `module.deployment` (`accounts/deployments`) | one per `cognitive_deployments` entry | `Deployment` (`v20250601`), `deployment:<key>`, owned by the account |
| `module.rai_policy` (`accounts/raiPolicies`) | one per `rai_policies` entry | `AccountsRaiPolicy` (`cognitiveservices.azure.hfl.dev/v20250601`, aso-extensions), `rai_policy:<key>` |
| `azapi_resource.private_endpoints` (or `_unmanaged`) | one per `private_endpoints` entry | `PrivateEndpoint` (`network.azure.com/v20250301`), `private_endpoint:<key>`, to the account's `account` subresource |
| `azapi_resource.private_dns_zone_groups` | `private_endpoints_manage_dns_zone_group` and the entry has zones | `PrivateEndpointsPrivateDnsZoneGroup`, `private_endpoint:<key>/dns_zone_group` |
| `azapi_resource.private_endpoint_locks`, `.private_endpoint_role_assignments` | per entry | `ManagementLock` (aso-extensions), `RoleAssignment`, `private_endpoint:<key>/lock`, `private_endpoint:<key>/role-assignment-<key>` |
| `azurerm_management_lock.this` | `lock` set | `ManagementLock`, `lock` |
| `azurerm_role_assignment.this` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `azurerm_monitor_diagnostic_setting.this` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` |
| `random_string.default_custom_subdomain_name_suffix` | never | a stable suffix instead: the first 5 hex characters of the SHA-256 of the account's ID |
| `data.azapi_resource_action.account_keys`, `.ai_service_account_keys` | never | not ported: the keys are secrets, not outputs |
| `data.azurerm_key_vault_key`, `data.azurerm_user_assigned_identity`, the managed HSM data sources, `data.azapi_resource.existing_private_endpoints` | never | not needed, or replaced by values (`key_version`; `network_interface_name`) |
| `time_sleep`s, telemetry | never | not ported (ASO waits on its own) |

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`), and the module's validations and
preconditions stop the render with its messages.

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required), `kind` (required), `sku_name` (required) | `azureName`, `location`, `kind`, `sku.name` |
| `parent_id` (required) | `owner.armId`, a resource group's ID |
| `custom_subdomain_name` | `customSubDomainName`; unset, `azure-cognitive-<suffix>` for every kind but AIServices, as the module (its suffix is random; the chart's is stable) |
| `allow_project_management`, `dynamic_throttling_enabled`, `fqdns`, `public_network_access_enabled`, `outbound_network_access_restricted`, `local_auth_enabled` | `allowProjectManagement`, `dynamicThrottlingEnabled`, `allowedFqdnList`, `publicNetworkAccess`, `restrictOutboundNetworkAccess`, `disableLocalAuth` (its negation; false when null) |
| `qna_runtime_endpoint`, `custom_question_answering_search_service_id`, `metrics_advisor_*` | `apiProperties` (`qnaRuntimeEndpoint`, `qnaAzureSearchEndpointId`, `aadClientId`, `aadTenantId`, `superUser`, `websiteName`), each only for its kind, as the module sends them |
| `custom_question_answering_search_service_key` | `apiProperties.qnaAzureSearchEndpointKey` (`TextAnalytics` only, as in the module), as a reference to a Kubernetes Secret, `{secretName, key}` ([secrets](../../../docs/secrets.md)); a string is refused |
| `network_acls` | `networkAcls`: `defaultAction`, `ipRules`, `virtualNetworkRules` (subnets by ID), `bypass` |
| `storage` | `userOwnedStorage` |
| `managed_identities` | `identity` (system-assigned, user-assigned by ID, or both) |
| `aml_workspace`, `network_injections`, `rai_monitor_config`, `associated_projects`, `default_project` | `amlWorkspace`, `networkInjections`, `raiMonitorConfig`, `associatedProjects`, `defaultProject` (AIServices only, as the module sends them) |
| `customer_managed_key`, `is_hsm_key` | `encryption`: `Microsoft.KeyVault`, the key's name, version and its vault's or managed HSM's URI (`https://<name>.vault.azure.net/`, `https://<name>.managedhsm.azure.net/`, Azure's public cloud). `key_version` is required (the module reads the current version from Key Vault); `user_assigned_identity` is refused (see below) |
| `cognitive_deployments` | `Deployment`s: `model`, `raiPolicyName`, `versionUpgradeOption`, `sku` (`scale.type` as its name, `capacity` (1), `family`, `size`, `tier`) |
| `deployment_serialization_enabled` | accepted, no effect: ASO retries a deployment Azure refuses while another of the account's runs |
| `rai_policies` | `AccountsRaiPolicy`s: `basePolicyName`, `mode`, `contentFilters`, `customBlocklists` |
| `private_endpoints`, `private_endpoints_manage_dns_zone_group` | the endpoints, as avm-utl-interfaces 0.6.0 builds them: default names `pep-account-<uuidv5 of the account's ID>`, `nic-...`, `pcon-...` (`nic-account--<name>` and `pcon-account-<name>` for a named entry), the account by Kubernetes name, `resource_group_name` and `location` per entry, the zone group's configs each named the group's name, as the interfaces module names them |
| `tags` | `spec.tags` of the account (an endpoint takes its entry's `tags`) |
| `lock`, `role_assignments`, `diagnostic_settings` | the AVM interfaces; a diagnostic setting without a name is `diag-<name>` |
| `enable_telemetry` | accepted; the chart sends no telemetry |

**Refused** (`upstream.yaml`): `retry` and `timeouts` (by design: ASO
retries on its own; Bundt sets a component's time limit), at the top and in
deployment and RAI policy entries;
`customer_managed_key.user_assigned_identity` (the module reads the
identity's client ID from Azure; ASO's `encryption.keyVaultProperties.identityClientId`
is a literal, with no `FromConfig` form); a deployment's
`dynamic_throttling_enabled: true` (ASO's `Deployment` has no such field;
false, the default, is Azure's default).

Not ported, and differing from the module: a private endpoint entry with
no zones gets no zone group (the module makes an empty one).

### Not module inputs

| Value | Renders |
| --- | --- |
| `names.account` | the account's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name`, never of a name under `names`; checked against the 64-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

## Outputs

| Output | From |
| --- | --- |
| `name` | the account's `azureName` |
| `resource_id` | the account's `status.id` |
| `endpoint` | the account's `status.properties.endpoint` |
| `system_assigned_mi_principal_id` | the account's `status.identity.principalId` when `managed_identities.system_assigned`, else null |
| `rai_policy_id` | each RAI policy's `status.id`, by key |
| `resource_cognitive_deployment` | each deployment's `status.id`, by key (the module's whole objects; the ID is the field consumers take) |
| `private_endpoints` | each endpoint's `status.id`, by key (the module's whole objects) |

Not outputs: `resource` (the whole account), and `primary_access_key`,
`secondary_access_key` and `resource_sensitive` (secret values).

## From Terraform

A module block's arguments are the values. Set `custom_subdomain_name` to
the account's current subdomain (the module's default suffix is random),
and set `customer_managed_key.key_version` to the version in use. ASO
adopts an account, deployment or endpoint that exists when an object with
its name is applied, so keep the names and leave `namePrefix` empty; set
`deletion_policy: ABANDON` for the first apply, `terraform state rm` the
module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-cognitiveservices-account`](https://github.com/Azure/terraform-azurerm-avm-res-cognitiveservices-account/tree/v0.11.1)
at v0.11.1 (`02ac1c99`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-cognitiveservices-account`: render cases `basic`,
`full`, `aiservices`, `metrics`, `names`, `search` (the Search service's
key from a Secret), `mock` and `mock-search` (the key from a Secret the
fake-cloud run makes), each validated against
ASO v2.22.0's CRD schemas and aso-extensions' `ManagementLock` and
`AccountsRaiPolicy` CRDs, and the refusals in `tests/*.fail.yaml`.
`task test-live-azure` with `AZURE_LIVE_CASES=cog` applies a free
Language account with a system-assigned identity and no deployments to the
Azure sandbox with Azure Service Operator, evaluates the outputs, deletes
it, checks Azure no longer has it and tries to purge the soft-deleted
account. It has not passed yet: the sandbox subscription has not
registered `Microsoft.CognitiveServices`, and the live identity may not
register it (run `cat11130328999c`, 2026-11-13; docs/azure.md, section 18).
`task test-mock-azure` applies `tests/mock.values.yaml` to aso-extensions'
fake cloud: passed on 2026-11-13, the account, its deployment and RAI
policy Ready and deleted, the outputs evaluated.

## Changes

- **0.2.0** (2026-11-14): `custom_question_answering_search_service_key`
  is mapped, as a reference to a Kubernetes Secret, `{secretName, key}`
  (docs/secrets.md, the builder's decision).
- **0.1.0** (2026-11-13): the port.
