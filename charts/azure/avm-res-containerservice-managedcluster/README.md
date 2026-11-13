# avm-res-containerservice-managedcluster

An Azure Kubernetes Service (AKS) cluster with its agent pools,
maintenance configurations, managed namespaces, private endpoints and the
module's monitoring and alerting, and its lock, role assignments and
diagnostic settings, as Azure Service Operator (ASO) objects. A port of the Azure Verified Module
[`avm-res-containerservice-managedcluster`](https://github.com/Azure/terraform-azurerm-avm-res-containerservice-managedcluster/tree/1925e0490783695919ab21e4c73ebf1f53d95e2d)
at v0.9.0 (`1925e049`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-containerservice-managedcluster`
(`package.yaml`). Checked against ASO v2.22.0's CRDs and aso-extensions'
`ManagedClustersManagedNamespace` CRD.

## Example

```yaml
name: aks-example
location: eastus2
parent_id: /subscriptions/<id>/resourceGroups/rg-example
default_agent_pool:
  vm_size: Standard_D2ds_v5
```

renders the ASO `ManagedCluster` `aks-example` with a system-assigned
identity and its default agent pool `systempool` (three nodes), and the
`ManagedClustersAgentPool` that keeps that pool's settings current
(`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.this` (`Microsoft.ContainerService/managedClusters`) | always | `ManagedCluster` (`containerservice.azure.com/v20260501`, or `v20251002preview`, below), `managed_cluster`, owned by `parent_id` |
| `azapi_update_resource.default_agent_pool` | unless `sku.name` is `Automatic` | `ManagedClustersAgentPool` (`v20251002preview`), `default_agent_pool`, never deleted on its own (`detach-on-delete`): the pool goes with the cluster, as the module's update resource never deletes it |
| `azapi_update_resource.kubernetes_version` | `kubernetes_version` set | the cluster's `kubernetesVersion` |
| `module.nodepools` (`managedClusters/agentPools`) | one per `agent_pools` entry, unless its `output_data_only` | `ManagedClustersAgentPool` (`v20251002preview`), `agent_pool:<key>` |
| `module.maintenanceconfiguration` | one per entry | `MaintenanceConfiguration` (`v20260501`), `maintenance_configuration:<key>` |
| `module.namespace` (`managedClusters/managedNamespaces`) | one per entry | `ManagedClustersManagedNamespace` (aso-extensions, `containerservice.azure.hfl.dev/v20260501`; ASO has none), `namespace:<key>` |
| `azapi_resource.lock` | `lock` set | `ManagementLock` (aso-extensions), `lock`, with the module's default notes |
| `azapi_resource.role_assignments` | one per entry | `RoleAssignment`, `role-assignment-<key>` |
| `azapi_resource.diagnostic_settings` | one per entry | `DiagnosticSetting`, `diagnostic-setting-<key>`: the module's logs (its groups, the others of `allLogs` and `audit` sent disabled; or its categories), named `diag-<name>` by default |
| `azapi_resource_action` (`listClusterUserCredential`, `listClusterAdminCredential`) | never | not ported: the kubeconfig is a secret (ASO can write it to a Kubernetes Secret through `operatorSpec.secrets`, which this chart does not set) |
| `azapi_resource.private_endpoints` | one per `private_endpoints` entry | `PrivateEndpoint` (`network.azure.com/v20250301`), `private_endpoint:<key>`: `pe-<name>` unless named, owned by `parent_id` or the entry's `resource_group_name` (in the cluster's subscription), to the cluster's `management` subresource by reference |
| `azapi_resource.private_dns_zone_groups` | an entry with `private_dns_zone_resource_ids`, when `private_endpoints_manage_dns_zone_group` | `PrivateEndpointsPrivateDnsZoneGroup`, `private_endpoint:<key>/dns_zone_group`, a zone configuration per zone, named for it |
| `module.monitoring` | `onboard_monitoring` | the managed Prometheus `DataCollectionEndpoint` and `DataCollectionRule` (`insights.azure.com/v1api20240311`, both `MSProm-<location>-<cluster>`, cut to 44 characters with a hash as the module cuts it; `monitoring:dce_msprom`, `monitoring:dcr_msprom`), their `DataCollectionRuleAssociation`s with the cluster (`dcr-<cluster>`, `configurationAccessEndpoint`), the three recording rule groups (`PrometheusRuleGroup`, `alertsmanagement.azure.com/v20230301`, `<group> - <cluster>`, the module's 48 rules verbatim in `templates/_promrules.tpl`), and the Container Insights `DataCollectionRule` (`MSCI-<location>-<cluster>`) and its association (`msci-<cluster>`) |
| `module.alerting` | `onboard_alerts` | `ActionGroup` (`insights.azure.com/v1api20230101`) `RecommendedAlertRules-AG-1` (with the namePrefix), emailing `alert_email`; the CPU and memory `MetricAlert`s (`insights.azure.com/v1api20180301`) on the cluster |
| telemetry | never | not ported |

**API versions.** The module's cluster is at 2026-03-01, and at
2026-03-02-preview when `kube_proxy_config`,
`ingress_profile.application_load_balancer` or
`security_profile.image_integrity` is set; ASO has 2026-05-01 and
2025-10-02-preview, and the chart takes them the same way. The preview
lacks `hosted_system_profile`'s subnets and
`ingress_profile.web_app_routing.gateway_api_implementations`, so either
with a preview-only setting stops the render. The module's agent pools
are at 2026-01-02-preview; the chart's at ASO's 2025-10-02-preview, the
only version with `kubelet_config.seccomp_default`,
`gpu_profile.driver_type`, `node_customization_profile`,
`node_initialization_taints`, `upgrade_settings.max_blocked_nodes`,
`upgrade_settings_blue_green` and `upgrade_strategy`.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`). The module turns its snake_case
inputs into the ARM body's camelCase field by field; the chart does the
same (`templates/_aks.tpl`, `aks.conv`), with the module's irregular
names (`osSKU`, `countIPv6`, `trustedCa`, the autoscaler profile's
kebab-case keys), and gives every ARM ID ASO's reference (`vnet_subnet_id`
is `vnetSubnetReference.armId`, a load balancer's `public_ips[].id` is
`reference.armId`, `dns_zone_resource_ids` is `dnsZoneResourceReferences`).

| Module input | ASO |
| --- | --- |
| `name`, `location`, `parent_id` (required) | `azureName`, `location`, `owner.armId` |
| `aad_profile`, `ai_toolchain_operator_profile`, `api_server_access_profile`, `auto_scaler_profile`, `auto_upgrade_profile`, `azure_monitor_profile`, `bootstrap_profile`, `disable_local_accounts`, `disk_encryption_set_id`, `enable_rbac`, `extended_location`, `fqdn_subdomain`, `hosted_system_profile`, `http_proxy_config`, `ingress_profile`, `kind`, `kube_proxy_config` (`networkProfile.kubeProxyConfig`), `kubernetes_version`, `linux_profile`, `metrics_profile`, `network_profile`, `node_provisioning_profile`, `node_resource_group`, `node_resource_group_profile`, `oidc_issuer_profile`, `pod_identity_profile`, `private_link_resources`, `public_network_access`, `security_profile`, `service_mesh_profile`, `service_principal_profile`, `sku`, `storage_profile`, `support_plan`, `upgrade_settings`, `windows_profile`, `workload_auto_scaler_profile` | the cluster's properties of the same name |
| `dns_prefix` | `dnsPrefix`; without it or `fqdn_subdomain`, 10 characters of the SHA-256 of the release and `name` (the module: a `random_string`, as stable once made) |
| `managed_identities` | `identity`: `SystemAssigned` or `UserAssigned` (an AKS cluster has one or the other) |
| `identity_profile` | `identityProfile.kubeletidentity.resourceReference` |
| `addon_profile_oms_agent`, `addon_profile_azure_policy`, `addon_profile_ingress_application_gateway`, `addon_profile_key_vault_secrets_provider`, `addon_profile_confidential_computing`, `addon_profiles_extra` | `addonProfiles` (`omsagent`, `azurepolicy`, `ingressApplicationGateway`, `azureKeyvaultSecretsProvider`, `ACCSGXDevicePlugin`, and the extra ones by their keys), configs as strings |
| `default_agent_pool` | `agentPoolProfiles[0]` (mode `System`, `Linux`, three nodes by default, the cluster's `tags`, `kubernetes_version` as its version) without the properties the module leaves to its update resource, and the default pool's `ManagedClustersAgentPool` with all of them |
| `agent_pools` | a `ManagedClustersAgentPool` each; `count_of` is not sent when both `min_count` and `max_count` are |
| `maintenanceconfiguration` | a `MaintenanceConfiguration` each |
| `namespace` | a `ManagedClustersManagedNamespace` each, at the entry's `location` or the cluster's |
| `tags` | the cluster's and the default pool's `tags` |
| `lock`, `role_assignments`, `diagnostic_settings` | the AVM interfaces |
| `enable_telemetry` | accepted; the chart sends no telemetry |

An Automatic cluster (`sku.name: Automatic`) takes only the properties
the module sends for one: no agent pool, no Azure Policy or Key Vault
add-on, and its `network_profile` only when `outbound_type` is not
`loadBalancer`.

**Refused** (`upstream.yaml`): a secret value anywhere
(`aad_profile.server_app_secret`, `service_principal_profile.secret`,
`windows_profile_password` and its `_version`: how a component supplies a
secret is not settled); `enable_os_disk_full_caching` and
`gpu_profile.nvidia` on a pool, and an agent pool's
`delete_options.ignore_pod_disruption_budget` (gaps: ASO has none of
them); `timeouts`, `cluster_timeouts`,
`agentpool_timeouts`, `retry`, `ignore_body_changes`, `resource_types`,
`create_agentpools_before_destroy` (by design: ASO does these its own
way).

`private_endpoints`: per entry `subnet.reference.armId`,
`customNetworkInterfaceName`, one `privateLinkServiceConnections` entry
(`pse-<name>` unless named, `groupIds: [management]`), `ipConfigurations`
(group and member `management`), `applicationSecurityGroups`, `location`,
`tags`. An entry's `lock` and `role_assignments` are accepted and ignored,
as the module ignores them. `onboard_monitoring` needs the OMS add-on's
workspace (the module's validation) and `prometheus_workspace_id` (the
module sends it as the Prometheus rule's destination and the rule groups'
scope; the chart stops the render without it, where the module would send
null). The monitoring and alerting objects take the cluster's `tags`; a
name the module derives from `basename(cluster ID)` takes the cluster's
Azure name, with the namePrefix.

The module's validations stop the render with its messages (the name's
pattern, the OMS and application gateway add-ons' IDs, `onboard_monitoring`
without the OMS workspace, `onboard_alerts` without `alert_email`, a hosted system
profile only on Automatic, the kubelet identity's one user-assigned
identity, the kube-proxy settings, the default pool's seccomp profile, an
agent pool named like the default one, a diagnostic setting with both
categories and groups).

### Not module inputs

| Value | Renders |
| --- | --- |
| `names.managedCluster` | the cluster's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name` (never of a name under `names`); checked against the 63-character limit. Agent pools, maintenance configurations and namespaces are named inside the cluster |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

## Outputs

| Output | From |
| --- | --- |
| `resource_id`, `name` | the cluster's `status.id`, `spec.azureName` |
| `fqdn`, `azure_portal_fqdn`, `private_fqdn`, `current_kubernetes_version`, `max_agent_pools`, `node_resource_group_name`, `oidc_issuer_profile_issuer_url`, `kubelet_identity`, `identity_principal_id`, `identity_tenant_id` | the cluster's status, null until Azure sets it |
| `node_resource_group_id` | `/subscriptions/<parent_id's>/resourceGroups/<nodeResourceGroup>`, as the module builds it |
| `ingress_app_object_id`, `key_vault_secrets_provider_identity` | the add-ons' identities |
| `ingress_profile_web_app_routing_identity`, `ingress_profile_application_load_balancer_identity` | the ingress profile's identities, `{}` without |
| `network_profile_load_balancer_profile_effective_outbound_ips`, `network_profile_nat_gateway_profile_effective_outbound_ips` | `[]` without |
| `agentpool_resource_ids`, `namespace_resource_ids` | `{<key>: {resource_id, name}}` |
| `data_collection_endpoint_id`, `data_collection_endpoint_name` | the managed Prometheus data collection endpoint's `status.id` and name; null without `onboard_monitoring` |

Not outputs: `kube_config`, `kube_admin_config` and `cluster_ca_certificate`
(the kubeconfig is a secret).

## From Terraform

A module block's arguments are the values, unchanged. ASO adopts a
cluster, agent pool, maintenance configuration or namespace that exists
when an object with its name is applied, so keep the names and leave
`namePrefix` empty; set `dns_prefix` to the cluster's (the module's random
one is in its state); set `deletion_policy: ABANDON` for the first apply,
`terraform state rm` the module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-containerservice-managedcluster`](https://github.com/Azure/terraform-azurerm-avm-res-containerservice-managedcluster/tree/v0.9.0)
at v0.9.0 (`1925e049`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-containerservice-managedcluster`: render cases
`basic`, `full` (every stable setting, a second and a spot pool, a
maintenance window, a namespace, the interfaces, a private endpoint,
monitoring and alerting), `monitoring` (a long name's cut data collection
names, an endpoint whose zone group is left to others), `preview`,
`automatic`, `names` and `mock`, each validated against ASO v2.22.0's
CRD schemas and aso-extensions' CRDs, and the refusals in
`tests/*.fail.yaml`. Not applied live: an AKS cluster makes its node
resource group (`MC_...`) outside the sandbox's one resource group, which
the live identity may not reach (`docs/azure.md`, "8. Charts").
`tests/mock.values.yaml` against the fake cloud (stock ASO v2.22.0,
aso-extensions' fakearm at `b9beb5ba`): the cluster, both agent pools and
the maintenance configuration Ready and deleted, the outputs evaluated
(run `off-catalog-1112234355-26788`, 2026-11-12).

0.2.0 against the fake cloud (stock ASO v2.22.0, aso-extensions' manager
at `b9beb5ba`), run `off-catalog-1113105656-11634` (2026-11-13): the cluster, both pools, the maintenance configuration, the private endpoint and its DNS zone group, the data collection endpoint, rules and associations, the three Prometheus rule groups, the action group and both metric alerts
Ready and deleted, the outputs evaluated.

## Changes

- **0.2.0** (2026-11-13): `private_endpoints` (with
  `private_endpoints_manage_dns_zone_group`), `onboard_monitoring` (with
  `prometheus_workspace_id`) and `onboard_alerts` (with `alert_email`)
  render the module's private endpoints, monitoring and alerting objects;
  new outputs `data_collection_endpoint_id` and
  `data_collection_endpoint_name`.
- **0.1.0** (2026-11-12): the port.
