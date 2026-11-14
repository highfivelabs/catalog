# avm-res-web-site

An Azure App Service app (a web app or a function app) with its deployment
slots, custom domains, Key Vault certificates, private endpoints, lock,
role assignments and diagnostic settings, as Azure Service Operator (ASO)
and aso-extensions objects. A port of the Azure Verified Module
[`avm-res-web-site`](https://github.com/Azure/terraform-azurerm-avm-res-web-site/tree/56c704e9f44002a46a71226d3c19f3915e1865c0)
at v0.24.1 (`56c704e9`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-web-site` (`package.yaml`).
Checked against ASO v2.22.0's CRDs and aso-extensions' (`b9beb5b`).

## Example

```yaml
name: app-example
location: eastus2
parent_id: /subscriptions/<id>/resourceGroups/rg-example
service_plan_resource_id: /subscriptions/<id>/resourceGroups/rg-example/providers/Microsoft.Web/serverFarms/asp-example
```

renders one ASO `Site` `app-example`, a Linux web app with the module's
defaults: HTTPS only, public network access disabled, TLS 1.3, FTPS only,
and an aso-extensions `SitesBasicPublishingCredentialsPolicyFtp` that turns
FTP basic authentication off (the module's default,
`ftp_publish_basic_authentication_enabled: false`).
`tests/golden/basic.yaml` sets it `true`, which renders no policy.

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.this` | always | `Site` (`web.azure.com/v20250501`; the module sends 2025-03-01), `site`, owned by the resource group `parent_id` names |
| `module.config_appsettings` | always | the `Site`'s `siteConfig.appSettings` (the merged app settings of `locals.app_settings.tf`) |
| `module.config_metadata` | always | the `Site`'s `siteConfig.metadata` (`site_config.metadata` and, on Windows, `CURRENT_STACK`) |
| `module.slot` | one per `deployment_slots` entry | aso-extensions `SitesSlot` (`web.azure.hfl.dev/v20260715`), `slot:<key>`, owned by the `Site`, its app settings and metadata inline; its lock `slot:<key>/lock` and role assignments `slot:<key>/role-assignment-<k>` |
| `module.hostname_binding` | one per `custom_domains` entry | aso-extensions `SitesHostNameBinding`, `hostname_binding:<key>`, named for the hostname |
| `module.slot_hostname_binding` | one per slot `custom_domains` entry | aso-extensions `SitesSlotsHostNameBinding`, `slot:<key>/hostname_binding:<k>` |
| the slot module's `azapi_resource.private_endpoint`, `.private_dns_zone_group`, `.lock_private_endpoint`, `.role_assignment_private_endpoint` | one per slot `private_endpoints` entry | ASO `PrivateEndpoint`, `slot:<key>/private_endpoint:<k>`, to the `Site`'s `sites-<slot name>` subresource (unless `subresource_name`; members `sites-<slot name>` unless given), named as the site's endpoints are; its zone group, lock (its own, else the slot's when `private_endpoints_inherit_lock`) and role assignments under `slot:<key>/private_endpoint:<k>/` |
| `module.certificate` | one per `certificates` entry | aso-extensions `Certificate`, `certificate:<key>`, in the resource group, on the site's plan, from Key Vault |
| `azapi_resource.private_endpoint`, `.private_dns_zone_group` | one per `private_endpoints` entry | ASO `PrivateEndpoint` (`network.azure.com/v20250301`), `private_endpoint:<key>`, to the `Site` (subresource `sites`), with the interfaces module's names; `PrivateEndpointsPrivateDnsZoneGroup` when it has zones and `private_endpoints_manage_dns_zone_group` |
| `azapi_resource.lock`, `.lock_private_endpoint` | `lock` set | aso-extensions `ManagementLock`, `lock` (and `private_endpoint:<key>/lock`), named `lock-<kind>` by default |
| `azapi_resource.role_assignment`, `.role_assignment_private_endpoint` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`) |
| `azapi_resource.diagnostic_setting` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` |
| `module.config_authsettingsv2` | `auth_settings_v2` set | aso-extensions `SitesConfigAuthSettingsV2` (`web.azure.hfl.dev/v20260715`), `config_authsettingsv2`, owned by the `Site` |
| `module.config_logs` | one `logs` entry | aso-extensions `SitesConfigLogs`, `config_logs:<key>` |
| `module.config_slotconfignames` | `sticky_settings` not empty | aso-extensions `SitesConfigSlotConfigNames`, `config_slotconfignames` |
| `module.ftp_publishing_credential_policy`, `module.scm_publishing_credential_policy` | `ftp_publish_basic_authentication_enabled` (default) or `scm_publish_basic_authentication_enabled` false | aso-extensions `SitesBasicPublishingCredentialsPolicyFtp` or `...Scm`, `allow: false`, `ftp_publishing_credential_policy` or `scm_publishing_credential_policy` |
| `module.config_connectionstrings`, `config_azurestorageaccounts`, `config_authsettings` (v1), `config_backup`, `azapi_resource_action.active_slot`, `module.extensions_zipdeploy` | | refused when they would write anything (below) |
| telemetry | never | not ported |

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`). The body is transcribed from the
module's `locals.body.tf`, `locals.config.tf` and
`modules/site_config_helpers` (the slot's from `modules/slot`), with ARM
IDs as ASO references (`serverFarmReference`, `virtualNetworkSubnetReference`,
`hostingEnvironmentProfile.reference`, `managedEnvironmentReference`,
`apiManagementConfig.reference`, `vnetSubnetResourceReference` of an IP
restriction, the identities' `reference`s) and nulls left out, as the
module's `ignore_null_property`.

| Module input | ASO |
| --- | --- |
| `name`, `location`, `parent_id` (required) | `azureName`, `location`, `owner.armId` |
| `service_plan_resource_id` (required) | `serverFarmReference.armId`, its provider segment normalised as the module does |
| `kind`, `os_type` | `kind` (the module's `arm_kind_map`: `app,linux`, `functionapp,linux,container` ...), `reserved` (Linux) |
| `site_config` | `siteConfig`: every field the module sends, the language versions and `linuxFxVersion`/`windowsFxVersion` from `application_stack` as `site_config_helpers` derives them, IP restrictions with their headers, auto heal rules, CORS, virtual applications (Windows web apps), FC1's omissions |
| `app_settings` and the function app settings (`functions_extension_version`, `storage_account_name` with `storage_uses_managed_identity` and `storage_user_assigned_identity_client_id`, `builtin_logging_enabled`, `content_share_force_disabled`) | `siteConfig.appSettings`, merged as `locals.app_settings.tf` does (the case-insensitive overrides included). Values are taken as given: the module does not mark `app_settings` sensitive |
| `https_only`, `enabled`, `public_network_access_enabled`, `client_affinity_*`, `client_certificate_*`, `container_size`, `end_to_end_encryption_enabled`, `host_names_disabled`, `hyper_v`, `ip_mode`, `key_vault_reference_identity`, `redundancy_mode`, `scm_site_also_stopped`, `ssh_enabled`, `storage_account_required`, `workload_profile_name`, `auto_generated_domain_name_label_scope`, `daily_memory_time_quota` | the same-named properties (`publicNetworkAccess` `Enabled`/`Disabled`) |
| `virtual_network_subnet_id`, `vnet_route_all_traffic`, `vnet_application_traffic_enabled`, `virtual_network_backup_restore_enabled`, `vnet_content_share_enabled`, `vnet_image_pull_enabled` | `virtualNetworkSubnetReference`, `outboundVnetRouting` |
| `hosting_environment_id`, `managed_environment_id`, `dapr_config`, `resource_config` | `hostingEnvironmentProfile`, `managedEnvironmentReference`, `daprConfig`, `resourceConfig` |
| `dns_configuration` | `dnsConfiguration`'s same-named fields. The module's body reads `alternate_private_dns_zone_id`, `dns_legacy_sort_order` and `dns_suffix`, attributes its own type does not declare (Terraform fails when it is set); the chart sends the fields the variable declares, which ASO's 2025-05-01 type has |
| `function_app_uses_fc1`, `fc1_runtime_name`, `fc1_runtime_version`, `always_ready`, `maximum_instance_count`, `instance_memory_in_mb`, `storage_container_type`, `storage_container_endpoint`, `storage_authentication_type`, `storage_user_assigned_identity_id` | `functionAppConfig`. The module lower-cases the storage and authentication types; ASO's enums take ARM's casing (`blobContainer`, `SystemAssignedIdentity` ...), which the chart sends |
| `managed_identities` | `identity` |
| `deployment_slots` (in part), `deployment_slots_inherit_lock`, `all_child_resources_inherit_tags` | `SitesSlot`s with the slot module's body; the site's lock on a slot without one; the site's tags merged into a slot's |
| `custom_domains` (in part), `certificates` | `SitesHostNameBinding` (`sslState`, `thumbprint`), `Certificate` (`keyVaultReference`, `keyVaultSecretName`, `hostNames`, its own `tags`); a PFX upload's `pfx_blob` and `password` as `pfxBlob` and `password`, each a reference to a Kubernetes Secret, `{secretName, key}` ([secrets](../../../docs/secrets.md)); a string is refused, and Key Vault and a PFX together are refused, as in the module |
| `storage_shares_to_mount`, `slots_storage_shares_to_mount_sensitive_values` | `siteConfig.azureStorageAccounts` on the `Site` and on each `SitesSlot` (the module's `config_azurestorageaccounts`, which PUTs the same map), keyed by each mount's `name`: `type` (default `AzureFiles`), `accountName`, `shareName`, `mountPath`, and `accessKey` as a reference to a Kubernetes Secret, `{secretName, key}` ([secrets](../../../docs/secrets.md)): a site mount's `access_key`, a slot mount's key in `slots_storage_shares_to_mount_sensitive_values` by the mount's key, as in the module. A string is refused |
| `private_endpoints`, `private_endpoints_manage_dns_zone_group`, `private_endpoints_inherit_lock` | as above; as in the module, the site's endpoints take only their own lock (the slot module reads `private_endpoints_inherit_lock`) |
| `tags` | `spec.tags` |
| `lock`, `role_assignments`, `diagnostic_settings` | the AVM interfaces (avm-utl-interfaces 0.7.0; diagnostic settings v2) |
| `auth_settings_v2` | `SitesConfigAuthSettingsV2`: the module's body (`modules/config_authsettingsv2`, its defaults for the object's optional attributes), every identity provider; nulls left out, and `allowedPrincipals` and `jwtClaimChecks` as `{}` where the module sends their cleared shape. The config sections have no name of their own (Azure fixes it) and no DELETE: deleting the object leaves the last values on the site until the site goes |
| `logs` | `SitesConfigLogs`: `detailedErrorMessages`, `failedRequestsTracing`, the first `application_logs` entry's file system level and Blob Storage destination, and the first `http_logs` entry's file system retention and Blob Storage destination, as the module takes them. One entry only (each writes the site's one `logs` section). A Blob Storage destination's `sas_url` is a reference to a Kubernetes Secret, `{secretName, key}` ([secrets](../../../docs/secrets.md)); a string is refused |
| `sticky_settings` | `SitesConfigSlotConfigNames`: every entry's app setting and connection string names, flattened as the module does |
| `ftp_publish_basic_authentication_enabled`, `scm_publish_basic_authentication_enabled` | `false` renders the `ftp` or `scm` publishing credential policy with `allow: false`; `true` renders nothing, as in the module |
| `enable_telemetry`, `manage_connection_strings`, `zip_deploy_wait_duration` | accepted; nothing is sent (no telemetry, no connection strings, no zip deploy to wait for) |

### Not module inputs

| Value | Renders |
| --- | --- |
| `names.site` | the site's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name` and of the certificates' names, never of a name under `names`; checked against the 60-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

### Refused

| Variable | Kind | Why |
| --- | --- | --- |
| `retry`, `timeouts`, `ignore_body_changes`, `resource_types` | by-design | the azapi provider's mechanics: ASO retries itself and owns every field; Bundt sets a component's time limit; the API versions are the kinds' |
| `zip_deploy_file` | by-design | uploads application code, which a Package does not carry |
| `application_insights_connection_string`, `application_insights_key`, `storage_account_access_key`, `slot_sensitive_app_settings` | not-ported | secret values the module marks sensitive: how a component supplies one is the builder's decision |
| `connection_strings` | not-ported | a connection string's value is a secret (ASO takes it in plain text) |
| `kind` (in part) | not-ported | `logicapp` is refused: the module writes the storage account key into an app setting |
| `logic_app_node_version`, `logic_app_runtime_version`, `bundle_version`, `use_extension_bundle`, `storage_account_share_name` | not-ported | only a Logic App reads them; accepted at their defaults |
| `auth_settings`, `backup` | gap | `Microsoft.Web/sites/config` (`authsettings`, `backup`) has no ASO or aso-extensions kind (each has a PUT and no GET; aso-extensions `docs/plan.md` §8 Q13). The module writes `auth_settings` only without `auth_settings_v2`, which is mapped |
| `app_service_active_slot` | gap | a slot swap is an action (`slotsswap`), not a resource |
| `delete_empty_service_plan` (in part) | gap | `false` is refused: ASO sends no `deleteEmptyServerFarm` |
| `site_config` (in part) | not-ported | `application_insights_connection_string`, `application_insights_key`: secret values |
| `deployment_slots` (in part) | not-ported | a slot must set `ftp_publish_basic_authentication_enabled` and `webdeploy_publish_basic_authentication_enabled` to `true` (a slot's publishing policies have no kind; aso-extensions' are the site's); its `connection_strings`, `zip_deploy_file`, `site_config.application_insights_*` and `custom_domains.*.certificate_key` are refused |
| `custom_domains` (in part) | not-ported | `certificate_key`: the binding takes the thumbprint Azure computes for the certificate, which a render cannot read; set `thumbprint` |

Coverage: 81 of the module's 99 variables are accepted (6 of them in
part), 18 refused; 13 of its 14 outputs.

## Outputs

| Output | From |
| --- | --- |
| `name`, `resource_id`, `location` | the `Site`'s `azureName`, `status.id`, `location` |
| `resource_uri` | `status.defaultHostName` (null until Azure reports it) |
| `custom_domain_verification_id` | `status.customDomainVerificationId` (null until Azure reports it) |
| `system_assigned_mi_principal_id`, `identity_principal_id` | `status.identity.principalId`, null without a system-assigned identity |
| `kind`, `os_type` | the inputs |
| `active_slot` | the site's ID (`app_service_active_slot` is refused) |
| `deployment_slots` | `{<key>: {name, resource_id}}` of each `SitesSlot`, null without slots |
| `system_assigned_mi_principal_id_slots` | each slot's identity's principal ID, for slots that have one |
| `private_endpoints` | each endpoint's ID (the module gives the whole resources), null without endpoints |

Not an output: `resource` (the whole site, which the module marks
sensitive).

## From Terraform

A module block's arguments are the values (per slot, the two publishing
flags `true`). ASO
adopts a site that exists when an object with its name is applied, so keep
the name and leave `namePrefix` empty; set `deletion_policy: ABANDON` for
the first apply, `terraform state rm` the module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-web-site`](https://github.com/Azure/terraform-azurerm-avm-res-web-site/tree/v0.24.1)
at v0.24.1 (`56c704e9`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence, the date last synced and the
refusals.

## Tests

`task test CHART=avm-res-web-site`: render cases `basic`, `windows` (a
Windows .NET app with most site variables, a certificate, a custom domain,
a private endpoint and the interfaces), `function` (identity-based host
storage), `flex` (Flex Consumption), `slots`, `names`, `config` (authentication v2,
logs, sticky settings, both publishing policies), `logs-blob` (logs to
Blob Storage, the SAS URLs from a Secret), `secrets` (a certificate
uploaded as a PFX with its password, and storage mounts on the site and a
slot, their access keys, all from Secrets) and `mock` (its application
logs' SAS URL, a PFX certificate with its password and a storage mount's
access key from Secrets the fake-cloud run makes), each
validated against ASO v2.22.0's CRD schemas and aso-extensions' copied CRDs
(`crds/aso-extensions`), and the refusals in `tests/*.fail.yaml`.

`task test-mock-azure` applies `tests/mock.values.yaml` (a Linux Python web
app on a plan by ARM ID, with a slot, a custom domain, a Key Vault
certificate and the site's lock inherited by the slot) to aso-extensions'
fake cloud: passed on 2026-11-13 (stock ASO v2.22.0 and aso-extensions'
manager at `b9beb5b` against fakearm, run `off-catalog-1113080724-28823`):
all 6 objects (the `Site`, `SitesSlot`, `SitesHostNameBinding`,
`Certificate` and two locks) Ready and deleted, the outputs evaluated.
`resource_uri` and `custom_domain_verification_id` evaluated to null: the
fake Resource Manager does not compute a site's `defaultHostName` or
`customDomainVerificationId` (a gap for aso-extensions'
`pkg/fakecloud/arm/computed.go`); the principal IDs, slot map and IDs did
evaluate.

`task test-live-azure` (case `web`, only when named) applies a Linux B1
plan with the serverfarm chart and then a Python web app on it. It is not
in the default cases and has not been run: the sandbox subscription's App
Service quota is 0 in eastus2 for B1 and F1, and Azure refused the plan
alone (the serverfarm chart's `asp` case, runs `cat11130326bbfc` and
`cat111303502c33`); raising the quota is a subscription-scope change the
live rules forbid (docs/azure.md, "8. Charts").

0.2.0 against the fake cloud (stock ASO v2.22.0, aso-extensions' manager
at `b9beb5ba`), run `off-catalog-1113105656-11634` (2026-11-13): the site, slot, the slot's private endpoint with its DNS zone group and lock, hostname binding, certificate and locks
Ready and deleted, the outputs evaluated.

aso-extensions `3d9ba27` computes a site's `defaultHostName` and
`customDomainVerificationId`: run `off-catalog-1113155314-18721` (2026-11-13), all 9 objects Ready
and deleted, every output evaluated, `resource_uri`
(`catalog-app.azurewebsites.net`) and `custom_domain_verification_id`
among them, no longer null.

## Changes

- **0.5.0** (2026-11-14): a certificate's `pfx_blob` and `password`
  (a PFX upload), `storage_shares_to_mount` and
  `slots_storage_shares_to_mount_sensitive_values` (with a slot's
  `storage_shares_to_mount`) are mapped, each secret a reference to a
  Kubernetes Secret, `{secretName, key}` (docs/secrets.md, the builder's
  decision).
- **0.4.0** (2026-11-14): a log's `azure_blob_storage` is mapped, its
  `sas_url` a reference to a Kubernetes Secret, `{secretName, key}`
  (docs/secrets.md, the builder's decision).
- **0.3.0** (2026-11-13): `auth_settings_v2`, `logs`, `sticky_settings`,
  `ftp_publish_basic_authentication_enabled` and
  `scm_publish_basic_authentication_enabled` are mapped to aso-extensions'
  `SitesConfigAuthSettingsV2`, `SitesConfigLogs`,
  `SitesConfigSlotConfigNames` and `SitesBasicPublishingCredentialsPolicyFtp`
  and `...Scm` (aso-extensions `8d7f8c2`). `ftp_publish_basic_authentication_enabled`
  no longer has to be `true`: its default, `false`, renders the FTP policy.
- **0.2.0** (2026-11-13): a deployment slot's `private_endpoints` render
  ASO `PrivateEndpoint`s to the site's `sites-<slot>` subresource, with
  their DNS zone groups, locks and role assignments.
- **0.1.0** (2026-11-13): the port.
