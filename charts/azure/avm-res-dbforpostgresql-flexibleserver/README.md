# avm-res-dbforpostgresql-flexibleserver

An Azure Database for PostgreSQL flexible server with its databases,
firewall rules, server parameters, Entra administrators, virtual
endpoints and private endpoints, and its lock, role assignments and
diagnostic settings, as Azure Service Operator (ASO) objects. A port of
the Azure Verified Module
[`avm-res-dbforpostgresql-flexibleserver`](https://github.com/Azure/terraform-azurerm-avm-res-dbforpostgresql-flexibleserver/tree/70d6e9c947f8b2c24b706bb3484228d53cf7858a)
at v0.2.3 (`70d6e9c9`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`), its `database` submodule included. Bundt Package
`azure-avm-res-dbforpostgresql-flexibleserver` (`package.yaml`). Checked
against ASO v2.22.0's CRDs.

## Example

```yaml
name: psql-orders
location: eastus2
resource_group_name: rg-data
subscription_id: <id>
sku_name: B_Standard_B1ms
server_version: "16"
storage_mb: 32768
high_availability: null
authentication: {active_directory_auth_enabled: true, password_auth_enabled: false, tenant_id: <tenant>}
firewall_rules: {}
databases:
  app: {name: app}
ad_administrator:
  dba: {tenant_id: <tenant>, object_id: <group object ID>, principal_name: dba-group, principal_type: Group}
```

renders the ASO `FlexibleServer` `psql-orders`, its
`FlexibleServersDatabase` `app` and its `FlexibleServersAdministrator`
(`tests/golden/mock.yaml` is the same shape). Applications connect to the
`fqdn` output with an Entra token.

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azurerm_postgresql_flexible_server.this` | always | `FlexibleServer` (`dbforpostgresql.azure.com/v20250801`), `server`, owned by the resource group |
| `module.databases` (`azurerm_postgresql_flexible_server_database.this`) | one per `databases` entry | `FlexibleServersDatabase`, `database:<key>` |
| `azurerm_postgresql_flexible_server_firewall_rule.this` | one per `firewall_rules` entry (not set: the module's allow-all `rule1`) | `FlexibleServersFirewallRule`, `firewall_rule:<key>` |
| `azurerm_postgresql_flexible_server_configuration.this` | one per `server_configuration` entry | `FlexibleServersConfiguration` (`source: user-override`), `server_configuration:<key>` |
| `azurerm_postgresql_flexible_server_active_directory_administrator.this` | one per `ad_administrator` entry | `FlexibleServersAdministrator` (named by `object_id`), `ad_administrator:<key>` |
| `azurerm_postgresql_flexible_server_virtual_endpoint.this` | one per `virtual_endpoint` entry | `FlexibleServersVirtualEndpoint` (its member the replica's name), `virtual_endpoint:<key>` |
| `azurerm_private_endpoint.this_managed_dns_zone_groups` / `this_unmanaged_dns_zone_groups` | one per `private_endpoints` entry | `PrivateEndpoint` (`network.azure.com/v20250301`), `private_endpoint:<key>`; a `PrivateEndpointsPrivateDnsZoneGroup` (`private_endpoint:<key>/dns_zone_group`) when `private_endpoints_manage_dns_zone_group` and zones are given |
| `azurerm_private_endpoint_application_security_group_association.this` | one per association | the endpoint's `applicationSecurityGroups` |
| `azurerm_management_lock.this` | `lock` set | `ManagementLock` (aso-extensions), `lock` |
| `azurerm_role_assignment.this` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `azurerm_monitor_diagnostic_setting.this` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` |
| telemetry | never | not ported |

Every child is owned by the server (ASO `owner`), so ASO creates it after
the server is ready and the server's ARM ID is never needed.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`), so a module block's arguments
convert one to one. How the server's map onto `FlexibleServer`:

| Variable | ASO field |
| --- | --- |
| `sku_name` (`B_`, `GP_`, `MO_` + name) | `sku.tier` (`Burstable`, `GeneralPurpose`, `MemoryOptimized`) and `sku.name` |
| `server_version` | `version` (11 to 18 at ASO's 2025-08-01) |
| `storage_mb`, `storage_tier`, `auto_grow_enabled` | `storage.storageSizeGB` (`storage_mb / 1024`), `storage.tier`, `storage.autoGrow` |
| `backup_retention_days`, `geo_redundant_backup_enabled` | `backup.backupRetentionDays`, `backup.geoRedundantBackup` |
| `authentication` | `authConfig` (`activeDirectoryAuth`, `passwordAuth`, `tenantId`) |
| `high_availability` | `highAvailability`; null is `mode: Disabled`, as azurerm sends it |
| `maintenance_window` | `maintenanceWindow` with `customWindow: Enabled`; null leaves the system window |
| `delegated_subnet_id`, `private_dns_zone_id`, `public_network_access_enabled` | `network.delegatedSubnetResourceReference`, `network.privateDnsZoneArmResourceReference`, `network.publicNetworkAccess` |
| `customer_managed_key` | `dataEncryption` (`type: AzureKeyVault`, the key URIs and identities) |
| `managed_identities` | `identity` |
| `create_mode`, `source_server_id`, `point_in_time_restore_time_in_utc`, `replication_role` | `createMode`, `sourceServerResourceReference`, `pointInTimeUTC`, `replicationRole` |
| `zone` | `availabilityZone` |

Not as in the module:

- **No password.** `administrator_password`, `administrator_password_wo`
  and `administrator_password_wo_version` are refused (by design): a
  password is a secret value, which does not belong in a component's
  inputs. ASO takes one only from a Kubernetes Secret
  (`administratorLoginPassword`), and how a component supplies that Secret
  is the builder's decision, still open. Because Azure needs a password
  when password authentication is on, a server the chart creates
  (`create_mode` `Default`) must set `authentication:
  {active_directory_auth_enabled: true, password_auth_enabled: false}`;
  the render stops otherwise, naming the reason. `administrator_login` is
  kept.
- **`timeouts`** (the server's and each database's) are refused: ASO has no
  per-request timeouts; Bundt sets a component's time limit.
- **`firewall_rules`' default** (`rule1`, every address) is applied in the
  template when the value is not set, so a map given replaces it as in
  Terraform; `{}` creates none.
- **Drift the module ignores** (`zone`, `high_availability.standby_availability_zone`,
  and a private endpoint's zone group when the module does not manage it):
  ASO keeps applying what it is given, so after a failover moves the
  server, set the new zone or leave these unset.
- **Server parameters are detached on delete.** Azure has no delete for a
  parameter (it goes with the server), so a `FlexibleServersConfiguration`
  always carries `reconcile-policy: detach-on-delete`. Removing an entry
  from `server_configuration` leaves the parameter's value in Azure, where
  azurerm would reset it to its default; set it back to the default to
  undo it.
- **A private endpoint's `role_assignments` and `lock`**, which the module
  declares and never creates, are created on the endpoint.

## Outputs

`package.yaml`: `resource_id` and `fqdn` (ASO's status), `name`,
`database_name` and `database_resource_ids` (keyed like `databases`), and
`private_endpoints` (each endpoint's `id` and `name`; the module gives the
whole azurerm object).

## Names, labels and tags

As every Azure chart (`docs/azure.md`, "8. Charts"): `names.flexibleServer`
sets the server's name in full; otherwise `namePrefix` goes in front of the
server's name and of each private endpoint's name. `labels` stay in
Kubernetes; `tags` are the server's Azure tags (a private endpoint takes its
entry's `tags`, as in the module). `deletion_policy: ABANDON` keeps every
resource in Azure when the component is deleted.

## Tests

`tests/*.values.yaml` render to `tests/golden/` and pass `kubeconform
-strict`; `tests/*.fail.yaml` must be refused with the message on their
first line. `tests/mock.values.yaml` is applied to aso-extensions' fake
cloud (`task test-mock-azure`), and the `psql` case of `hack/azure-live.sh`
to the Azure sandbox (`docs/azure.md`, "8. Charts", Testing).
