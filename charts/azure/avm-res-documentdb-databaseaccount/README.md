# avm-res-documentdb-databaseaccount

An Azure Cosmos DB account with its SQL (NoSQL) databases, containers,
stored procedures, triggers and functions, its MongoDB databases and
collections, its Gremlin databases and graphs, its SQL dedicated gateway
and private endpoints, and its lock, role assignments and diagnostic
settings, as Azure Service Operator (ASO) and aso-extensions objects. A
port of the Azure Verified Module
[`avm-res-documentdb-databaseaccount`](https://github.com/Azure/terraform-azurerm-avm-res-documentdb-databaseaccount/tree/9939de3a2e36161242f5140bcf0cd28e23a3e1f0)
at v0.12.0 (`9939de3a`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-documentdb-databaseaccount`
(`package.yaml`). Checked against ASO v2.22.0's CRDs and aso-extensions'
at `b9beb5b`.

## Example

```yaml
name: cosmos-orders
location: eastus2
resource_group_name: rg-data
subscription_id: <id>
capabilities: [{name: EnableServerless}]
geo_locations: [{location: eastus2, failover_priority: 0, zone_redundant: false}]
sql_databases:
  app:
    name: app
    containers:
      items: {name: items, partition_key_paths: [/tenant]}
```

renders the ASO `DatabaseAccount` `cosmos-orders` (serverless, SQL API,
Entra only, no public network access: the module's defaults), its
`SqlDatabase` `app` and its `SqlDatabaseContainer` `items`. Applications
reach the `endpoint` output with an Entra token and a Cosmos DB data-plane
role (a `SqlRoleAssignment`, which the module does not make).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azurerm_cosmosdb_account.this` | always | `DatabaseAccount` (`documentdb.azure.com/v1api20240815`), `account`, owned by the resource group |
| `azurerm_cosmosdb_sql_database.this` | one per `sql_databases` entry | `SqlDatabase`, `sql_database:<key>` |
| `azurerm_cosmosdb_sql_container.this` | one per container | `SqlDatabaseContainer`, `sql_container:<db key>/<key>` |
| `azurerm_cosmosdb_sql_function.this` | one per function | `SqlDatabaseContainerUserDefinedFunction`, `sql_function:<db key>/<container key>/<key>` |
| `azurerm_cosmosdb_sql_stored_procedure.this` | one per stored procedure | `SqlDatabaseContainerStoredProcedure`, `sql_stored_procedure:...` |
| `azurerm_cosmosdb_sql_trigger.this` | one per trigger | `SqlDatabaseContainerTrigger`, `sql_trigger:...` |
| `azurerm_cosmosdb_sql_dedicated_gateway.this` | `sql_dedicated_gateway` set and SQL databases given | `DatabaseAccountsService` (aso-extensions, `documentdb.azure.hfl.dev/v20240815`) named `SqlDedicatedGateway`, `sql_dedicated_gateway` |
| `azurerm_cosmosdb_mongo_database.this` | one per `mongo_databases` entry | `MongodbDatabase`, `mongo_database:<key>` |
| `azurerm_cosmosdb_mongo_collection.this` | one per collection | `MongodbDatabaseCollection`, `mongo_collection:<db key>/<key>` |
| `azurerm_cosmosdb_gremlin_database.this` | one per `gremlin_databases` entry | `DatabaseAccountsGremlinDatabase` (aso-extensions), `gremlin_database:<key>` |
| `azurerm_cosmosdb_gremlin_graph.this` | one per graph | `DatabaseAccountsGremlinDatabasesGraph` (aso-extensions), `gremlin_graph:<db key>/<key>` |
| `azurerm_private_endpoint.this_managed_dns_zone_groups` / `this_unmanaged_dns_zone_groups` | one per `private_endpoints` entry | `PrivateEndpoint` (`network.azure.com/v20250301`), `private_endpoint:<key>`; a `PrivateEndpointsPrivateDnsZoneGroup` (`private_endpoint:<key>/dns_zone_group`) when `private_endpoints_manage_dns_zone_group` and zones are given |
| `azurerm_private_endpoint_application_security_group_association.this` | one per association | the endpoint's `applicationSecurityGroups` |
| `azurerm_management_lock.this` | `lock` set; an endpoint's own `lock`, else the account's (kind `None` is none) | `ManagementLock` (aso-extensions), `lock`, `private_endpoint:<key>/lock` |
| `azurerm_role_assignment.this` | one per entry, the account's and each endpoint's | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>`, `private_endpoint:<key>/role-assignment-<key>` |
| `azurerm_monitor_diagnostic_setting.this` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` |
| `time_sleep.wait_180_seconds_for_destroy`, telemetry | never | not ported: ASO retries a delete Azure refuses while the account settles |

Every child is owned by its parent (ASO `owner`), so ASO creates it after
the parent is ready and no ARM ID is ever computed in the chart. The SQL
and MongoDB kinds are ASO's at the 2024-08-15 API; the Gremlin kinds and
the dedicated gateway (a `services` child) are aso-extensions', at the
same API version (ASO v2.22.0 has neither).

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`, with the module's validations), so a
module block's arguments convert one to one. All 38 are carried.

| Module input | ASO `DatabaseAccount` field |
| --- | --- |
| `name`, `location`, `tags` | `azureName`, `location`, `tags` |
| `resource_group_name` (+ `subscription_id`) | `owner.armId` |
| `backup` | `backupPolicy.continuous` (`tier`) or `backupPolicy.periodic` (`periodicModeProperties`), the module's defaults (`Continuous30Days`; 240 minutes, 8 hours, Geo) |
| `capabilities`, `capacity` | `capabilities`, `capacity.totalThroughputLimit` (default -1) |
| `consistency_policy` | `consistencyPolicy`; the staleness bounds only for `BoundedStaleness` (the module's default, 5 seconds and 100) |
| `cors_rule` | `cors[0]`, each list joined with commas as azurerm joins it |
| `customer_managed_key` | `keyVaultKeyUri` (`https://<vault>.vault.azure.net/keys/<key_name>`, as the module builds it) and `defaultIdentity: UserAssignedIdentity=<identity>`; `key_version` is ignored, as by the module. Without one, `defaultIdentity: FirstPartyIdentity`, azurerm's default |
| `managed_identities` | `identity` |
| `geo_locations` | `locations`, by failover priority; null is the account's location, zone redundant |
| `ip_range_filter` | `ipRules` |
| `virtual_network_rules` | `virtualNetworkRules` (`ignoreMissingVNetServiceEndpoint: false`) and `isVirtualNetworkFilterEnabled` |
| `network_acl_bypass_for_azure_services`, `network_acl_bypass_resource_ids` | `networkAclBypass`, `networkAclBypassResourceReferences` |
| `public_network_access_enabled`, `minimal_tls_version` | `publicNetworkAccess`, `minimalTlsVersion` |
| `access_key_metadata_writes_enabled` | `disableKeyBasedMetadataWriteAccess` (negated) |
| `local_authentication_disabled` | `disableLocalAuth`, false when there are MongoDB or Gremlin databases, as the module forces |
| `multiple_write_locations_enabled` | `enableMultipleWriteLocations`, only with a Periodic backup, as the module sends it |
| `analytical_storage_enabled`, `analytical_storage_config`, `automatic_failover_enabled`, `burst_capacity_enabled`, `free_tier_enabled`, `partition_merge_enabled` | `enableAnalyticalStorage`, `analyticalStorageConfiguration`, `enableAutomaticFailover`, `enableBurstCapacity`, `enableFreeTier`, `enablePartitionMerge` |
| `mongo_databases` (any), `mongo_server_version` | `kind: MongoDB` and `apiProperties.serverVersion`; otherwise `kind: GlobalDocumentDB` |
| `sql_databases`, `sql_dedicated_gateway`, `mongo_databases`, `gremlin_databases` | the children above: `options.throughput` or `options.autoscaleSettings.maxThroughput`; a container's partition key (`Hash`, version 2 by default), TTLs, unique keys, conflict resolution policy (a Custom procedure as the module writes it, `dbs/{<db key>}/colls/{<name>}/sprocs/{<procedure>}`) and indexing policy (orders lower-cased, spatial indexes of all four types, as azurerm sends them); a collection's indexes (the entry's, the module's unique `_id` index, a `_ts` index expiring after `default_ttl_seconds`) and hashed shard key; a graph's index policy with `/"_etag"/?` always excluded |
| `private_endpoints`, `private_endpoints_manage_dns_zone_group` | the endpoints above: named `pep-<name>` and their connection `pse-<key>` unless given, the endpoint's tags else the account's |
| `lock` | the AVM lock interface (`lock-<kind>`, the module's notes), inherited by endpoints |
| `role_assignments` | the AVM interface: a role by name (ASO resolves it) or ID; `skip_service_principal_aad_check` sends `principalType: ServicePrincipal`, as azurerm does; `principal_type`, `condition` and `condition_version` are dropped, as the module drops them ("not supported") |
| `diagnostic_settings` | the AVM interface: `diag-<key>` unless named; log categories when given, else log groups (default `allLogs`); metric categories must be `SLI` or `Requests`, so each setting sets them (the module's default, `AllMetrics`, fails its own validation) |
| `enable_telemetry` | accepted; the chart sends no telemetry |

The module's preconditions stop the render with its messages: continuous
backup with multi-region writes, analytical storage with partition merge,
SQL and MongoDB databases together, throughput on a serverless account's
databases or containers, and serverless in more than one region (the
module's own check of that last one never fires: it looks for a string in a
set of objects).

### Not module inputs

| Value | Renders |
| --- | --- |
| `subscription_id` | the subscription of `resource_group_name` when it is a name: ASO's owner is a resource ID |
| `names.databaseAccount` | the account's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name` and of the endpoints' names; checked against the 44-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

### Refused when set

None: every variable is carried (`upstream.yaml`, `refused: []`).

## Outputs

43 of the module's 47, from the live objects (`package.yaml`): the
account's `name`, `resource_id`, `resource_group_name`, `location`
(normalized, `eastus2`), `kind`, `offer_type`, `endpoint`,
`read_endpoints`, `write_endpoints` and every setting the module echoes
(`backup`, `capabilities`, `capacity`, `consistency_policy`, `cors_rule`,
`geo_location`, `identity`, `ip_range_filter`, `virtual_network_rule`,
`tags` and the flags), shaped as azurerm's; `sql_databases` and
`mongo_databases` (each database's ID and its containers' or collections'),
`sql_dedicated_gateway`, `resource_private_endpoints`,
`resource_private_endpoints_application_security_group_association`
(azurerm's `<endpoint ID>|<group ID>`), `resource_locks`,
`resource_role_assignments` and `resource_diagnostic_settings`.

Not as in the module: `sql_databases` gives each container's functions
(the module's filter compares a function's container ID with the
database's ID, so its maps are always empty), and `resource_locks` keys an
endpoint's lock `<endpoint key>/<lock name>` (an endpoint inherits the
account's lock, and the module's map then has one key twice and fails).

Not outputs: `cosmosdb_keys`, `cosmosdb_sql_connection_strings` and
`cosmosdb_mongodb_connection_strings`, the account's keys and the
connection strings that carry them: secret values, which do not belong
in outputs (whether a component may hold one is the builder's decision);
and `resource`, the whole azurerm account, those keys among its
attributes. ASO can write the keys to a Kubernetes Secret
(`operatorSpec.secrets`); the chart does not ask it to.

## From Terraform

A module block's arguments are the values, plus `subscription_id` when
`resource_group_name` is a name. ASO adopts an account, database or
container that exists when an object with its name is applied, so keep the
names and leave `namePrefix` empty; set `deletion_policy: ABANDON` for the
first apply, `terraform state rm` the module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-documentdb-databaseaccount`](https://github.com/Azure/terraform-azurerm-avm-res-documentdb-databaseaccount/tree/v0.12.0)
at v0.12.0 (`9939de3a`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-documentdb-databaseaccount`: render cases
`basic` (the module's default example), `sql`, `mongo`, `gremlin`, `full`,
`names` and `mock`, each validated against ASO v2.22.0's CRD schemas and
aso-extensions' copied CRDs (`ManagementLock`, the two Gremlin kinds and
`DatabaseAccountsService`), and the refusals in `tests/*.fail.yaml`.

`task test-mock-azure` applies `tests/mock.values.yaml` (a serverless SQL
account with a database, a container, its stored procedure, trigger and
function, a dedicated gateway and a Gremlin database with a graph) to
aso-extensions' fake cloud: run `off-catalog-1113080039-31223` on
2026-11-13, all 9 objects Ready and deleted, 41 of the 43 outputs
evaluated. `endpoint` and `geo_location` were not: the fake Resource
Manager's account has no `documentEndpoint`, no `readLocations` or
`writeLocations`, and no `id` on a location (computed fields Azure
returns; a gap of aso-extensions' fakearm, not faked in the chart).

`task test-live-azure` with `AZURE_LIVE_CASES=cosmos` (not in the
default) applies a serverless SQL account in one region, not zone
redundant, with the free 7-day continuous backup, a database and a
container. Not applied: the sandbox subscription has not registered the
`Microsoft.DocumentDB` provider, and ASO's registration call was refused
(run `cat11130805699c` on 2026-11-13: `403 AuthorizationFailed`, the
identity may not perform `Microsoft.DocumentDB/register/action` on the
subscription). The account never existed in Azure, so the database and
container waited for their owner; nothing was made. Registering a
provider is a subscription-scope action the live rules forbid, so the
case waits on the builder (`az provider register --namespace
Microsoft.DocumentDB --subscription 149e8810-e0fe-48e2-a46e-6f8f575bde01`).

## Changes

- **0.1.0** (2026-11-13): the port.
