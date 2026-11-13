# avm-res-containerregistry-registry

An Azure container registry with its geo-replications, cache rules,
credential sets, scope maps and tokens, and its lock, role assignments and diagnostic settings, as Azure Service
Operator (ASO) objects. A port of the Azure Verified Module
[`avm-res-containerregistry-registry`](https://github.com/Azure/terraform-azurerm-avm-res-containerregistry-registry/tree/7f2dc78bb5dbfc6e05809963410be844006f9490)
at v0.9.0 (`7f2dc78b`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-containerregistry-registry`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

## Example

```yaml
name: acrexample001
location: eastus2
resource_group_name: rg-example
subscription_id: <id>
```

renders the ASO `Registry` `acrexample001` with the module's defaults:
Premium, zone-redundant, 7-day retention of untagged manifests, export
policy on, admin user off (`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azurerm_container_registry.this` | always | `Registry` (`containerregistry.azure.com/v20251101`), `registry`, owned by the resource group |
| its `georeplications` blocks | one per entry | `RegistryReplication`, `georeplication:<location>`, named for its location (as azurerm names it), owned by the registry |
| `module.cache_rule` (`registries/cacheRules`) | one per `cache_rules` entry | `RegistryCacheRule`, `cache_rule:<key>`, owned by the registry |
| `module.credential_set` (`registries/credentialSets`) | one per `credential_sets` entry | `RegistriesCredentialSet` (aso-extensions, `containerregistry.azure.hfl.dev/v20251101`), `credential_set:<key>`, owned by the registry, with a system-assigned identity as the module gives it |
| `module.scope_maps`: `azurerm_container_registry_scope_map` | one per `scope_maps` entry | `RegistriesScopeMap` (aso-extensions), `scope_map:<key>`, owned by the registry |
| `module.scope_maps`: `azurerm_container_registry_token` | one per `registry_tokens` entry | `RegistriesToken` (aso-extensions), `scope_map:<key>:token:<key>`, owned by the registry, its `scopeMapReference` the scope map's object |
| `azurerm_management_lock.this` | `lock` set | `ManagementLock` (aso-extensions), `lock` |
| `azurerm_role_assignment.this` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `azurerm_monitor_diagnostic_setting.this` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` |
| a token's passwords (`azurerm_container_registry_token_password`), the customer-managed key, private endpoints | when set | refused (below) |
| telemetry | never | not ported |

ASO v2.22.0 carries the registry at ARM API version 2025-11-01, the
version of the module's cache rules, so every registry property the module
sets has a field (`docs/azure.md` section 3 listed it as unreleased).

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`).

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` |
| `resource_group_name` (required) | `owner.armId`: `/subscriptions/<subscription_id>/resourceGroups/<resource_group_name>`, or `resource_group_name` itself when it is a resource group's ID |
| `sku` | `sku.name` |
| `admin_enabled`, `anonymous_pull_enabled`, `data_endpoint_enabled` | `adminUserEnabled`, `anonymousPullEnabled`, `dataEndpointEnabled` |
| `public_network_access_enabled` | `publicNetworkAccess` |
| `network_rule_bypass_option`, `network_rule_bypass_for_tasks_enabled` | `networkRuleBypassOptions`, `networkRuleBypassAllowedForTasks` |
| `network_rule_set` | `networkRuleSet` (`defaultAction`, `ipRules`) |
| `azuread_authentication_as_arm_policy_enabled`, `export_policy_enabled`, `quarantine_policy_enabled`, `enable_trust_policy` | `policies.azureADAuthenticationAsArmPolicy`, `exportPolicy`, `quarantinePolicy`, `trustPolicy` (Notary) |
| `retention_policy_in_days` | `policies.retentionPolicy` on Premium (null disables it), as azurerm sends it; not sent below Premium |
| `zone_redundancy_enabled` | `zoneRedundancy`, `Disabled` below Premium |
| `role_assignment_mode` | `roleAssignmentMode` |
| `managed_identities` | `identity` (`SystemAssigned`, `UserAssigned` or both; identities by `armId`) |
| `georeplications` | one replication each: `location` (its name too), `regional_endpoint_enabled` (`regionEndpointEnabled`), `zone_redundancy_enabled`, `tags` |
| `cache_rules` | one cache rule each: `name`, `source_repository`, `target_repository`; `credential_set_key` or `credential_set_resource_id` as `credentialSetResourceReference.armId` (a key's set by the ARM ID it will have, computed from the registry's: ASO cannot reference an aso-extensions object by name, and retries until the set exists) |
| `credential_sets` | one credential set each: `name` (`azureName`), `login_server`, `auth_credentials` (`name`, default `Credential1`; the Key Vault secret URIs, not their values); `identity` `SystemAssigned` |
| `scope_maps` | one scope map each: `name`, `actions`, `description`; one token per `registry_tokens` entry: `name`, `enabled` (`status` `enabled` or `disabled`); `passwords` is refused |
| `tags` | `spec.tags` of the registry |
| `lock` | the AVM lock interface, named `lock-<name>` unless named, with the module's notes |
| `role_assignments` | the AVM interface; `skip_service_principal_aad_check` without a `principal_type` sends `ServicePrincipal`, as azurerm does |
| `diagnostic_settings` | the AVM interface, `Dedicated` left to Azure as the module sends it; a setting without a name is `diag-<name>` |
| `private_endpoints_inherit_lock`, `private_endpoints_manage_dns_zone_group` | accepted: they shape private endpoints, which are refused |
| `enable_telemetry` | accepted; the chart sends no telemetry |

Azure refuses a cache rule from Docker Hub without credentials ("Cannot
create cache rule with source repository Docker without credentials",
found live): such a rule needs a credential set (`credential_set_key`, or
`credential_set_resource_id` for a set made elsewhere) whose identity can
read the Key Vault secrets; an anonymous source such as
`mcr.microsoft.com` needs none.

The module's preconditions and validations stop the render with its
messages: Premium for zone redundancy and a network rule set, one of a
cache rule's credential set inputs, and credential set names unique
ignoring case; a `credential_set_key` that is not a key of
`credential_sets` stops it too.

### Not module inputs

| Value | Renders |
| --- | --- |
| `subscription_id` | the subscription of `resource_group_name` when that is a name: the module's azurerm provider knows its subscription, ASO's owner is a resource ID |
| `names.registry` | the registry's name in full, used as given |
| `namePrefix` | an optional convenience: the namePrefix without its hyphens in front of `name` (a registry name is letters and digits), never of a name under `names`; checked against the 50-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

### Refused when set

| Variable | Why |
| --- | --- |
| a token's `passwords` (`scope_maps.<key>.registry_tokens.<key>.passwords`) | secrets Azure generates and returns once (`generateCredentials`); whether a component may hold one is the builder's decision (not ported) |
| `customer_managed_key` | ASO's `Registry` takes the key's URI and the identity's client ID; the module looks both up from the vault's and the identity's IDs, which a render cannot (not ported) |
| `private_endpoints` | ASO has `PrivateEndpoint`; the chart does not map private endpoints yet (not ported) |
| `resource_types`, `retry`, `timeouts` | ASO's kinds fix the API versions; ASO retries itself; Bundt sets a component's time limit |

## Outputs

| Output | From |
| --- | --- |
| `name` | computed from the inputs, as the module sets it |
| `resource_id`, `login_server`, `data_endpoint_host_names` | the registry's `status.id`, `status.loginServer`, `status.dataEndpointHostNames` |
| `system_assigned_mi_principal_id`, `system_assigned_mi_tenant_id` | `status.identity.principalId`, `tenantId` (null without a system-assigned identity) |
| `cache_rules` | `{<key>: {name, resource_id}}`, as the module builds it |
| `credential_sets` | `{<key>: {name, resource_id, principal_id, tenant_id}}`: the set's system-assigned identity, to grant read on its Key Vault secrets |
| `scope_maps` | `{<key>: {name, resource_id, id, registry_tokens: {<key>: {name, id}}}}`: the scope-map submodule's outputs without the token passwords |

Not outputs: `admin_username` and `admin_password` (secrets; ASO can write
them to a Kubernetes Secret, which is not an output), a token's passwords
and `private_endpoints` (refused).

## From Terraform

A module block's arguments are the values, plus `subscription_id` when
`resource_group_name` is a name. ASO adopts a registry, replication or
cache rule that exists when an object with its name is applied (its images
are kept), so keep the name and leave `namePrefix` empty; set
`deletion_policy: ABANDON` for the first apply, `terraform state rm` the
module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-containerregistry-registry`](https://github.com/Azure/terraform-azurerm-avm-res-containerregistry-registry/tree/v0.9.0)
at v0.9.0 (`7f2dc78b`, MIT), its `cache-rule` submodule included.
[`upstream.yaml`](upstream.yaml) records the repository, release, commit,
licence and the date last synced.

## Tests

`task test CHART=avm-res-containerregistry-registry`: render cases
`basic`, `basic-sku`, `full`, `names` and `mock`, each validated against
ASO v2.22.0's CRD schemas and aso-extensions' `ManagementLock` CRD, and
the refusals in `tests/*.fail.yaml`. `task test-live-azure`
applies it to the Azure sandbox with Azure Service Operator, evaluates the
outputs, deletes it and checks Azure no longer has it: passed on
2026-11-12. `task test-mock-azure` applies its `tests/mock.values.yaml` to aso-extensions'
fake cloud with stock ASO (`docs/azure.md`, "8. Charts").

## Changes

- **0.1.0** (2026-11-12): the port.
