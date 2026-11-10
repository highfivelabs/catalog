# gke-cluster

A GKE cluster, Standard with n node pools or Autopilot, public or private,
with its node service account and that account's grants, as Config
Connector objects. A port of terraform-google-modules'
[`kubernetes-engine`](https://registry.terraform.io/modules/terraform-google-modules/kubernetes-engine/google)
module family at v47.0.0 (`a19597ac`), Apache-2.0, Copyright Google LLC:
[`modules/beta-private-cluster`](https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/tree/a19597ac18ad833d224448e2954df93095b8ce9d/modules/beta-private-cluster)
for Standard and
[`modules/beta-autopilot-private-cluster`](https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/tree/a19597ac18ad833d224448e2954df93095b8ce9d/modules/beta-autopilot-private-cluster)
for Autopilot. Bundt Package `gcp-gke-cluster` (`package.yaml`). Checked
against Config Connector v1.160.0.

## Why one chart

The module ships eleven cluster variants. Their inputs nest: every input of
the root module, `private-cluster` and `beta-public-cluster` is an input of
`beta-private-cluster`, the `*-update-variant` modules have exactly their
base module's inputs, and the two Autopilot variants have a subset of
`beta-private-cluster`'s plus two of their own. Only three shared inputs
differ between the families, and only in their defaults or type
(`dns_cache`, `enable_vertical_pod_autoscaling`, `node_pools_cgroup_mode`).
So one chart takes every input under its own name, and one value, `mode`,
says which family it renders. Split charts would repeat about a hundred
inputs and their templates. The 56 inputs only Standard has are refused in
Autopilot mode when set, so the single chart stays readable.

"Private" is not a separate switch: it is the module's own
`enable_private_nodes` (default `true`, as in `beta-private-cluster`). The
public variants are the same chart with `enable_private_nodes: false`.

| Terraform module (`source = ".../kubernetes-engine/google//modules/<x>"`) | Chart values |
| --- | --- |
| root module (`.../kubernetes-engine/google`) | `mode: standard`, `enable_private_nodes: false` |
| `private-cluster`, `private-cluster-update-variant` | `mode: standard` (default) |
| `beta-public-cluster`, `beta-public-cluster-update-variant` | `mode: standard`, `enable_private_nodes: false` |
| `beta-private-cluster`, `beta-private-cluster-update-variant` | `mode: standard` (the defaults) |
| `beta-autopilot-private-cluster` | `mode: autopilot` |
| `beta-autopilot-public-cluster` | `mode: autopilot`, `enable_private_nodes: false` |
| `safer-cluster*`, `gke-standard-cluster`, `gke-autopilot-cluster`, `gke-node-pool` | not covered: other interfaces (see "Not ported") |

The `*-update-variant` modules differ from their base only in how Terraform
replaces a node pool (create before destroy, with a random suffix on the
pool's name). Config Connector updates a node pool in place where GKE can,
and a pool's name is its entry's `name`, so nothing in the values differs.

Every other input keeps its name, type and default: a module block's
arguments become the values one to one. For the public variants, whose
defaults are those of the private one minus the private inputs, leave the
private inputs out.

## Mode

`mode: standard` (the default) renders the `beta-private-cluster` cluster:
a `ContainerCluster`, one `ContainerNodePool` per entry of `node_pools` and
`windows_node_pools`, and the node service account. `mode: autopilot`
renders the `beta-autopilot-private-cluster` cluster (`enableAutopilot:
true`, no node pools; GKE manages nodes, network policy, logging and
monitoring services and most add-ons) and the same service account.

- **Standard-only inputs in Autopilot mode** are refused when they differ
  from their defaults, naming the input (`node_pools`, `cluster_autoscaling`,
  `network_policy`, ... 56 in all, the list in `templates/refused.yaml`).
  `allow_net_admin` and `default_compute_class_enabled` are refused in
  Standard mode.
- **Mode-dependent defaults**: `dns_cache` and
  `enable_vertical_pod_autoscaling` default to `null`, which takes each
  module's own default: `false` in Standard, `true` in Autopilot. Set them to
  carry a value either way.
- **`node_pools_cgroup_mode`** is a map by node pool in Standard (the
  module's `map(string)`) and a string in Autopilot (its twin's `string`).

**Changing mode replaces the cluster.** GKE cannot convert a Standard
cluster to Autopilot or back, and `spec.enableAutopilot` is immutable in
Config Connector, which refuses the change rather than recreating the
cluster. (Terraform would destroy and recreate it, with everything running
on it.) So the chart makes the replacement explicit:

1. When the render can see the cluster (`helm install` or `upgrade`
   against it), a mode that differs from the live cluster's stops the
   render: "mode is autopilot but cluster `<name>` is standard: GKE cannot
   change a cluster's mode, so this would replace the cluster ...".
2. An offline render (Bundt's) cannot see it; Bundt's live check at plan
   time reports Config Connector's refusal of the immutable field, so the
   plan is blocked, not applied.
3. To change mode on purpose: delete the component (its cluster, node pools
   and service account go with it), then create it again with the new mode.
   Or create a second component beside it, move the workloads, and delete
   the first. The chart has no `allow_recreate` value, because Helm cannot
   see the previous mode in an offline render, and Config Connector cannot
   recreate the cluster in place even when told to.

Changing an input that renders an immutable `ContainerCluster` field is
refused the same way at plan time: `regional`, `region` and `zones[0]`
(`location`), `name` (`resourceID`), `description`, `ip_range_pods`,
`ip_range_services`, `stack_type`, `cluster_ipv4_cidr`,
`master_ipv4_cidr_block`, `private_endpoint_subnetwork`,
`datapath_provider`, `default_max_pods_per_node`, `enable_tpu`,
`enable_kubernetes_alpha`, `enable_multi_networking`,
`enable_confidential_nodes`, `issue_client_certificate`, the
`cluster_dns_*` inputs, and, while the default pool is kept, its node
configuration. The module's descriptions say "WARNING: changing this after
cluster creation is destructive!" for several of them; Terraform replaces
the cluster, Config Connector refuses.

## Example

The module README's first example, as values (`tests/basic.values.yaml`):

```yaml
project_id: my-project
name: gke-test-1
region: us-central1
zones: [us-central1-a, us-central1-b, us-central1-f]
network: vpc-01
subnetwork: us-central1-01
ip_range_pods: us-central1-01-gke-01-pods
ip_range_services: us-central1-01-gke-01-services
http_load_balancing: false
enable_private_endpoint: true
cloudrun: true
dns_cache: false
node_pools:
  - name: default-node-pool
    machine_type: e2-medium
    min_count: 1
    max_count: 100
    # ...
```

renders a `ContainerCluster` (private nodes and endpoint, the default pool
configured from the first node pool), a `ContainerNodePool`, an
`IAMServiceAccount` (`tf-gke-gke-test-1-f80a`) and its three project
grants (`tests/golden/basic.yaml`). The same with `mode: autopilot` and no
node pools is `tests/autopilot.values.yaml`.

## Values: module inputs to Config Connector

Every module input is a value of the same name (`values.yaml`,
`values.schema.json`). The table says what each renders; `ContainerCluster`
fields are under `spec`. "S" marks the inputs only Standard mode takes, "A"
the ones only Autopilot mode takes.

### Not module inputs

| Value | Renders |
| --- | --- |
| `mode` | `standard` or `autopilot` (above). The module you call picks it |
| `names.cluster`, `names.serviceAccount` | the cluster's and the node service account's cloud names in full, used as given (no `namePrefix`) and checked against GKE's limits (40 and 30 characters); a name not set derives from `name` (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of the derived cluster name and node service account ID, never a name set under `names`. Node pool names are scoped to their cluster and take none |
| `labels` | Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label |
| `tags` | cloud labels on every object |
| `deletion_policy` | `DELETE` (default) or `ABANDON`: every object keeps its cloud resource when the component is deleted. `PREVENT` is refused |

### Cluster

| Module input | Config Connector |
| --- | --- |
| `project_id` (required) | `cnrm.cloud.google.com/project-id` on every object; the workload pool `<project_id>.svc.id.goog`; the grants' project |
| `name` (required) | `resourceID` (or `names.cluster`) |
| `description` | `description` |
| `regional`, `region`, `zones` | `location` (the region, or the first zone) and `nodeLocations` (`zones` for a regional cluster, the other zones for a zonal one) |
| `network`, `subnetwork`, `network_project_id` | `networkRef` and `subnetworkRef`, external, in the Shared VPC host project when `network_project_id` is set |
| `ip_range_pods` (required), `ip_range_services`, `additional_ip_range_pods`, `additional_ip_ranges_config`, `stack_type` | `ipAllocationPolicy` (`clusterSecondaryRangeName`, `servicesSecondaryRangeName`, `additionalPodRangesConfig`, `additionalIpRangesConfigs`, `stackType`) |
| `cluster_ipv4_cidr` | `clusterIpv4Cidr` |
| `cluster_resource_labels` | the cluster object's labels, which Config Connector copies to the cluster's resource labels |
| `kubernetes_version` | `minMasterVersion`, unless `latest` |
| `release_channel` | `releaseChannel.channel` |
| `gateway_api_channel` | `gatewayApiConfig.channel` |
| `enable_k8s_beta_apis` | `enableK8sBetaApis.enabledApis` |
| `enable_private_nodes`, `enable_private_endpoint`, `master_ipv4_cidr_block`, `private_endpoint_subnetwork`, `master_global_access_enabled` | `privateClusterConfig` (`enablePrivateNodes`, `enablePrivateEndpoint`, `masterIpv4CidrBlock` or `privateEndpointSubnetworkRef`, `masterGlobalAccessConfig`), only when `enable_private_nodes` |
| `deploy_using_private_endpoint` | the `endpoint` output (the private endpoint) |
| `master_authorized_networks`, `gcp_public_cidrs_access_enabled` | `masterAuthorizedNetworksConfig` (present with no networks when `enable_private_endpoint`) |
| `dns_allow_external_traffic`, `dns_enable_k8s_tokens_via_dns`, `ip_endpoints_enabled` | `controlPlaneEndpointsConfig` |
| `issue_client_certificate` | `masterAuth.clientCertificateConfig.issueClientCertificate` |
| `authenticator_security_group` | `authenticatorGroupsConfig.securityGroup` |
| `identity_namespace` | `workloadIdentityConfig.workloadPool` (`enabled` is `<project_id>.svc.id.goog`; `null` or `"null"` leaves Workload Identity off) |
| `enable_mesh_certificates` (S) | `meshCertificates.enableCertificates`, with Workload Identity |
| `database_encryption` | `databaseEncryption` (one entry) |
| `enable_binary_authorization` | `binaryAuthorization.evaluationMode: PROJECT_SINGLETON_POLICY_ENFORCE` |
| `enable_shielded_nodes` (S), `enable_confidential_nodes` | `enableShieldedNodes`, `confidentialNodes.enabled` |
| `security_posture_mode`, `security_posture_vulnerability_mode` | `securityPostureConfig` |
| `workload_config_audit_mode`, `workload_vulnerability_mode` | `protectConfig` |
| `enable_cost_allocation` | `costManagementConfig.enabled` |
| `disable_default_snat` | `defaultSnatStatus.disabled` |
| `default_max_pods_per_node` (S) | `defaultMaxPodsPerNode` |
| `datapath_provider` (S) | `datapathProvider` |
| `network_policy`, `network_policy_provider` (S) | `networkPolicy` and `addonsConfig.networkPolicyConfig` |
| `enable_cilium_clusterwide_network_policy`, `enable_fqdn_network_policy`, `enable_multi_networking`, `enable_l4_ilb_subsetting`, `disable_l4_lb_firewall_reconciliation`, `in_transit_encryption_config`, `service_external_ips` | the fields of the same names |
| `enable_intranode_visibility`, `enable_kubernetes_alpha`, `enable_tpu`, `enable_identity_service`, `enable_pod_security_policy` (S) | `enableIntranodeVisibility`, `enableKubernetesAlpha`, `enableTpu`, `identityServiceConfig`, `podSecurityPolicyConfig` |
| `allow_net_admin` (A) | `allowNetAdmin` |
| `enable_vertical_pod_autoscaling` | `verticalPodAutoscaling.enabled` (`null`: the mode's default) |
| `http_load_balancing`, `horizontal_pod_autoscaling`, `filestore_csi_driver`, `gke_backup_agent_config` | `addonsConfig` (`httpLoadBalancing`, `horizontalPodAutoscaling`, `gcpFilestoreCsiDriverConfig`, `gkeBackupAgentConfig`) |
| `dns_cache`, `gce_pd_csi_driver`, `config_connector`, `gcs_fuse_csi_driver`, `parallelstore_csi_driver`, `cloudrun`, `cloudrun_load_balancer_type` (S) | `addonsConfig` (`dnsCacheConfig`, `gcePersistentDiskCsiDriverConfig`, `configConnectorConfig`, `gcsFuseCsiDriverConfig`, `parallelstoreCsiDriverConfig`, `cloudrunConfig`) |
| `cluster_dns_provider`, `cluster_dns_scope`, `cluster_dns_domain` (S) | `dnsConfig` |
| `logging_service`, `monitoring_service` (S) | `loggingService`, `monitoringService`, unless a logging or monitoring config is set, as the module does |
| `logging_enabled_components`, `monitoring_enabled_components` | `loggingConfig`, `monitoringConfig.enableComponents` |
| `cluster_telemetry_type`, `monitoring_enable_managed_prometheus`, `monitoring_enable_observability_metrics` (S) | `clusterTelemetry`, `monitoringConfig.managedPrometheus`, `monitoringConfig.advancedDatapathObservabilityConfig` |
| `maintenance_start_time`, `maintenance_end_time`, `maintenance_recurrence`, `maintenance_exclusions` | `maintenancePolicy` (a recurring window when both `maintenance_recurrence` and `maintenance_end_time` are set, else a daily one) |
| `notification_config_topic`, `notification_filter_event_type` | `notificationConfig.pubsub` (`topicRef` external) |
| `resource_usage_export_dataset_id`, `enable_network_egress_export`, `enable_resource_consumption_export` | `resourceUsageExportConfig` |
| `cluster_autoscaling` (S) | `clusterAutoscaling`: `enabled`, `autoscalingProfile`, `resourceLimits` (cpu, memory, `gpu_resources`), `defaultComputeClassConfig` (`enable_default_compute_class`), and `autoProvisioningDefaults` (service account, `node_pools_oauth_scopes.all`, `boot_disk_kms_key`, management, `disk_size`, upgrade settings, shielded instance, `image_type`) |
| `default_compute_class_enabled` (A) | `clusterAutoscaling.defaultComputeClassConfig.enabled` |
| `network_tags`, `resource_manager_tags` | `nodePoolAutoConfig` (Autopilot, or Standard with node auto-provisioning) |
| `logging_variant`, `enable_gcfs` (S) | `nodePoolDefaults.nodeConfigDefaults` |
| `initial_node_count`, `remove_default_node_pool` (S) | `initialNodeCount` (at least 1 when the default pool is removed) and the annotation `cnrm.cloud.google.com/remove-default-node-pool`; while the default pool stays, `nodeConfig` configures it from the first node pool, as the module's `node_pool` block does |
| `deletion_protection` | nothing (see "Differences") |

### Node service account

| Module input | Config Connector |
| --- | --- |
| `create_service_account` | an `IAMServiceAccount` |
| `service_account_name` | its ID; empty: `tf-gke-<name, 15 characters>-<4 characters>` (see "Differences") |
| `service_account` | the account nodes run as (`serviceAccountRef` external) instead of the created one; `""` or `create` uses the created one, as the module does |
| `monitoring_metric_writer_role` | with `roles/container.defaultNodeServiceAccount` and `roles/stackdriver.resourceMetadata.writer`, an `IAMPolicyMember` on the project for the created account |
| `grant_registry_access`, `registry_project_ids` | `roles/storage.objectViewer` and `roles/artifactregistry.reader` (and `roles/serviceusage.serviceUsageConsumer` with `enable_gcfs`) on each registry project, else the cluster's |
| `boot_disk_kms_key` | `bootDiskKMSCryptoKeyRef` on nodes (and `bootDiskKMSKeyRef` for auto-provisioned nodes), unless a pool sets its own |

### Node pools (Standard)

| Module input | Config Connector |
| --- | --- |
| `node_pools`, `windows_node_pools` | one `ContainerNodePool` per entry, named by its `name` (the cloud name; unique within the cluster) |
| a pool's `node_locations`, `version`, `auto_upgrade`, `auto_repair` | `nodeLocations`, `version` (only without auto-upgrade, defaulting to `kubernetes_version`), `management` (auto-upgrade defaults to on for a regional cluster or any release channel) |
| `autoscaling`, `min_count`, `max_count`, `total_min_count`, `total_max_count`, `location_policy`, `initial_node_count`, `node_count` | `autoscaling` and `initialNodeCount`, or `nodeCount` with `autoscaling: false` |
| `max_pods_per_node`, `pod_range`, `enable_private_nodes`, `pod_cidr_overprovision_disabled` | `maxPodsPerNode`, `networkConfig` |
| `strategy`, `max_surge`, `max_unavailable`, `node_pool_soak_duration`, `batch_soak_duration`, `batch_percentage`, `batch_node_count` | `upgradeSettings` |
| `placement_policy`, `policy_name`, `tpu_topology`, `queued_provisioning` | `placementPolicy`, `queuedProvisioning` |
| `machine_type`, `image_type`, `min_cpu_platform`, `disk_size_gb`, `disk_type`, `local_ssd_count`, `spot`, `preemptible`, `logging_variant` | `nodeConfig` fields of those names |
| `enable_gcfs`, `enable_gvnic`, `enable_fast_socket`, `enable_secure_boot`, `enable_integrity_monitoring`, `enable_confidential_nodes`, `sandbox_enabled` | `gcfsConfig`, `gvnic`, `fastSocket`, `shieldedInstanceConfig`, `confidentialNodes`, `sandboxConfig` (gVisor) |
| `accelerator_count`, `accelerator_type`, `gpu_partition_size`, `gpu_driver_version`, `gpu_sharing_strategy`, `max_shared_clients_per_gpu` | `guestAccelerator` |
| `consume_reservation_type`, `reservation_affinity_key`, `reservation_affinity_values` | `reservationAffinity` |
| `local_ssd_ephemeral_storage_count`, `ephemeral_storage_local_ssd_data_cache_count`, `local_ssd_ephemeral_count`, `local_nvme_ssd_count` | `ephemeralStorageLocalSsdConfig`, `ephemeralStorageConfig`, `localNvmeSsdBlockConfig` |
| `threads_per_core`, `enable_nested_virtualization` | `advancedMachineFeatures` |
| `cpu_manager_policy`, `cpu_cfs_quota`, `cpu_cfs_quota_period`, `pod_pids_limit`, `image_gc_low_threshold_percent`, `image_gc_high_threshold_percent`, `image_minimum_gc_age`, `image_maximum_gc_age` | `kubeletConfig` |
| `node_affinity` (JSON), `windows_node_config_os_version`, `boot_disk_kms_key`, `service_account`, `node_metadata` | `soleTenantConfig`, `windowsNodeConfig`, `bootDiskKMSCryptoKeyRef`, `serviceAccountRef`, `workloadMetadataConfig` |
| `node_pools_labels`, `node_pools_metadata`, `node_pools_tags`, `node_pools_taints`, `node_pools_oauth_scopes`, `node_pools_resource_labels`, `node_pools_resource_manager_tags` | `labels` (with `cluster_name` and `node_pool`), `metadata` (with `cluster_name`, `node_pool` and `disable-legacy-endpoints`), `tags` (with `gke-<cluster>` and `gke-<cluster>-<pool>`), `taint`, `oauthScopes`, `resourceLabels`, `resourceManagerTags`: each the `all` entry merged with the pool's, and `default_values` as the module reads it |
| `node_pools_linux_node_configs_sysctls`, `node_pools_cgroup_mode` | `linuxNodeConfig` (`sysctls`, `cgroupMode`) |
| `node_metadata`, `disable_legacy_metadata_endpoints`, `enable_default_node_pools_metadata`, `sandbox_enabled` | every pool's defaults, as in the module |

A pool's keys are those the module reads, listed in `values.schema.json`; a
misspelt key is refused. As in Terraform's `map(any)`, a boolean or a number
may be written as a string (`"false"`, `"3"`).

### Refused when set

The chart keeps these in its values, so a module block still converts one
to one, and stops the render naming the input and why
(`upstream.yaml`, `refused`).

| Input | Kind | Why |
| --- | --- | --- |
| `gke_auto_upgrade_config_patch_mode` | gap | `ContainerCluster` has no `gkeAutoUpgradeConfig` |
| `anonymous_authentication_config_mode` | gap | no `anonymousAuthenticationConfig` |
| `total_egress_bandwidth_tier` (cluster and pool) | gap | no `networkPerformanceConfig` |
| `rbac_binding_config` | gap | no `rbacBindingConfig` |
| `enable_secret_manager_addon`, `enable_secret_sync` | gap | no `secretManagerConfig` or `secretSyncConfig` |
| `enable_managed_machine_learning_diagnostics` | gap | no `managedMachineLearningDiagnosticsConfig` |
| `hpa_profile` | gap | no `podAutoscaling` |
| `enterprise_config` | gap | no `enterpriseConfig` |
| `lustre_csi_driver`, `enable_legacy_lustre_port`, `agent_sandbox_enabled`, `stateful_ha`, `ray_operator_config` | gap | `addonsConfig` has no Lustre, agent sandbox, Stateful HA or Ray operator config |
| `user_managed_keys_config` | gap | no `userManagedKeysConfig` |
| `fleet_project` | gap | no `fleet`; a `GKEHubMembership` registers a cluster in Config Connector, not ported |
| `network_tier_config` | gap | `ipAllocationPolicy` has no `networkTierConfig` |
| `insecure_kubelet_readonly_port_enabled` (cluster and pool) | gap | no field in `nodePoolDefaults`, `nodePoolAutoConfig` or `kubeletConfig` |
| `additive_vpc_scope_dns_domain` | gap | `dnsConfig` has no `additiveVpcScopeDnsDomain` |
| `monitoring_enable_observability_relay` | gap | only the deprecated `relayMode` |
| `monitoring_auto_monitoring_config_scope: ALL` | gap | `managedPrometheus` has no `autoMonitoringConfig` (`NONE`, the default, carries over) |
| `cluster_autoscaling.disk_type` other than `pd-standard` | gap | `autoProvisioningDefaults` has no `diskType` |
| `node_pools_cgroup_mode` for Autopilot or auto-provisioned nodes | gap | `nodePoolAutoConfig` has no `linuxNodeConfig` |
| `node_pools_transparent_hugepage_enabled`, `_defrag`, `node_pools_hugepage_size_2m`, `_1g` | gap | `linuxNodeConfig` has no hugepage fields |
| pool keys `respect_pdb_during_node_pool_deletion`, `enable_confidential_storage`, `provisioned_iops`, `provisioned_throughput`, `secondary_boot_disk`, `secondary_boot_disk_mode`, `performance_monitoring_unit`, `container_log_max_size`, `container_log_max_files`, `allowed_unsafe_sysctls`, `shutdown_grace_period_seconds`, `shutdown_grace_period_critical_pods_seconds`, `single_process_oom_kill`, `storage_pools`, `local_ssd_encryption_mode`, `max_run_duration`, `flex_start` | gap | no `ContainerNodePool` field |
| `add_cluster_firewall_rules`, `add_master_webhook_firewall_rules`, `add_shadow_firewall_rules` (and `firewall_priority`, `firewall_inbound_ports`, `shadow_firewall_rules_priority`, `shadow_firewall_rules_log_config`, used only by them) | not ported | the rules need the subnetwork's and pod ranges' CIDRs, which the module reads with data sources and a chart cannot; add `ComputeFirewall` rules beside the cluster |
| `fleet_project_grant_service_agent` | not ported | grants for `fleet_project`, a gap |
| `stub_domains`, `upstream_nameservers`, `configure_ip_masq`, `ip_masq_link_local` (and `ip_masq_resync_interval`, `non_masquerade_cidrs`) | by design | the module writes kube-dns and ip-masq-agent ConfigMaps into the cluster through the kubernetes provider; with Bundt that is a component delivered to the cluster as a Target |
| `timeouts` | by design | Config Connector has no per-resource timeouts |

## Outputs

| Output | From |
| --- | --- |
| `name`, `location`, `cluster_id` | the cluster's `resourceID` and `location` (`projects/<p>/locations/<l>/clusters/<n>`) |
| `region`, `type` | inputs, as the module computes them |
| `endpoint` | `status.endpoint`, or the private or public endpoint of `status.observedState.privateClusterConfig`, as the module chooses |
| `endpoint_dns`, `ca_certificate` | `status.observedState` |
| `master_version`, `tpu_ipv4_cidr_block` | `status` |
| `min_master_version`, `logging_service`, `monitoring_service`, `vertical_pod_autoscaling_enabled` | the cluster's spec |
| `service_account` | the created account's email, or `service_account` |
| `node_pools_names`, `node_pools_versions`, `instance_group_urls` | the node pools (names from inputs; versions and instance groups from their status) |
| `release_channel`, `gateway_api_channel`, `identity_namespace`, `master_ipv4_cidr_block`, and the add-on flags (`http_load_balancing_enabled`, `horizontal_pod_autoscaling_enabled`, `network_policy_enabled`, `dns_cache_enabled`, `intranode_visibility_enabled`, `identity_service_enabled`, `pod_security_policy_enabled`, `cloudrun_enabled`) | inputs |

Not outputs: `zones` and `peering_name` (Config Connector reports neither in
status), `master_authorized_networks_config` and `mesh_certificates_config`
(whole Terraform objects; `docs/design.md`, "Outputs"), `fleet_membership`
and `secret_manager_addon_enabled` (their inputs are gaps).

## Differences from the module

- **`deletion_protection`** (default `true`) is accepted and does nothing.
  It is Terraform's guard against `terraform destroy`; Config Connector has
  no equivalent. Deleting the component deletes the cluster, as Bundt
  decided (`docs/design.md`, "Deletion"); `deletion_policy: ABANDON` keeps
  it, and a Bundt policy can block a plan that deletes it.
- **The node service account's suffix.** The module names a created
  account `tf-gke-<name>-<random 4 characters>`. A render must not change,
  so the chart's 4 characters are the first 4 hex characters of the sha256
  of `<project_id>/<name>`. To adopt an account Terraform made, set
  `service_account_name` (or `names.serviceAccount`) to its ID.
- **Regional clusters without `zones`.** The module picks three random
  zones of the region (`random_shuffle`); the chart sets no
  `nodeLocations`, and GKE uses its default zones for the region.
- **`kubernetes_version: latest` without a release channel.** The module
  looks up the latest master version (a data source) and pins it; the chart
  sets no `minMasterVersion`, so GKE's default version applies.
- **The default node pool** while it is kept (`remove_default_node_pool:
  false`) is configured by `nodeConfig` from the first node pool. When it is
  removed the chart sends no `nodeConfig`, and creates the pool with at least
  one node, which Config Connector deletes once the cluster is ready.
- **`cluster_autoscaling.disk_type`** is not sent (no field), so
  auto-provisioned nodes take GKE's default disk type rather than
  `pd-standard`.
- **IAM grants** are additive `IAMPolicyMember`s, as the module's
  `google_project_iam_member`s are.
- **Outputs** come from the live objects where the module reads them from
  the cluster, so a dependent waits until the cluster is ready.

## Not ported

- The firewall rules (`firewall.tf`): see "Refused when set".
- The in-cluster ConfigMaps (`dns.tf`, `masq.tf`): see "Refused when set".
- `safer-cluster` and `safer-cluster-update-variant`: opinionated wrappers
  of `beta-private-cluster` with fixed values; the same values here give the
  same cluster.
- `gke-standard-cluster`, `gke-autopilot-cluster` and `gke-node-pool`: the
  newer modules, which mirror the provider's resource schema field for
  field rather than these modules' inputs. A separate chart if wanted.
- `auth`, `workload-identity`, `fleet-membership`, `hub-legacy`,
  `binary-authorization` and the other helper modules: separate resources,
  not the cluster.

## Since 5.0.0

The builder's link names v5.0.0 (2019). Between v5.0.0 and v47.0.0 the
`beta-private-cluster` inputs grew from 62 to 162. Seven of v5.0.0's inputs
are gone: `basic_auth_username` and `basic_auth_password` (GKE removed basic
authentication), `istio` (the Istio add-on, removed from GKE),
`kubernetes_dashboard` (removed from GKE), `pod_security_policy_config` (now
`enable_pod_security_policy`; PodSecurityPolicy itself left GKE in 1.25),
`master_authorized_networks_config` (now `master_authorized_networks`, a flat
list), and `node_version` (now per pool, `version`). The Autopilot modules,
`*-update-variant` and the private and public splits of the beta modules
arrived later. A v5.0.0 module block needs those seven renamed or dropped
before it converts.

## Upstream

Ported from
[`modules/beta-private-cluster`](https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/tree/v47.0.0/modules/beta-private-cluster)
and
[`modules/beta-autopilot-private-cluster`](https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/tree/v47.0.0/modules/beta-autopilot-private-cluster)
at v47.0.0 (`a19597ac`, Apache-2.0). [`upstream.yaml`](upstream.yaml)
records the repository, path, release, commit, licence and the date last
synced, and the module is listed in
[`upstream/modules.yaml`](../../../upstream/modules.yaml) as
`gcp/kubernetes-engine-beta-private-cluster`. Both modules are generated
from one template (`autogen/main`) and release together, so one pin covers
both. To take a newer release, see [`UPSTREAM.md`](../../../UPSTREAM.md),
"Moving the pins".

## Tests

`task test CHART=gke-cluster`: seven render cases (`basic`, `public`,
`full`, `names`, `autopilot`, `autopilot-full`, `mock`), each validated
against Config Connector v1.160.0's CRD schemas, and the refusals in
`tests/*.fail.yaml`. `tests/mock.values.yaml` is applied to the fake cloud by
`hack/mock-apply.sh`. A live run of each mode is described in `docs/design.md`,
"Pilot results".

## Changes

- **0.1.0** (2026-11-10): the port.
