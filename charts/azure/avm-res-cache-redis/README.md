# avm-res-cache-redis

An Azure Cache for Redis with its access policies, access policy
assignments, firewall rules, linked servers, patch schedule and private
endpoints, and its lock, role assignments and diagnostic settings, as Azure
Service Operator (ASO) objects. A port of the Azure Verified Module
[`avm-res-cache-redis`](https://github.com/Azure/terraform-azurerm-avm-res-cache-redis/tree/7469021fb795f8ee3dce2ed2dba2f41b91c4785c)
at v0.5.0 (`7469021f`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-cache-redis`
(`package.yaml`). Checked against ASO v2.22.0's CRDs (`cache.azure.com`
at ARM API 2024-11-01).

## Example

```yaml
name: redis-orders
location: eastus2
resource_group_name: rg-data
subscription_id: <id>
sku_name: Basic
capacity: 0
zones: []
cache_firewall_rules:
  office: {name: office, start_ip: 203.0.113.10, end_ip: 203.0.113.10}
```

renders the ASO `Redis` `redis-orders` (Basic C0, no zones) and its
`RedisFirewallRule` `office`.

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azurerm_redis_cache.this` | always | `Redis` (`cache.azure.com/v20241101`), `cache`, owned by the resource group |
| its `patch_schedule` blocks | `patch_schedule` not empty | one `RedisPatchSchedule` (Azure's `patchSchedules/default`), `patch_schedule` |
| `azurerm_redis_cache_access_policy.this` | one per `cache_access_policies` entry | `RedisAccessPolicy`, `access_policy:<key>` |
| `azurerm_redis_cache_access_policy_assignment.this` | one per `cache_access_policy_assignments` entry | `RedisAccessPolicyAssignment`, `access_policy_assignment:<key>` |
| `azurerm_redis_firewall_rule.this` | one per `cache_firewall_rules` entry | `RedisFirewallRule`, `firewall_rule:<key>` |
| `azurerm_redis_linked_server.this` | one per `linked_redis_caches` entry | `RedisLinkedServer` (named by the linked cache's name, as azurerm names it), `linked_redis_cache:<key>` |
| `azurerm_private_endpoint.this_managed_dns_zone_groups` / `this_unmanaged_dns_zone_groups` | one per `private_endpoints` entry | `PrivateEndpoint` (`network.azure.com/v20250301`), `private_endpoint:<key>`; a `PrivateEndpointsPrivateDnsZoneGroup` (`private_endpoint:<key>/dns_zone_group`) when `private_endpoints_manage_dns_zone_group` and zones are given |
| `azurerm_private_endpoint_application_security_group_association.this` | one per association | the endpoint's `applicationSecurityGroups` |
| `azurerm_role_assignment.private_endpoints`, `azurerm_management_lock.private_endpoints` | per endpoint entry | `RoleAssignment`, `ManagementLock` on the endpoint |
| `azurerm_management_lock.this` | `lock` set | `ManagementLock` (aso-extensions), `lock` |
| `azurerm_role_assignment.this` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `azurerm_monitor_diagnostic_setting.this` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` |
| `data.azapi_resource.this` | never | ASO's status carries the identity the module reads it for |
| telemetry | never | not ported |

Every child is owned by the cache (ASO `owner`), so ASO creates it after
the cache is ready and the cache's ARM ID is never needed.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`), so a module block's arguments
convert one to one: 31 of 31 variables, one of them
(`redis_configuration`) accepted in part. How the cache's map onto
`Redis`:

| Variable | ASO field |
| --- | --- |
| `sku_name`, `capacity` | `sku.name`, `sku.capacity`, and `sku.family` from the SKU (`C` for Basic and Standard, `P` for Premium), as the module derives it |
| `access_keys_authentication_enabled` | `disableAccessKeyAuthentication` (its negation) |
| `enable_non_ssl_port`, `minimum_tls_version` | `enableNonSslPort`, `minimumTlsVersion` |
| `public_network_access_enabled` | `publicNetworkAccess` (`Enabled`, `Disabled`) |
| `managed_identities` | `identity` (`SystemAssigned, UserAssigned` with both) |
| `redis_configuration` | `redisConfiguration`: each value set, as the string Azure takes (`aad-enabled`, `aof-backup-enabled`, `maxmemory-*`, `maxfragmentationmemory-reserved`, `preferred-data-persistence-auth-method`, `rdb-backup-*`, `storage-subscription-id`, `notify-keyspace-events`); `enable_authentication: false` is `authnotrequired: "true"` |
| `redis_version` | `redisVersion` (a string) |
| `replicas_per_master`, `replicas_per_primary`, `shard_count` | `replicasPerMaster`, `replicasPerPrimary`, `shardCount` |
| `subnet_resource_id`, `private_static_ip_address` | `subnetReference.armId`, `staticIP` |
| `tenant_settings`, `zones`, `tags` | `tenantSettings`, `zones`, `tags` |
| `patch_schedule` | a `RedisPatchSchedule`'s `scheduleEntries`, with the module's defaults (Saturday, `PT5H`, hour 0) |

Not as in the module:

- **No storage connection strings.** `redis_configuration`'s
  `aof_storage_connection_string_0`, `aof_storage_connection_string_1`
  and `rdb_storage_connection_string` are refused (by design): a storage
  connection string carries the account's key, a secret value, which does
  not belong in a component's inputs (the builder's decision); ASO's
  `redisConfiguration` takes them only as plain strings. So AOF and RDB
  persistence to storage cannot be configured through the chart.
- **No secret outputs.** The module's sensitive `resource` output (the
  whole `azurerm_redis_cache`, with its access keys and connection
  strings) is not an output, and the chart sets none of ASO's
  `operatorSpec.secrets`: no access key leaves Azure.
- **Diagnostic settings** never send `log_analytics_destination_type`: the
  module hard-sets it to null, so an entry's value is accepted and not
  sent.
- **A private endpoint's `location`** is accepted and not used: the module
  places every endpoint in the cache's location. Its IP configurations'
  `member_name` defaults as the module's two endpoint resources do
  (`Azure redis cache` when the module manages the DNS zone group,
  `redisCache` when not).
- **`capacity`** is checked against the SKU (0 to 6 for Basic and
  Standard, 1 to 5 for Premium), as the module's description says.
- **`zones`** defaults to the module's `["1", "2", "3"]`; a Basic cache
  takes none, so set `zones: []` (or null) for one, as the module's basic
  example does.

## Outputs

`package.yaml`: `name` and `resource_id` (the cache's Azure name and ARM
ID), `system_assigned_mi_principal_id` (`""` without a system-assigned
identity, as the module's) and `private_endpoints` (each endpoint's ID,
keyed like the value; the module gives the whole azurerm object): 4 of the
module's 5 outputs. `resource` is not one (above).

## Names, labels and tags

As every Azure chart (`docs/azure.md`, "8. Charts"): `names.redisCache`
sets the cache's name in full; otherwise `namePrefix` goes in front of the
cache's name and of each private endpoint's name. `labels` stay in
Kubernetes; `tags` are the cache's Azure tags (a private endpoint takes
its entry's `tags`, as in the module). `deletion_policy: ABANDON` keeps
every resource in Azure when the component is deleted.

## Tests

`tests/*.values.yaml` render to `tests/golden/` and pass `kubeconform
-strict`; `tests/*.fail.yaml` must be refused with the message on their
first line. `tests/mock.values.yaml` is applied to aso-extensions' fake
cloud (`task test-mock-azure`), and the `redis` case of
`hack/azure-live.sh` to the Azure sandbox (`docs/azure.md`, "8. Charts",
Testing).

**Fake cloud** (2026-11-13, stock ASO v2.22.0 and aso-extensions' manager
against fakearm at `b9beb5b`, `cache.azure.com/*` added to
`hack/azure-mock.sh`'s CRD pattern, offload run
`off-catalog-1113075628-30638`): the Premium cache with a system-assigned
identity, its patch schedule, access policy, access policy assignment and
firewall rule, 5 objects, all Ready and deleted; outputs evaluated (the
identity's principal ID among them).

**Live: not applied.** The `redis` case (Basic C0, zoneless, about 0.02
USD an hour, one firewall rule for 203.0.113.10; a 45-minute limit) ran
in run `cat11130800eaa5` (offload `off-catalog-1113075628-15559`) on
2026-11-13, and Azure refused it before anything was made: the sandbox
subscription has not registered the `Microsoft.Cache` provider, and ASO's
attempt to register it (`POST
/subscriptions/<id>/providers/Microsoft.Cache/register`) is a
subscription-scope action the live identity is refused (403
`AuthorizationFailed`). The cache never became Ready (its firewall rule
waited for it), so no output was read from Azure. The case is out of the
default set until someone with subscription rights runs `az provider
register --namespace Microsoft.Cache --subscription <sandbox>`; then run
it with `AZURE_LIVE_CASES=redis`. Whether a Basic cache takes a firewall
rule is therefore not yet checked live. The same run found that
`hack/azure-live.sh` stopped before its summary rows for a case with
nothing applied first (its `pre-live.json` missing under `pipefail`);
that is fixed.
