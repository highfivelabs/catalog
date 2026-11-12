# avm-res-storage-storageaccount

An Azure storage account with its containers, queues, tables and file
shares, and its lock, role assignments and diagnostic settings, as Azure
Service Operator (ASO) objects. A port of the Azure Verified Module
[`avm-res-storage-storageaccount`](https://github.com/Azure/terraform-azurerm-avm-res-storage-storageaccount/tree/226f9bbefcc9299ad46f6263fc9005edb39a38e5)
at v0.11.0 (`226f9bbe`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-storage-storageaccount`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

Partial: the account and its children are ported; the services'
properties, lifecycle rules, Data Lake filesystems, private endpoints and
the customer-managed key are not mapped yet, and local users and the static
website have no ASO kind (below).

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
| each child's `role_assignments` | one per assignment | `RoleAssignment`, `<child id>/role-assignment-<k>`, owned by the child |
| `azapi_resource.lock` | `lock` set | `ManagementLock` (aso-extensions), `lock`: `lock-<name>` with the module's notes |
| `module.role_assignments` | one per entry | `RoleAssignment`, `role-assignment-<key>` |
| `module.diagnostic_setting_*` | one per entry | `DiagnosticSetting`, `diagnostic-setting-<key>` on the account, `<svc>-service/diagnostic-setting-<key>` on the blob, file, queue or table service (by ARM ID) |
| telemetry | never | not ported |

ASO's `StorageAccount` is at API version 2025-06-01, the module's default
2025-08-01 (`resource_types`): every property the module sends exists in
2025-06-01 except the `Smart` access tier.

Like the module, the chart does not create the blob, file, queue or table
service objects: Azure gives every account a `default` of each, and the
children name them by ARM ID (`<account>/blobServices/default`). So
`parent_id` and the account's name must be known at render time, as they
are.

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
| `enable_telemetry`, `role_assignment_definition_lookup_enabled`, `private_endpoints_manage_dns_zone_group`, `table_service_cors_propagation_wait` | accepted, no effect: no telemetry is sent; ASO always resolves a role name; private endpoints and the table service's CORS rules are refused |

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
| `local_user` | gap | `Microsoft.Storage/storageAccounts/localUsers` has no ASO or aso-extensions kind |
| `static_website` | gap | set on the blob service's data plane, which ASO does not call |
| `access_tier: Smart` | gap | needs API version 2025-08-01; ASO's `StorageAccount` is at 2025-06-01 |
| a table's or share's `signed_identifiers` | gap | ASO renders a signed identifier's `id` as an ARM reference |
| `blob_properties`, `file_service_properties`, `queue_properties`, `table_properties` | not ported | ASO has the service kinds |
| `storage_management_policy_rule` | not ported | ASO has `StorageAccountsManagementPolicy` |
| `storage_data_lake_gen2_filesystems` | not ported | a container with its ACLs |
| `private_endpoints` | not ported | ASO has `PrivateEndpoint` and its DNS zone group |
| `customer_managed_key` | not ported | ASO has `encryption.keyvaultproperties` |
| `resource_types` | by design | ASO's kinds fix the API versions |
| `retry`, `timeouts`, `storage_management_policy_timeouts`, any entry's or `network_rules`' `timeouts` | by design | ASO retries itself and has no per-request timeouts |

## Outputs

| Output | From |
| --- | --- |
| `name` | computed from the inputs |
| `resource_id` | the account's `status.id` |
| `fqdn` | `{blob, queue, table}` (each when the account has containers, queues or tables, as the module lists them) to the host of the account's `status.primaryEndpoints` |
| `containers`, `queues`, `tables`, `shares` | `{<key>: {id, name}}` from each child's `status.id` and `azureName`, as the module outputs them |

Not outputs: `resource` (the module's whole azapi object), and
`local_users`, `private_endpoints` and `data_lake_gen2_filesystems`, which
the chart refuses.

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
`full`, `premium`, `names` and `mock`, each validated against ASO
v2.22.0's CRD schemas and aso-extensions' `ManagementLock` CRD, and the
refusals in `tests/*.fail.yaml`. `task test-live-azure` applies a Standard_LRS account with a container and a queue to the Azure sandbox with
Azure Service Operator, evaluates the outputs, deletes it and checks Azure
no longer has it: passed on 2026-11-12. Not yet applied to the fake cloud
(`docs/azure.md`, "8. Charts").

## Changes

- **0.1.0** (2026-11-12): the port.
