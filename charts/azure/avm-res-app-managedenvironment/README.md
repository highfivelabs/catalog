# avm-res-app-managedenvironment

An Azure Container Apps environment with its virtual network, workload
profiles, logs destination, custom domain, peer authentication and
encryption, identities, and its certificates, managed certificates, Dapr
components, storages, Java components, HTTP route configurations,
maintenance configurations, lock, role assignments and diagnostic
settings, as Azure Service Operator (ASO) and aso-extensions objects. A
port of the Azure Verified Module
[`avm-res-app-managedenvironment`](https://github.com/Azure/terraform-azurerm-avm-res-app-managedenvironment/tree/c6709095a923c7c3d1fb54da0d43cb56d95b731e)
at v0.6.0 (`c6709095`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-app-managedenvironment`
(`package.yaml`). Checked against ASO v2.22.0's CRDs and aso-extensions'
at `b9beb5b`.

## Example

```yaml
name: cae-example
location: eastus2
resource_group_name: rg-example
subscription_id: <id>
zone_redundant: false
```

renders one ASO `ManagedEnvironment` `cae-example`, a Consumption-only
environment with no logs destination (`tests/golden/basic.yaml`). The
module's default `zone_redundant: true` needs an infrastructure subnet
(`vnet_configuration`); Azure refuses it without one.

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.this` | always | `ManagedEnvironment` (`app.azure.com/v20250101`), `managed_environment`, owned by the resource group |
| `module.certificates` | one per entry | `ManagedEnvironmentsCertificate` (aso-extensions, `app.azure.hfl.dev/v20250101`), `certificate:<key>` |
| `module.dapr_components` | one per entry | `ManagedEnvironmentsDaprComponent` (aso-extensions, `v20250101`), `dapr_component:<key>` |
| `module.storages` | one per entry | `ManagedEnvironmentsStorage` (aso-extensions, `v20250101`), `storage:<key>` |
| `module.managed_certificates` | one per entry | `ManagedEnvironmentsManagedCertificate` (aso-extensions, `v20250101`), `managed_certificate:<key>` |
| `module.java_components` | one per entry | `ManagedEnvironmentsJavaComponent` (aso-extensions, `v20250101`), `java_component:<key>` |
| `module.http_route_configs` | one per entry | `ManagedEnvironmentsHttpRouteConfig` (aso-extensions, `v20260101`), `http_route_config:<key>` |
| `module.maintenance_configurations` | one per entry | `ManagedEnvironmentsMaintenanceConfiguration` (aso-extensions, `v20260101`), `maintenance_configuration:<key>` |
| `azapi_resource.lock` | `lock` set | `ManagementLock` (aso-extensions), `lock`, named `lock-<kind>` and with the module's notes unless given |
| `azapi_resource.role_assignments` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `azapi_resource.diagnostic_settings` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` |
| `module.dapr_subscriptions`, `module.dot_net_components` | never | refused: no kind (below) |
| `time_sleep.lock_removal`, the role definition lookup, the workspace's customer ID and shared key lookups, telemetry | never | not ported: ASO retries a delete a lock still blocks and resolves a role by name itself; the shared key is a secret (below) |

Every child is owned by the environment and named as the module names it
(its `name`), without the `namePrefix`: its name is scoped to the
environment, whose name carries the prefix.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`), with the module's validations.
Where the module folds a deprecated input into a newer one (its
`effective_*` locals), the chart folds it the same way, the newer winning.

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` |
| `resource_group_name` (required), `parent_id` | `owner.armId`: `parent_id` when set, else `/subscriptions/<subscription_id>/resourceGroups/<resource_group_name>`, or `resource_group_name` itself when it is a group's ID |
| `kind` | `kind` |
| `managed_identities` | `identity` |
| `app_logs_configuration`, `log_analytics_workspace_destination` (deprecated) | `appLogsConfiguration.destination`: `azure-monitor`, or none (`{}`). `log-analytics` is refused (below) |
| `custom_domain_configuration`; `custom_domain_dns_suffix`, `custom_domain_certificate_key_vault_url`, `custom_domain_certificate_key_vault_identity` (deprecated) | `customDomainConfiguration`: `dnsSuffix` and the Key Vault certificate (`certificateKeyVaultProperties`: the identity by ID, or `System` as `wellKnownName`, and the secret's URL) |
| `infrastructure_resource_group`, `infrastructure_resource_group_name` (deprecated) | `infrastructureResourceGroup` |
| `vnet_configuration`; `infrastructure_subnet_id`, `internal_load_balancer_enabled` (deprecated) | `vnetConfiguration`, the subnet by ID (`infrastructureSubnetReference`) |
| `peer_authentication`, `peer_authentication_enabled` (deprecated) | `peerAuthentication.mtls.enabled` |
| `peer_traffic_configuration`, `peer_traffic_encryption_enabled` (deprecated) | `peerTrafficConfiguration.encryption.enabled` |
| `workload_profiles`, `workload_profile` (deprecated) | `workloadProfiles`: the profiles given less any Consumption one, then the Consumption profile, as the module sends them (Azure makes it itself) |
| `zone_redundant` (default `true`), `zone_redundancy_enabled` (deprecated) | `zoneRedundant` |
| `dapr_configuration`, `keda_configuration` | accepted: both are empty objects (`object({})`), and the module sends them as `{}`, which carries no setting. ASO's type has neither field (Azure reports the Dapr and KEDA versions in status) |
| `tags` | `spec.tags` (the environment's only; a certificate's and a managed certificate's own `tags` are theirs, as in the module) |
| `certificates` | `ManagedEnvironmentsCertificate`: `name`, `location`, `tags`, the Key Vault certificate (`certificate_key_vault_properties`). `password` and `value` are refused; `password_version` and `value_version` are accepted and do nothing, as in the module without a value |
| `dapr_components` | `ManagedEnvironmentsDaprComponent`: `component_type`, `dapr_components_version` (`version`), `ignore_errors`, `init_timeout`, `metadata` (a value or a secret's name), `scopes`, `secret_store_component`, `secrets` as Key Vault references (`key_vault_url`, `identity`). A secret's `value` is refused. `secrets_version` is required with `secrets`, as in the module, and does nothing: ASO sends the whole body on every change |
| `storages` | `ManagedEnvironmentsStorage`: `azure_file` (`access_mode`, `account_name`, `share_name`) and `nfs_azure_file` (`access_mode`, `server`, `share_name`). The account key and `azure_file.account_key_vault_properties` are refused, so an Azure Files share cannot be given a credential: use NFS |
| `managed_certificates` | `ManagedEnvironmentsManagedCertificate`: `name`, `location`, `subject_name`, `domain_control_validation`, `tags` |
| `java_components` | `ManagedEnvironmentsJavaComponent`: `SpringBootAdmin`, `SpringCloudConfig` or `SpringCloudEureka` (the kind's three component types), with `configurations`, `scale` and `service_binds` (the service by ID) |
| `http_route_configs` | `ManagedEnvironmentsHttpRouteConfig`: `custom_domains` (the certificate by ID) and `rules` (routes and their targets) |
| `maintenance_configurations` | `ManagedEnvironmentsMaintenanceConfiguration`: `scheduled_entries` |
| `lock` | the AVM lock interface, with the module's default name (`lock-<kind>`) and notes |
| `role_assignments` | the AVM interface: an entry's `name` is the assignment's GUID; a role by name (ASO resolves it) or ID; `skip_service_principal_aad_check` without a `principal_type` sends `ServicePrincipal`, as the module does |
| `diagnostic_settings` | the AVM interface: log groups (default `allLogs`), log categories, metric categories (default `AllMetrics`; an empty list sends none), the destination type (`Dedicated`, the default, is not sent, as the module does); a setting without a name is `diag-<name>` |
| `enable_telemetry` | accepted; the chart sends no telemetry |

### Not module inputs

| Value | Renders |
| --- | --- |
| `subscription_id` | the subscription of `resource_group_name` when it is a name and `parent_id` is not set: ASO's owner is a resource ID |
| `names.managedEnvironment` | the environment's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name`, never of a name under `names`; checked against the 60-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

### Refused when set

Secret values are the builder's decision (ASO takes each as a
`SecretReference` to a Kubernetes Secret, and how a component supplies one
is not settled); Key Vault references, which hold no value, are taken.

| Variable | Kind | Why |
| --- | --- | --- |
| `ignore_body_changes` | gap | ASO applies every property it is given and cannot leave a path to another writer |
| `resource_types` | by-design | ASO's and aso-extensions' kinds fix the API versions |
| `retry` | by-design | ASO retries every failed request itself |
| `timeouts` | by-design | ASO has no per-request timeouts; Bundt sets a component's time limit |
| `app_insights_configuration`, `connection_string`, `connection_string_version` | gap | ASO's `ManagedEnvironment` is at ARM API version 2025-01-01, which has no `appInsightsConfiguration` (the module sends 2025-10-02-preview) |
| `availability_zones` | gap | likewise no `availabilityZones` |
| `disk_encryption_configuration` | gap | likewise no `diskEncryptionConfiguration` |
| `ingress_configuration` | gap | likewise no `ingressConfiguration` |
| `open_telemetry_configuration`, `key`, `key_version` | gap | likewise no `openTelemetryConfiguration` |
| `public_network_access`, `public_network_access_enabled` | gap | likewise no `publicNetworkAccess` |
| `dapr_subscriptions` | gap | no ASO or aso-extensions kind for `Microsoft.App/managedEnvironments/daprSubscriptions` |
| `dot_net_components` | gap | no ASO or aso-extensions kind for `Microsoft.App/managedEnvironments/dotNetComponents` |
| `log_analytics_workspace` | not-ported | the module reads the workspace's primary shared key and sends it: a secret |
| `shared_key`, `shared_key_version`, `log_analytics_workspace_primary_shared_key`, `log_analytics_workspace_customer_id` | not-ported | a Log Analytics destination needs the workspace's shared key: a secret |
| `certificate_password`, `certificate_value` (and their `_version`), `custom_domain_certificate_password`, `custom_domain_certificate_value` | not-ported | the custom domain certificate's password and blob: secrets (reference the certificate in Key Vault instead) |
| `dapr_ai_connection_string`, `dapr_ai_instrumentation_key` (and their `_version`), `dapr_application_insights_connection_string` | not-ported | Application Insights credentials for Dapr: secrets |

Accepted in part: `app_logs_configuration` and
`log_analytics_workspace_destination` (not `log-analytics`, which needs the
shared key), `custom_domain_configuration` (not `certificate_value`),
`certificates` (not `password` or `value`), `dapr_components` (not a
secret's `value`), `storages` (not the account key, a secret, nor
`azure_file.account_key_vault_properties`, which aso-extensions'
`ManagedEnvironmentsStorage` at 2025-01-01 lacks), `java_components` (not
`Nacos` or `SpringCloudGateway`, nor `ingress`, which aso-extensions'
`ManagedEnvironmentsJavaComponent` at 2025-01-01 lacks).

Logs without a secret: `app_logs_configuration: {destination:
azure-monitor}` and a `diagnostic_settings` entry to the workspace.

## Outputs

| Output | From |
| --- | --- |
| `name` | the environment's `azureName` |
| `resource_id`, `id` (deprecated) | its `status.id` |
| `default_domain`, `static_ip_address`, `event_stream_endpoint`, `infrastructure_resource_group` | its status (`defaultDomain`, `staticIp`, `eventStreamEndpoint`, `infrastructureResourceGroup`), null until Azure reports them |
| `docker_bridge_cidr`, `platform_reserved_cidr`, `platform_reserved_dns_ip_address` | `status.vnetConfiguration`, null without a network |
| `custom_domain_verification_id` | `status.customDomainConfiguration.customDomainVerificationId` |
| `managed_identities` | `status.identity` (`type`, `principalId`, `tenantId`, `userAssignedIdentities`), `{}` without one |
| `certificate_resource_ids`, `dapr_component_resource_ids`, `managed_certificate_resource_ids`, `storage_resource_ids` | each child's key to `{id: <its status.id>}`, as the module gives them |

Not outputs: `dapr_ai_instrumentation_key`, which ASO's status does not
carry (and a secret besides), and `resource`, the whole azapi object.

## From Terraform

A module block's arguments are the values, plus `subscription_id` when
`resource_group_name` is a name and `parent_id` is not set. Drop the secret
inputs: send logs to Azure Monitor (above), and give certificates and Dapr
secrets as Key Vault references. ASO adopts an environment that exists
when an object with its name is applied, so keep the name and leave
`namePrefix` empty; set `deletion_policy: ABANDON` for the first apply,
`terraform state rm` the module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-app-managedenvironment`](https://github.com/Azure/terraform-azurerm-avm-res-app-managedenvironment/tree/v0.6.0)
at v0.6.0 (`c6709095`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-app-managedenvironment`: render cases `basic`,
`deprecated`, `full`, `names` and `mock`, each validated against ASO
v2.22.0's CRD schemas and the aso-extensions CRDs copied in
`crds/aso-extensions`, and the refusals in `tests/*.fail.yaml`.
`task test-mock-azure` applies `tests/mock.values.yaml` (the environment
with a Key Vault certificate, a Dapr component, an NFS storage, a managed
certificate, a Eureka Java component, an HTTP route configuration, a
maintenance configuration and a lock) to aso-extensions' fake cloud: passed
on 2026-11-13 (stock ASO against fakearm at `b9beb5b`, run
`off-catalog-1113080132-28448`: 9 objects Ready and deleted, the outputs
evaluated; the fake computes no domain or static IP, so those are null
there).

`task test-live-azure` (case `cae`) applies a Consumption-only environment
(no network, no logs destination, not zone redundant) with one Dapr
component that names no secret, in `AZURE_LIVE_CAE_LOCATION` (centralus by
default: the sandbox subscription may hold one environment per region, and
the container app case makes one in the run's location). It passed on
2026-11-13 (run `cat11130845e67b`, VM `off-catalog-1113084135-19478`): 2
objects Ready, the outputs evaluated (Azure's default domain, static IP,
event stream endpoint and custom domain verification ID among them),
deleted, Azure answering 404, nothing of the run left. Creating and
deleting the environment took about 35 minutes in all (`CASE_TIMEOUT`
2400 seconds). The first run (`cat11130805a424`) got the same objects
Ready and the outputs evaluated, then stopped before its report: the live
script's report line read `pre-live.json`, which a case without objects
made first does not have, and errexit ended the run (fixed in
`hack/azure-live.sh`); its cleanup deleted what was left.

## Changes

- **0.1.0** (2026-11-13): the port.
