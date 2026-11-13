# avm-res-sql-server

An Azure SQL logical server with its databases (and their retention,
threat detection and encryption settings), elastic pools, firewall rules,
connection policy and private endpoints, and its lock, role assignments
and diagnostic settings, as Azure Service Operator (ASO) objects. A port
of the Azure Verified Module
[`avm-res-sql-server`](https://github.com/Azure/terraform-azurerm-avm-res-sql-server/tree/dd3461fc43de092133eea999eb21efba31983079)
at v0.2.1 (`dd3461fc`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`), its `database` and `elasticpool` submodules included.
Bundt Package `azure-avm-res-sql-server` (`package.yaml`). Checked against
ASO v2.22.0's CRDs (`sql.azure.com/v20250101`).

## Example

```yaml
name: sql-orders
location: eastus2
resource_group_name: rg-data
subscription_id: <id>
server_version: "12.0"
azuread_administrator:
  azuread_authentication_only: true
  login_username: dba-group
  object_id: <group object ID>
  tenant_id: <tenant>
databases:
  app: {name: app, sku_name: Basic}
firewall_rules:
  office: {start_ip_address: 203.0.113.10, end_ip_address: 203.0.113.10}
```

renders the ASO `Server` `sql-orders` (Entra-only, the group its Entra
administrator), its `ServersDatabase` `app` and its `ServersFirewallRule`
`office` (`tests/golden/mock.yaml` is the same shape). Applications connect
to `resource.fully_qualified_domain_name` with an Entra token.

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azurerm_mssql_server.this` | always | `Server` (`sql.azure.com/v20250101`), `server`, owned by the resource group; `azuread_administrator` is its `administrators` |
| the server's `connection_policy` (a separate call in azurerm) | `connection_policy` set | `ServersConnectionPolicy`, `connection_policy` |
| `module.elasticpool` (`azurerm_mssql_elasticpool.this`) | one per `elastic_pools` entry | `ServersElasticPool`, `elastic_pool:<key>` |
| `module.database` (`azurerm_mssql_database.this`) | one per `databases` entry | `ServersDatabase`, `database:<key>`; in its pool by `elasticPoolReference` when `elastic_pool_key` is set |
| a database's `long_term_retention_policy` block | set | `ServersDatabasesBackupLongTermRetentionPolicy`, `database:<key>/long_term_retention_policy` |
| a database's `short_term_retention_policy` block | set | `ServersDatabasesBackupShortTermRetentionPolicy`, `database:<key>/short_term_retention_policy` |
| a database's `threat_detection_policy` block | set | `ServersDatabasesSecurityAlertPolicy`, `database:<key>/threat_detection_policy` |
| a database's `transparent_data_encryption_enabled` | `false` (Azure's default is on) | `ServersDatabasesTransparentDataEncryption` (`state: Disabled`), `database:<key>/transparent_data_encryption` |
| a database's `geo_backup_enabled` | `false` on a DataWarehouse (`DW...`) SKU | `ServersDatabasesGeoBackupPolicy` (aso-extensions, `sql.azure.hfl.dev/v20250101`; `state: Disabled`, owned by the database), `database:<key>/geo_backup_policy` |
| the server's `express_vulnerability_assessment_enabled` | `true` | `ServersSqlVulnerabilityAssessment` (aso-extensions, `sql.azure.hfl.dev/v20250101`; `state: Enabled`), `express_vulnerability_assessment` |
| `azurerm_mssql_firewall_rule.this` | one per `firewall_rules` entry, named by its key | `ServersFirewallRule`, `firewall_rule:<key>` |
| `azurerm_private_endpoint.this` / `this_unmanaged_dns_zone_groups` | one per `private_endpoints` entry | `PrivateEndpoint` (`network.azure.com/v20250301`, sub-resource `sqlServer`), `private_endpoint:<key>`; a `PrivateEndpointsPrivateDnsZoneGroup` (`private_endpoint:<key>/dns_zone_group`) when `private_endpoints_manage_dns_zone_group` and zones are given |
| `azurerm_private_endpoint_application_security_group_association.this` | one per association | the endpoint's `applicationSecurityGroups` |
| `azurerm_management_lock.this` (server, database, pool) | `lock` set | `ManagementLock` (aso-extensions), `lock`, `database:<key>/lock`, `elastic_pool:<key>/lock` |
| `azurerm_role_assignment.this` (server, database, pool) | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` (prefixed as the lock) |
| `azurerm_monitor_diagnostic_setting.this` (server, database, pool) | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` (prefixed as the lock) |
| `random_password`, `azurerm_key_vault_secret`, telemetry | never | not ported (below) |

Every child is owned by the server (ASO `owner`), so ASO creates it after
the server is ready and the server's ARM ID is never needed.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`), so a module block's arguments
convert one to one. 23 of the module's 28 variables are mapped, three of
them in part (below). The server's:

| Variable | ASO field |
| --- | --- |
| `server_version` | `version` |
| `azuread_administrator` | `administrators` (`administratorType: ActiveDirectory`, `login`, `sid`, `tenantId`, `azureADOnlyAuthentication: true`) |
| `administrator_login` | `administratorLogin` (passed through; see "No password") |
| `public_network_access_enabled`, `outbound_network_restriction_enabled` | `publicNetworkAccess`, `restrictOutboundNetworkAccess` |
| `managed_identities`, `primary_user_assigned_identity_id` | `identity`, `primaryUserAssignedIdentityReference` |
| `transparent_data_encryption_key_vault_key_id` | `keyId` |
| `connection_policy` | `ServersConnectionPolicy.connectionType` |
| the module's fixed `minimum_tls_version = "1.2"` | `minimalTlsVersion: "1.2"` |

A database's: `sku_name` is `sku.name`; `max_size_gb` is `maxSizeBytes`
(GiB); `auto_pause_delay_in_minutes`, `min_capacity`, `collation`,
`create_mode`, `ledger_enabled`, `license_type`, `zone_redundant`,
`sample_name`, `restore_point_in_time` are the like-named fields;
`read_scale` is `readScale`, `read_replica_count`
`highAvailabilityReplicaCount`, `storage_account_type`
`requestedBackupStorageRedundancy`, `recover_database_id` and
`restore_dropped_database_id` the recoverable and restorable dropped
database references, `transparent_data_encryption_key_vault_key_id` and
`..._automatic_rotation_enabled` `encryptionProtector` and
`encryptionProtectorAutoRotation`, a user-assigned
`managed_identities` `identity`, and `maintenance_configuration_name` the
public maintenance configuration's ID in the server's subscription (as
azurerm builds it). An elastic pool's `sku`, `per_database_settings`,
`zone_redundant`, `license_type`, `max_size_gb` or `max_size_bytes` and
`maintenance_configuration_name` (default `SQL_Default`) map the same way.

Not as in the module:

- **No password, Entra-only.** `administrator_login_password`,
  `administrator_login_password_wo`, `administrator_login_password_wo_version`,
  `generate_administrator_login_password` (when true) and
  `administrator_login_password_key_vault_configuration` are refused (by
  design): a password, given or generated, is a secret value, which does
  not belong in a component's inputs. ASO takes one only from a Kubernetes
  Secret (`administratorLoginPassword`), and how a component supplies that
  Secret is the builder's decision, still open; the Key Vault copy needs
  the password too. Because Azure needs a password for a server that is
  not Entra-only, the chart needs `azuread_administrator` with
  `azuread_authentication_only: true`; the render stops otherwise, naming
  the reason. The Entra administrator is a login on the server (the
  database-level administrator), not an Azure role assignment.
  `administrator_login` is kept and passed through; Azure decides whether
  it takes one without a password.
- **A database's `import`** is refused: a `.bacpac` import is an action
  with a storage key and an administrator password (secret values) and no
  ASO kind. **`threat_detection_policy.storage_account_access_key`** is
  refused (a secret value; ASO takes it only from a Kubernetes Secret).
A database's
  `managed_identities.system_assigned` is accepted and ignored, as the
  module ignores it (Azure has no system identity on a database).
- **A database's `geo_backup_enabled: false`** renders a
  `ServersDatabasesGeoBackupPolicy` with `state: Disabled` only on a
  DataWarehouse (`DW...`) SKU, as azurerm sets
  `Microsoft.Sql/servers/databases/geoBackupPolicies` for DW SKUs only;
  real Azure accepts the policy only on a DataWarehouse database, so on any
  other SKU the value has no effect, as in the module. `true` (the default)
  renders nothing: Azure's policy is on.
- **A firewall rule's `timeouts`** are refused: ASO has no per-request
  timeouts; Bundt sets a component's time limit.
- **Settings detached on delete.** The connection policy, a database's
  retention policies, its threat detection policy, its transparent data
  encryption setting, its geo-backup policy and the server's express
  vulnerability assessment are settings of their parent with no delete in Azure
  (blocks of the azurerm resource in the module), so their objects always
  carry `reconcile-policy: detach-on-delete`. Removing one from the values
  leaves the setting as it was in Azure; set it back to undo it.
- **A private endpoint's `subresource_name`** is accepted and not used:
  the module always connects `sqlServer`. Its `role_assignments` and
  `lock`, which the module declares and never creates, are created on the
  endpoint.
- **Changing the administrator.** Azure applies `administrators` on
  updates too, except `azureADOnlyAuthentication`, which the chart always
  sets to `true`.

## Outputs

`package.yaml`: `resource_id` (ASO's status), `resource_name`, `resource`
(the server's `id`, `name`, `location`, `version` and
`fully_qualified_domain_name`; the module gives the whole azurerm object),
`resource_databases` and `resource_elasticpools` (keyed like `databases`
and `elastic_pools`: each entry's `name`, `resource_id` and a cut-down
`resource`), and `private_endpoints` (each endpoint's `id` and `name`).
Not outputs: `generated_administrator_login_password` and
`administrator_login_password_key_vault_secret`, the secret values the
chart refuses to make. 6 of the module's 8 outputs.

## Names, labels and tags

As every Azure chart (`docs/azure.md`, "8. Charts"): `names.server` sets
the server's name in full; otherwise `namePrefix` goes in front of the
server's name and of each private endpoint's default name. `labels` stay in
Kubernetes; `tags` are the server's Azure tags (a database, a pool and a
private endpoint take their entry's `tags`, as in the module).
`deletion_policy: ABANDON` keeps every resource in Azure when the component
is deleted.

## Tests

`tests/*.values.yaml` render to `tests/golden/` and pass `kubeconform
-strict`; `tests/*.fail.yaml` must be refused with the message on their
first line. `tests/mock.values.yaml` is applied to aso-extensions' fake
cloud (`task test-mock-azure`), and the `sql` case of `hack/azure-live.sh`
to the Azure sandbox (`docs/azure.md`, "8. Charts", Testing).

Run on 2026-11-13. Fake cloud (stock ASO v2.22.0 and aso-extensions'
manager against aso-extensions' fakearm at `b9beb5b`, run
`off-catalog-1113081050-1496`): `tests/mock.values.yaml`'s 6 objects (the
server, its connection policy, a Basic database with its short-term
retention policy, a Basic elastic pool and a firewall rule) Ready and
deleted, the outputs evaluated. The fake Resource Manager at `b9beb5b` did not compute
a server's `fullyQualifiedDomainName`, so `resource.fully_qualified_domain_name`
was null there. 0.2.0 against aso-extensions `3d9ba27` (run
`off-catalog-1113161553-22079`): the same 6 objects and the express
vulnerability assessment (`ServersSqlVulnerabilityAssessment`) Ready and
deleted, the outputs evaluated, `resource.fully_qualified_domain_name`
(`catalog-sql.database.windows.net`) among them. A DataWarehouse
database's geo-backup policy, tried in run `off-catalog-1113155314-18721`,
never became Ready (the kind's owner was broken at `3d9ba27`). 0.3.0
against aso-extensions `f73f5ca` (run `off-catalog-1113185043-30939`):
the same objects plus a DW100c database and its
`ServersDatabasesGeoBackupPolicy` (`state: Disabled`), 9 objects Ready
and deleted, the outputs evaluated. Live: pending (live pending AZURE env
in catalog/.env).
The first fake run (`off-catalog-1113075959-109`) had every object Ready
and the outputs evaluated, but stopped at the delete: Kubernetes had
already collected a firewall rule its server owned when `kubectl delete -f`
reached it, so the fake and live scripts now delete with
`--ignore-not-found`.

Live (`sql` case, `hack/azure-live.sh`): a server with Entra-only
authentication and the live identity as its Entra administrator, one
Basic database (locally redundant backups) and a firewall rule for one
documentation address. eastus2, the runs' default region, refuses Azure
SQL servers for the sandbox subscription: "Provisioning is restricted in
this region. Please choose a different region. For exceptions to this rule
please open a support request with Issue type of 'Service and subscription
limits'." (run `cat111308043e66`, offload `off-catalog-1113080046-4023`;
nothing was made). So the case runs in `AZURE_LIVE_SQL_LOCATION`,
by default `centralus`, and passed there in run `cat11130849e109` (offload
`off-catalog-1113084555-21499`): 3 objects Ready, outputs evaluated (the
FQDN `<server>.database.windows.net` among them), deleted, Azure answering
404, no SQL server left in the group. A run before it (`cat1113083518f9`)
made and evaluated the same, then stopped in the script's report: a `cat`
of a case's prerequisites file, which only cases with prerequisites have,
failed under `pipefail` (fixed in `hack/azure-live.sh`); its server was
deleted.

## Changes

- **0.2.0** (2026-11-13): `express_vulnerability_assessment_enabled: true`
  renders aso-extensions' `ServersSqlVulnerabilityAssessment` and is no
  longer refused.
- **0.1.0** (2026-11-13): the port.
