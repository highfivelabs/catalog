# avm-res-keyvault-vault

An Azure Key Vault with its keys, secrets and private endpoints, and its lock,
role assignments and diagnostic settings, as Azure Service Operator (ASO) objects. A port of
the Azure Verified Module
[`avm-res-keyvault-vault`](https://github.com/Azure/terraform-azurerm-avm-res-keyvault-vault/tree/7c53adbc7f4f716fa00b21af90e1a120db5e19ef)
at v0.13.0 (`7c53adbc`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-keyvault-vault`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

Partial: certificate contacts have no kind (below). A secret's value is
a reference to a Kubernetes Secret ([secrets](../../../docs/secrets.md)).

## Example

```yaml
name: kv-example-001
location: eastus2
parent_id: /subscriptions/<id>/resourceGroups/rg-example
tenant_id: <tenant GUID, lower case>
```

renders the ASO `Vault` `kv-example-001` with the module's defaults:
premium, Azure RBAC, purge protection, public network access with a
firewall that denies all (`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.this` (`Microsoft.KeyVault/vaults`) | always | `Vault` (`keyvault.azure.com/v1api20230701`), `vault`, owned by `parent_id` |
| `module.keys` (`azurerm_key_vault_key`) | one per `keys` entry | `VaultKey` (`keyvault.azure.com/v20230701`, `Microsoft.KeyVault/vaults/keys`), `key:<key>`, owned by the vault |
| the keys' `role_assignments` | one per assignment | `RoleAssignment`, `key:<key>/role-assignment-<k>`, owned by the key |
| `module.secrets` (`azurerm_key_vault_secret`) | one per `secrets` entry | `VaultSecret` (aso-extensions, `keyvault.azure.hfl.dev/v1`, written in the vault's data plane as azurerm writes it), `secret:<key>`, owned by the vault |
| the secrets' `role_assignments` | one per assignment | `RoleAssignment`, `secret:<key>/role-assignment-<k>`, owned by the secret's versionless ARM ID |
| `azapi_resource.lock` | `lock` set | `ManagementLock` (aso-extensions), `lock`: `lock-<name>` |
| `azapi_resource.role_assignments` | one per entry | `RoleAssignment`, `role-assignment-<key>` |
| `azapi_resource.diagnostic_settings` | one per entry | `DiagnosticSetting`, `diagnostic-setting-<key>`: `diag-<name>` unless named |
| `azapi_resource.private_endpoints` (or `_unmanaged_dns_zone_groups`) | one per `private_endpoints` entry | `PrivateEndpoint` (`network.azure.com/v20250301`), `private_endpoint:<key>`: `pe-<name>` unless named, owned by `parent_id` or the entry's `resource_group_name` (in the vault's subscription), its connection to the vault by reference |
| `azapi_resource.private_dns_zone_groups` | an entry with `private_dns_zone_resource_ids`, when `private_endpoints_manage_dns_zone_group` | `PrivateEndpointsPrivateDnsZoneGroup`, `private_endpoint:<key>/dns_zone_group`, one zone configuration per zone, named for it |
| `azapi_resource.private_endpoint_locks` | an entry with a `lock` | `ManagementLock` (aso-extensions), `private_endpoint:<key>/lock`: `lock-<endpoint name>` unless named, its notes when set |
| `time_sleep.wait_for_rbac_*` | never | ASO retries until a role assignment has propagated |
| telemetry | never | not ported |

ASO's `Vault` is at API version 2023-07-01, older than the module's
2026-02-01; every property the module sets exists in both. The module
makes keys through the data plane (azurerm); the chart makes them through
Resource Manager (`Microsoft.KeyVault/vaults/keys`). Resource Manager's
key PUT creates a key that does not exist and otherwise changes nothing
(Azure's "Keys - Create If Not Exist"): a change to a key's values after
it exists does not reach Azure, where azurerm would update or replace it.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`).

| Module input | ASO |
| --- | --- |
| `name`, `location`, `parent_id`, `tenant_id`, `tags` | `azureName`, `location`, `owner.armId`, `properties.tenantId`, `tags` |
| `sku_name` | `properties.sku` (`family: A`) |
| `enabled_for_deployment`, `enabled_for_disk_encryption`, `enabled_for_template_deployment` | the same `properties` |
| `purge_protection_enabled` | `enablePurgeProtection: true`, left out when false, as the module does |
| `legacy_access_policies_enabled`, `legacy_access_policies` | `enableRbacAuthorization` (its opposite) and, with legacy policies, `accessPolicies`, each permission in ASO's spelling (`Get` is `get`). Without them the chart sends no `accessPolicies`, as the module leaves them to others |
| `network_acls` | `networkAcls`: `bypass`, `defaultAction`, `ipRules`, `virtualNetworkRules`; `null` leaves them out |
| `public_network_access_enabled`, `soft_delete_retention_days` | `publicNetworkAccess`, `softDeleteRetentionInDays` |
| `keys` | per key: `kty`, `keyOps` (`["sign", "verify"]`), `keySize`, `curveName`, `attributes.nbf` and `exp` (the dates as Unix times), `tags`, `release_policy` (the JSON base64url-encoded, as azurerm sends it), `rotationPolicy` (`expire_after` as `attributes.expiryTime`, `automatic` as a `rotate` action, `notify_before_expiry` as a `notify` action), `role_assignments`; `release_policy.immutable` refused |
| `secrets`, `secrets_value`, `secrets_value_wo`, `secrets_value_wo_version` | per secret: `azureName`, `contentType`, `notBefore`, `expiresOn` (the module's UTC datetimes, checked as it checks them), `tags`, `role_assignments`, and `value` from `secrets_value` (or `secrets_value_wo`) under the entry's key, as a reference to a Kubernetes Secret, `{secretName, key}` ([secrets](../../../docs/secrets.md)); a string is refused, and so is an entry with neither or both. A change to the Secret makes a new version, so `secrets_value_wo_version` is accepted and does nothing. As azurerm's defaults: `createMode: createOrRecover` (a soft-deleted secret of the name is recovered) and `deleteMode: delete` (deleting the object soft-deletes the secret) |
| `lock`, `role_assignments`, `diagnostic_settings` | the AVM interfaces (`docs/azure.md`, "8. Charts"); a role assignment with `skip_service_principal_aad_check` and no `principal_type` is `ServicePrincipal`, as the module sets it. The module lists every diagnostic category Azure offers, the unused ones disabled; the chart lists the enabled ones, the same setting |
| `private_endpoints` | per entry: `subnet.reference.armId`, `customNetworkInterfaceName`, one `privateLinkServiceConnections` entry (`pse-<name>` unless named, `groupIds` the `subresource_name`, default `vault`), `ipConfigurations` (`groupId` as the connection's, `memberName` default `default`) and `applicationSecurityGroups`, sent empty when unset as the module sends them, `location`, `tags`; the zone group and lock above. An entry's `role_assignments` are accepted and ignored, as the module ignores them |
| `private_endpoints_manage_dns_zone_group` | false: no zone groups, for zones managed elsewhere (Azure Policy) |
| `enable_telemetry`, `wait_for_rbac_before_key_operations`, `_secret_operations`, `_contact_operations` | accepted, no effect: no telemetry is sent; ASO retries until RBAC has propagated |

The module's validations stop the render with its messages: the vault's
name (3 to 24 letters, digits and dashes, a letter first, no `--`), the
tenant ID (a lower-case GUID), the SKU and the retention days.

### Not module inputs

| Value | Renders |
| --- | --- |
| `names.keyVault` | the vault's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name`, never of a name under `names` or a key's; checked against the 24-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` and `purge_protection_enabled` |

### Refused when set

| Variable | Kind | Why |
| --- | --- | --- |
| `contacts` | gap | certificate contacts are a Key Vault data-plane setting, with no ASO or aso-extensions kind |
| a key's `release_policy.immutable` | gap | ASO's `VaultKey` release policy has `contentType` and `data` only |
| `ignore_body_changes` | gap | ASO cannot leave a path to another writer |
| `resource_types`, `retry`, `timeouts` | by design | ASO's kinds fix the API versions; ASO retries itself and has no per-request timeouts |

## Outputs

| Output | From |
| --- | --- |
| `name` | computed from the inputs |
| `resource_id`, `uri` | the vault's `status.id` and `status.properties.vaultUri` |
| `keys_resource_ids` | `{<key>: {id, name, resource_id, resource_versionless_id, versionless_id}}`, from each key's status, as the module outputs them |
| `keys` | the same map: the module's key objects also carry the public key material (`n`, `e`, `x`, `y`, PEM, OpenSSH), which ASO's status does not |
| `secrets_resource_ids`, `secrets` | `{<key>: {id, name, resource_id, resource_versionless_id, versionless_id}}`, from each secret's status (its current version's URI and version) and the vault's ARM ID, as the module outputs them (the module's `secrets` is the same map) |
| `private_endpoints` | `{<key>: {id, name, location, subnet_id}}`, from each endpoint; the module's azurerm-shaped object also carries Azure's DNS configurations and network interface, which are not outputs here |

## From Terraform

A module block's arguments are the values, unchanged. ASO adopts a vault
that exists when an object with its name is applied, so keep the name and
leave `namePrefix` empty; set `deletion_policy: ABANDON` for the first
apply, `terraform state rm` the module, then remove `ABANDON`. A key that
exists is taken as it is: Resource Manager's key PUT leaves it unchanged.

## Upstream

Ported from the Azure Verified Module
[`avm-res-keyvault-vault`](https://github.com/Azure/terraform-azurerm-avm-res-keyvault-vault/tree/v0.13.0)
at v0.13.0 (`7c53adbc`, MIT), its `key` submodule included.
[`upstream.yaml`](upstream.yaml) records the repository, release, commit,
licence, the date last synced and every refusal.

## Tests

`task test CHART=avm-res-keyvault-vault`: render cases `basic`, `full`,
`legacy`, `names`, `pe-unmanaged`, `secrets` (two secrets, their values
from a Secret) and `mock` (a secret whose value is in a Secret the
fake-cloud run makes), each validated against ASO v2.22.0's CRD
schemas and aso-extensions' `ManagementLock` and `VaultSecret` CRDs, and the refusals in
`tests/*.fail.yaml`. `task test-live-azure` applies a standard vault without purge protection (no keys) to the Azure sandbox with
Azure Service Operator, evaluates the outputs, deletes it and checks Azure
no longer has it: passed on 2026-11-12. `task test-mock-azure` applies its `tests/mock.values.yaml` to aso-extensions'
fake cloud with stock ASO (`docs/azure.md`, "8. Charts").

0.2.0 against the fake cloud (stock ASO v2.22.0, aso-extensions' manager
at `b9beb5ba`), run `off-catalog-1113104327-27737` (2026-11-13): the vault, key, private endpoint and its DNS zone group
Ready and deleted, the outputs evaluated.

0.3.0 against the fake cloud (stock ASO v2.22.0, aso-extensions' manager
at `8d7f8c2`), run `off-catalog-1114090847-14562` (2026-11-14): with a
secret in `tests/mock.values.yaml`, the vault, key, private endpoint and
its DNS zone group were Ready and deleted, but the `VaultSecret` was not
Ready (`creating secret catalog-secret: key vault: 404 NotFound : fake
vault: no such operation`): the fake Resource Manager answers a vault's
data plane for keys only, and aso-extensions' fake secrets data plane
(`cmd/fakevault`, `pkg/fakecloud/keyvault`) is a separate server that
`hack/azure-mock.sh` did not run, so the secret was taken out of the mock
case. `hack/azure-mock.sh` now runs `cmd/fakevault` from `ASOX_COMMIT` and
sends a vault's secret requests to it (`tools/vaultroute`; `docs/azure.md`,
"8. Charts"), and the secret is back: run `off-catalog-1114103759-4674`
(2026-11-14), the vault, key, secret, private endpoint and its DNS zone
group Ready and deleted, the outputs evaluated.

## Changes

- **0.3.0** (2026-11-14): `secrets`, `secrets_value`, `secrets_value_wo`
  and `secrets_value_wo_version` are mapped, as aso-extensions
  `VaultSecret`s whose values are references to Kubernetes Secrets,
  `{secretName, key}` (docs/secrets.md, the builder's decision); new
  outputs `secrets` and `secrets_resource_ids`.
- **0.2.0** (2026-11-13): `private_endpoints` (with
  `private_endpoints_manage_dns_zone_group`) render ASO `PrivateEndpoint`,
  `PrivateEndpointsPrivateDnsZoneGroup` and a lock each; new output
  `private_endpoints`.
- **0.1.0** (2026-11-12): the port.
