# avm-res-storage-storageaccount

An Azure storage account with its containers, queues, tables, file
shares, local users, services' properties, lifecycle rules, Data Lake
filesystems and private endpoints, and its lock, role assignments and
diagnostic settings, as Azure
Service Operator (ASO) objects. A port of the Azure Verified Module
[`avm-res-storage-storageaccount`](https://github.com/Azure/terraform-azurerm-avm-res-storage-storageaccount/tree/226f9bbefcc9299ad46f6263fc9005edb39a38e5)
at v0.11.0 (`226f9bbe`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-storage-storageaccount`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

Partial: the customer-managed key (applied by the module in a second
step, below), the static website (no kind) and a few fields are refused.

## Example

```yaml
name: stexample001
location: eastus2
parent_id: /subscriptions/<id>/resourceGroups/rg-example
```

renders the ASO `StorageAccount` `stexample001` with the module's
defaults: `StorageV2`, `Standard_ZRS`, `Hot`, TLS 1.2, HTTPS only, public
network access, shared keys and nested public access off, and network
rules that deny all but Azure services (`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.this` (`Microsoft.Storage/storageAccounts`) | always | `StorageAccount` (`storage.azure.com/v20250601`), `storage_account`, owned by `parent_id` |
| `module.containers` (`.../blobServices/default/containers`) | one per `containers` entry | `StorageAccountsBlobServicesContainer`, `container:<key>`, owned by the blob service by ARM ID |
| `module.queues` (`.../queueServices/default/queues`) | one per entry | `StorageAccountsQueueServicesQueue`, `queue:<key>` |
| `module.tables` (`.../tableServices/default/tables`) | one per entry | `StorageAccountsTableServicesTable`, `table:<key>` |
| `module.shares` (`.../fileServices/default/shares`) | one per entry | `StorageAccountsFileServicesShare`, `share:<key>` |
| `module.local_users` (`.../localUsers`) | one per `local_user` entry | `StorageAccountsLocalUser` (aso-extensions, `storage.azure.hfl.dev/v20260601`), `local_user:<key>`: home directory, SSH key authentication, permission scopes (the module's `rwdlc` string), authorized public keys; no shared key, as the module sends it |
| each child's `role_assignments` | one per assignment | `RoleAssignment`, `<child id>/role-assignment-<k>`, owned by the child |
| `azapi_resource.lock` | `lock` set | `ManagementLock` (aso-extensions), `lock`: `lock-<name>` with the module's notes |
| `module.role_assignments` | one per entry | `RoleAssignment`, `role-assignment-<key>` |
| `module.blob_service`, `file_service`, `queue_service`, `table_service` (`azapi_update_resource` on `<account>/<svc>Services/default`) | `blob_properties`, `file_service_properties`, `queue_properties`, `table_properties` set | `StorageAccountsBlobService`, `StorageAccountsFileService`, `StorageAccountsQueueService`, `StorageAccountsTableService`, `blob_service` ... `table_service`, owned by the account, with `detach-on-delete`: deleting one leaves the service, as removing an update resource does |
| `module.management_policy` | `storage_management_policy_rule` not empty | `StorageAccountsManagementPolicy` (`default`), `management_policy`, one rule per entry (`Lifecycle`) |
| `module.data_lake_filesystems` (`.../blobServices/default/containers`) | one per `storage_data_lake_gen2_filesystems` entry | `StorageAccountsBlobServicesContainer`, `data_lake_gen2_filesystem:<key>`, owned by the blob service by ARM ID |
| `module.private_endpoints` | one per `private_endpoints` entry | `PrivateEndpoint` (`network.azure.com/v20250301`), `private_endpoint:<key>`: `pe-<name>` unless named, owned by `parent_id` or the entry's `resource_group_name` (in the account's subscription), in the account's `edge_zone`; its `PrivateEndpointsPrivateDnsZoneGroup` (`private_endpoint:<key>/dns_zone_group`, zones `config-0`, `config-1` ... as the module names them) when `private_endpoints_manage_dns_zone_group`; its `ManagementLock` (`lock-<endpoint name>`, the module's notes unless given) and `RoleAssignment`s, owned by the endpoint |
| `module.diagnostic_setting_*` | one per entry | `DiagnosticSetting`, `diagnostic-setting-<key>` on the account, `<svc>-service/diagnostic-setting-<key>` on the blob, file, queue or table service (by ARM ID) |
| telemetry | never | not ported |

ASO's `StorageAccount` is at API version 2025-06-01, the module's default
2025-08-01 (`resource_types`): every property the module sends exists in
2025-06-01 except the `Smart` access tier.

Like the module, the chart creates no blob, file, queue or table service
objects of its own: Azure gives every account a `default` of each, and the
children name them by ARM ID (`<account>/blobServices/default`). So
`parent_id` and the account's name must be known at render time, as they
are. A service's properties, when set, are an ASO object for that
`default` service that changes it in place.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`).

| Module input | ASO |
| --- | --- |
| `name`, `location`, `parent_id`, `tags` | `azureName`, `location`, `owner.armId`, `tags` |
| `account_kind`; `account_sku_name`, else `account_tier`, `account_replication_type` and `provisioned_billing_model_version` | `kind`; `sku.name`, computed as the module computes it |
| `access_tier` | `accessTier`, left out for a premium `BlockBlobStorage` account as the module does; `Smart` refused |
| `allow_nested_items_to_be_public`, `cross_tenant_replication_enabled`, `allowed_copy_scope`, `shared_access_key_enabled`, `default_to_oauth_authentication`, `is_hns_enabled`, `local_user_enabled`, `nfsv3_enabled`, `sftp_enabled`, `min_tls_version`, `https_traffic_only_enabled` | `allowBlobPublicAccess`, `allowCrossTenantReplication`, `allowedCopyScope`, `allowSharedKeyAccess`, `defaultToOAuthAuthentication`, `isHnsEnabled`, `isLocalUserEnabled`, `isNfsV3Enabled`, `isSftpEnabled`, `minimumTlsVersion`, `supportsHttpsTrafficOnly` |
| `public_network_access_enabled`, `large_file_share_enabled` | `publicNetworkAccess`, `largeFileSharesState` (`Enabled` or `Disabled`) |
| `infrastructure_encryption_enabled`, `queue_encryption_key_type`, `table_encryption_key_type` | `encryption` (`keySource: Microsoft.Storage`, `requireInfrastructureEncryption`, `services.queue` and `services.table`) |
| `network_rules` | `networkAcls`: `bypass` (joined, `None` when empty), `defaultAction`, `ipRules` and `virtualNetworkRules` (each `Allow`), `resourceAccessRules`; `null` leaves them out, as the module does |
| `custom_domain`, `edge_zone`, `routing`, `sas_policy`, `immutability_policy`, `azure_files_authentication` | `customDomain`, `extendedLocation` (`EdgeZone`), `routingPreference`, `sasPolicy`, `immutableStorageWithVersioning`, `azureFilesIdentityBasedAuthentication` |
| `managed_identities` | `identity` (`SystemAssigned`, `UserAssigned` or both) |
| `containers` | `publicAccess` (`None`), `metadata`, `defaultEncryptionScope` (`$account-encryption-key`), `denyEncryptionScopeOverride` (`false`), the NFSv3 squash flags, `immutableStorageWithVersioning`, `role_assignments` |
| `queues` | `metadata`, `role_assignments` |
| `tables` | `role_assignments`; `signed_identifiers` refused |
| `shares` | `shareQuota`, `accessTier`, `enabledProtocols`, `metadata`, `provisionedBandwidthMibps`, `provisionedIops`, `rootSquash`, `role_assignments`; `signed_identifiers` refused |
| `diagnostic_settings_storage_account`, `_blob`, `_file`, `_queue`, `_table` | the v2 interface: logs and metrics as given, each with its retention policy; an entry needs a `name`, as the module's azapi resource does |
| `lock`, `role_assignments` | the AVM interfaces (`docs/azure.md`, "8. Charts") |
| `blob_properties` | every property the module sends, each only when set: `automaticSnapshotPolicyEnabled`, `changeFeed`, `containerDeleteRetentionPolicy`, `cors.corsRules`, `defaultServiceVersion`, `deleteRetentionPolicy`, `isVersioningEnabled`, `lastAccessTimeTrackingPolicy`, `restorePolicy`; the module's validations (day ranges, restore days below delete days, the policy name) stop the render with its messages |
| `file_service_properties` | `cors.corsRules`, `protocolSettings.smb` (the sets joined with `;`, as the module joins them; `multichannel.enabled`), `shareDeleteRetentionPolicy` (7 days, enabled, unless given) |
| `queue_properties`, `table_properties` | `cors.corsRules` |
| `storage_management_policy_rule` | per rule: `name`, `enabled`, `type: Lifecycle`; `baseBlob`, `snapshot` and `version` actions (each tier or delete action only when one of its days is set), `filters` (`blobTypes`, `prefixMatch`, `blobIndexMatch` with `op` `==` unless given) |
| `storage_data_lake_gen2_filesystems` | `name`, `defaultEncryptionScope` when set, `properties` as `metadata`; the key `legacy` stops the render with the module's message; an entry's `timeouts` refused |
| `private_endpoints` | per entry: `subnet.reference.armId`, `customNetworkInterfaceName`, one `privateLinkServiceConnections` entry (`pse-<endpoint name>` unless named, `groupIds` the required `subresource_name`), `ipConfigurations` (`memberName` the subresource unless given) and `applicationSecurityGroups`, sent empty when unset as the module sends them, `location`, `tags`; the zone group, lock and role assignments above |
| `enable_telemetry`, `role_assignment_definition_lookup_enabled`, `table_service_cors_propagation_wait` | accepted, no effect: no telemetry is sent; ASO always resolves a role name; ASO reads back until Azure agrees, so no wait is needed |

### Not module inputs

| Value | Renders |
| --- | --- |
| `names.storageAccount` | the account's name in full, used as given |
| `namePrefix` | an optional convenience: in front of `name` without its hyphens (an account name is 3 to 24 lower-case letters and digits), never of a name under `names`; checked against the 24-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

### Refused when set

| Variable | Kind | Why |
| --- | --- | --- |
| a local user's `ssh_password_enabled`, `timeouts` | not ported, by design | Azure generates the password, returned once by `regeneratePassword`: whether a component may hold one is the builder's decision; Bundt sets a component's time limit |
| `static_website` | gap | set on the blob service's data plane, which ASO does not call |
| `access_tier: Smart` | gap | needs API version 2025-08-01; ASO's `StorageAccount` is at 2025-06-01 |
| a table's or share's `signed_identifiers` | gap | ASO renders a signed identifier's `id` as an ARM reference |
| `customer_managed_key` | gap | the module creates the account with Microsoft-managed keys and patches the key in afterwards (Azure rejects one PUT that both gives the account its identity and names it for encryption), reading the vault's URI from Azure; ASO applies a `StorageAccount` in one PUT, and a render cannot read the URI |
| `resource_types` | by design | ASO's kinds fix the API versions |
| `retry`, `timeouts`, `storage_management_policy_timeouts`, any entry's (a filesystem's too) or `network_rules`' `timeouts` | by design | ASO retries itself and has no per-request timeouts |

## Outputs

| Output | From |
| --- | --- |
| `name` | computed from the inputs |
| `resource_id` | the account's `status.id` |
| `fqdn` | `{blob, queue, table}` (each when the account has containers, queues or tables, as the module lists them) to the host of the account's `status.primaryEndpoints` |
| `containers`, `queues`, `tables`, `shares` | `{<key>: {id, name}}` from each child's `status.id` and `azureName`, as the module outputs them |
| `local_users` | `{<key>: {id, name, home_directory, sid, ssh_key_enabled, ssh_password_enabled}}`, the `sid` from the local user's status |
| `data_lake_gen2_filesystems` | `{<key>: {id, name}}`, as the module outputs them |
| `private_endpoints` | `{<key>: {id, name, edge_zone, private_dns_zone_group_id, role_assignments}}`, as the module outputs them (`role_assignments` `{<key>: {id, name}}`) |

Not output: `resource` (the module's whole azapi object).

## From Terraform

A module block's arguments are the values, unchanged. ASO adopts an
account and children that exist when objects with their names are
applied, so keep the names and leave `namePrefix` empty; set
`deletion_policy: ABANDON` for the first apply, `terraform state rm` the
module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-storage-storageaccount`](https://github.com/Azure/terraform-azurerm-avm-res-storage-storageaccount/tree/v0.11.0)
at v0.11.0 (`226f9bbe`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence, the date last synced and every
refusal.

## Tests

`task test CHART=avm-res-storage-storageaccount`: render cases `basic`,
`full`, `premium`, `names`, `services` and `mock`, each validated against ASO
v2.22.0's CRD schemas and aso-extensions' `ManagementLock` CRD, and the
refusals in `tests/*.fail.yaml`. `task test-live-azure` applies a Standard_LRS account with a container and a queue to the Azure sandbox with
Azure Service Operator, evaluates the outputs, deletes it and checks Azure
no longer has it: passed on 2026-11-12. `task test-mock-azure` applies its `tests/mock.values.yaml` to aso-extensions'
fake cloud with stock ASO (`docs/azure.md`, "8. Charts").

## Changes

- **0.2.0** (2026-11-13): `blob_properties`, `file_service_properties`,
  `queue_properties`, `table_properties` (ASO service objects),
  `storage_management_policy_rule`, `storage_data_lake_gen2_filesystems`
  and `private_endpoints` (with `private_endpoints_manage_dns_zone_group`)
  are mapped; new outputs `data_lake_gen2_filesystems` and
  `private_endpoints`. `customer_managed_key` is a gap, not a mapping to
  come.
- **0.1.0** (2026-11-12): the port.
