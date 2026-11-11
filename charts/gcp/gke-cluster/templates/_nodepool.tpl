{{/*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Ported from terraform-google-kubernetes-engine
modules/beta-private-cluster/cluster.tf (the node_config of
google_container_cluster.primary's default pool and of
google_container_node_pool.pools and .windows_pools) and
variables_defaults.tf (v47.0.0), Copyright 2022 Google LLC, Apache-2.0.

A node pool entry is the module's map(any): its keys are listed in
values.schema.json; a value may be a string, as Terraform's map(any)
makes it ("true", "3"), and gke.bool and int read both.
*/}}

{{/*
gke.poolGaps: stop the render when a node pool sets a key Config
Connector v1.160.0 cannot carry.
  {{ include "gke.poolGaps" (dict "root" $ "pool" $pool "list" "node_pools") }}
*/}}
{{- define "gke.poolGaps" -}}
{{- $p := .pool -}}
{{- $gaps := dict
  "total_egress_bandwidth_tier" "ContainerNodePool's networkConfig has no networkPerformanceConfig"
  "respect_pdb_during_node_pool_deletion" "ContainerNodePool has no nodeDrainConfig"
  "enable_confidential_storage" "nodeConfig has no enableConfidentialStorage"
  "provisioned_iops" "nodeConfig has no bootDisk"
  "provisioned_throughput" "nodeConfig has no bootDisk"
  "secondary_boot_disk" "nodeConfig has no secondaryBootDisks"
  "secondary_boot_disk_mode" "nodeConfig has no secondaryBootDisks"
  "performance_monitoring_unit" "nodeConfig's advancedMachineFeatures has no performanceMonitoringUnit"
  "insecure_kubelet_readonly_port_enabled" "nodeConfig's kubeletConfig has no insecureKubeletReadonlyPortEnabled"
  "container_log_max_size" "nodeConfig's kubeletConfig has no containerLogMaxSize"
  "container_log_max_files" "nodeConfig's kubeletConfig has no containerLogMaxFiles"
  "allowed_unsafe_sysctls" "nodeConfig's kubeletConfig has no allowedUnsafeSysctls"
  "shutdown_grace_period_seconds" "nodeConfig's kubeletConfig has no shutdownGracePeriodSeconds"
  "shutdown_grace_period_critical_pods_seconds" "nodeConfig's kubeletConfig has no shutdownGracePeriodCriticalPodsSeconds"
  "single_process_oom_kill" "nodeConfig's kubeletConfig has no singleProcessOomKill"
  "storage_pools" "nodeConfig has no storagePools"
  "local_ssd_encryption_mode" "nodeConfig has no localSsdEncryptionMode"
  "max_run_duration" "nodeConfig has no maxRunDuration"
  "flex_start" "nodeConfig has no flexStart" -}}
{{- range $k := keys $gaps | sortAlpha -}}
{{- if and (hasKey $p $k) (not (kindIs "invalid" (index $p $k))) (ne (toString (index $p $k)) "false") -}}
{{- include "kcc.unsupported" (list $.root (printf "%s[%s].%s" $.list $p.name $k) (index $p $k) (get $gaps $k)) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
gke.nodeConfig: a nodeConfig, for a node pool (pool, windows) or for the
cluster's default pool (defaultPool: true, pool = the first node pool, as
the module's node_pool block takes it).
*/}}
{{- define "gke.nodeConfig" -}}
{{- $root := .root -}}{{- $v := $root.Values -}}{{- $p := .pool -}}
{{- $name := toString ($p.name | default "") -}}
{{- $own := ternary "default-pool" $name (eq (toString .defaultPool) "true") -}}
{{- $isDefault := eq (toString .defaultPool) "true" -}}
{{- $tag := include "gke.networkTag" $root -}}
imageType: {{ $p.image_type | default "COS_CONTAINERD" | quote }}
machineType: {{ $p.machine_type | default "e2-medium" | quote }}
{{- with $p.min_cpu_platform }}
minCpuPlatform: {{ . | quote }}
{{- end }}
{{- if $isDefault }}
{{- with $p.disk_type }}
diskType: {{ . | quote }}
{{- end }}
{{- else }}
diskSizeGb: {{ include "gke.int" (list $p.disk_size_gb 100) }}
diskType: {{ $p.disk_type | default "pd-standard" | quote }}
localSsdCount: {{ include "gke.int" (list $p.local_ssd_count 0) }}
{{- end }}
{{- if hasKey $p "enable_gcfs" }}
gcfsConfig:
  enabled: {{ include "gke.bool" (list $p.enable_gcfs false) }}
{{- end }}
{{- if eq (include "gke.bool" (list $p.enable_gvnic false)) "true" }}
gvnic:
  enabled: true
{{- end }}
{{- if hasKey $p "enable_fast_socket" }}
fastSocket:
  enabled: {{ include "gke.bool" (list $p.enable_fast_socket false) }}
{{- end }}
{{- $kubelet := list "cpu_manager_policy" "cpu_cfs_quota" "cpu_cfs_quota_period" "pod_pids_limit" "image_gc_low_threshold_percent" "image_gc_high_threshold_percent" "image_minimum_gc_age" "image_maximum_gc_age" -}}
{{- $hasKubelet := false -}}
{{- range $k := $kubelet }}{{ if hasKey $p $k }}{{ $hasKubelet = true }}{{ end }}{{ end -}}
{{- if $hasKubelet }}
kubeletConfig:
  cpuManagerPolicy: {{ $p.cpu_manager_policy | default "static" | quote }}
  {{- if hasKey $p "cpu_cfs_quota" }}
  cpuCfsQuota: {{ include "gke.bool" (list $p.cpu_cfs_quota true) }}
  {{- end }}
  {{- with $p.cpu_cfs_quota_period }}
  cpuCfsQuotaPeriod: {{ . | quote }}
  {{- end }}
  {{- with $p.pod_pids_limit }}
  podPidsLimit: {{ . | int }}
  {{- end }}
  {{- with $p.image_gc_low_threshold_percent }}
  imageGcLowThresholdPercent: {{ . | int }}
  {{- end }}
  {{- with $p.image_gc_high_threshold_percent }}
  imageGcHighThresholdPercent: {{ . | int }}
  {{- end }}
  {{- with $p.image_minimum_gc_age }}
  imageMinimumGcAge: {{ . | quote }}
  {{- end }}
  {{- with $p.image_maximum_gc_age }}
  imageMaximumGcAge: {{ . | quote }}
  {{- end }}
{{- end }}
{{- with $p.node_affinity }}
{{- $a := . | fromJson }}
soleTenantConfig:
  nodeAffinity:
    - key: {{ $a.key | quote }}
      operator: {{ $a.operator | quote }}
      values: {{ $a.values | default list | toJson }}
{{- end }}
{{- with (include "gke.saRef" (list $root (toString ($p.service_account | default ""))) | fromJson) }}
serviceAccountRef: {{ toJson . }}
{{- end }}
{{- /* node_pools_tags.default_values is [cluster tag?, pool tag?] */}}
{{- $dv := index ($v.node_pools_tags | default dict) "default_values" | default (list true true) -}}
{{- $tags := list -}}
{{- if eq (include "gke.bool" (list (index $dv 0) true)) "true" }}{{ $tags = append $tags $tag }}{{ end -}}
{{- if eq (include "gke.bool" (list (index $dv 1) true)) "true" }}{{ $tags = append $tags (printf "%s-%s" $tag $own) }}{{ end -}}
{{- $tags = concat $tags (include "gke.poolMap" (list $root "node_pools_tags" $name "list") | fromJsonArray) }}
tags: {{ toJson $tags }}
loggingVariant: {{ $p.logging_variant | default "DEFAULT" | quote }}
{{- $md := include "gke.nodeMetadata" (default $v.node_metadata $p.node_metadata) -}}
{{- if and $md (ne (toString $v.node_metadata) "UNSPECIFIED") }}
workloadMetadataConfig:
  mode: {{ $md | quote }}
{{- end }}
{{- if $isDefault }}
{{- with (index ($v.node_pools_metadata | default dict) "all") }}
metadata: {{ toJson . }}
{{- end }}
{{- else }}
{{- $mdv := index ($v.node_pools_metadata | default dict) "default_values" | default dict -}}
{{- $meta := dict -}}
{{- if eq (include "gke.bool" (list (index $mdv "cluster_name") $v.enable_default_node_pools_metadata)) "true" }}{{ $_ := set $meta "cluster_name" $v.name }}{{ end -}}
{{- if eq (include "gke.bool" (list (index $mdv "node_pool") $v.enable_default_node_pools_metadata)) "true" }}{{ $_ := set $meta "node_pool" $name }}{{ end -}}
{{- $meta = merge (include "gke.poolMap" (list $root "node_pools_metadata" $name "map") | fromJson) $meta -}}
{{- $_ := set $meta "disable-legacy-endpoints" (toString $v.disable_legacy_metadata_endpoints) }}
metadata: {{ toJson $meta }}
{{- $ldv := index ($v.node_pools_labels | default dict) "default_values" | default dict -}}
{{- $labels := dict -}}
{{- if eq (include "gke.bool" (list (index $ldv "cluster_name") true)) "true" }}{{ $_ := set $labels "cluster_name" $v.name }}{{ end -}}
{{- if eq (include "gke.bool" (list (index $ldv "node_pool") true)) "true" }}{{ $_ := set $labels "node_pool" $name }}{{ end -}}
{{- $labels = merge (include "gke.poolMap" (list $root "node_pools_labels" $name "map") | fromJson) $labels }}
labels: {{ toJson $labels }}
{{- with (include "gke.poolMap" (list $root "node_pools_resource_labels" $name "map") | fromJson) }}
resourceLabels: {{ toJson . }}
{{- end }}
{{- with (include "gke.poolMap" (list $root "node_pools_resource_manager_tags" $name "map") | fromJson) }}
resourceManagerTags: {{ toJson . }}
{{- end }}
{{- with (include "gke.poolMap" (list $root "node_pools_taints" $name "list") | fromJsonArray) }}
taint:
  {{- range . }}
  - key: {{ .key | quote }}
    value: {{ .value | quote }}
    effect: {{ .effect | quote }}
  {{- end }}
{{- end }}
oauthScopes: {{ include "gke.poolMap" (list $root "node_pools_oauth_scopes" $name "list") }}
preemptible: {{ include "gke.bool" (list $p.preemptible false) }}
spot: {{ include "gke.bool" (list $p.spot false) }}
{{- if or (eq (include "gke.bool" (list $p.queued_provisioning false)) "true") $p.consume_reservation_type }}
reservationAffinity:
  consumeReservationType: {{ ternary "NO_RESERVATION" ($p.consume_reservation_type | default "") (eq (include "gke.bool" (list $p.queued_provisioning false)) "true") | quote }}
  {{- with $p.reservation_affinity_key }}
  key: {{ . | quote }}
  {{- end }}
  {{- with $p.reservation_affinity_values }}
  values: {{ splitList "," . | toJson | replace " " "" }}
  {{- end }}
{{- end }}
{{- if or (gt (int ($p.local_ssd_ephemeral_storage_count | default 0)) 0) (gt (int ($p.ephemeral_storage_local_ssd_data_cache_count | default 0)) 0) }}
ephemeralStorageLocalSsdConfig:
  localSsdCount: {{ $p.local_ssd_ephemeral_storage_count | default 0 | int }}
  dataCacheCount: {{ $p.ephemeral_storage_local_ssd_data_cache_count | default 0 | int }}
{{- end }}
{{- if gt (int ($p.local_ssd_ephemeral_count | default 0)) 0 }}
ephemeralStorageConfig:
  localSsdCount: {{ $p.local_ssd_ephemeral_count | int }}
{{- end }}
{{- if gt (int ($p.local_nvme_ssd_count | default 0)) 0 }}
localNvmeSsdBlockConfig:
  localSsdCount: {{ $p.local_nvme_ssd_count | int }}
{{- end }}
{{- if gt (int ($p.accelerator_count | default 0)) 0 }}
guestAccelerator:
  - type: {{ $p.accelerator_type | default "" | quote }}
    count: {{ $p.accelerator_count | int }}
    {{- with $p.gpu_partition_size }}
    gpuPartitionSize: {{ . | quote }}
    {{- end }}
    {{- with $p.gpu_driver_version }}
    gpuDriverInstallationConfig:
      gpuDriverVersion: {{ . | quote }}
    {{- end }}
    {{- with $p.gpu_sharing_strategy }}
    gpuSharingConfig:
      gpuSharingStrategy: {{ . | quote }}
      maxSharedClientsPerGpu: {{ include "gke.int" (list $p.max_shared_clients_per_gpu 2) }}
    {{- end }}
{{- end }}
{{- if or (gt (int ($p.threads_per_core | default 0)) 0) (eq (include "gke.bool" (list $p.enable_nested_virtualization false)) "true") }}
advancedMachineFeatures:
  threadsPerCore: {{ $p.threads_per_core | default 0 | int }}
  {{- if hasKey $p "enable_nested_virtualization" }}
  enableNestedVirtualization: {{ include "gke.bool" (list $p.enable_nested_virtualization false) }}
  {{- end }}
{{- end }}
{{- with $p.windows_node_config_os_version }}
windowsNodeConfig:
  osVersion: {{ . | quote }}
{{- end }}
{{- if not .windows }}
{{- $sysctls := include "gke.poolMap" (list $root "node_pools_linux_node_configs_sysctls" $name "map") | fromJson -}}
{{- $cgroup := "" -}}
{{- if kindIs "map" $v.node_pools_cgroup_mode }}{{ $cgroup = include "gke.poolMap" (list $root "node_pools_cgroup_mode" $name "string") }}{{ end -}}
{{- range $k := list "node_pools_transparent_hugepage_enabled" "node_pools_transparent_hugepage_defrag" "node_pools_hugepage_size_2m" "node_pools_hugepage_size_1g" -}}
{{- $set := include "gke.poolMap" (list $root $k $name "string") -}}
{{- include "kcc.unsupported" (list $root (printf "%s[%s]" $k $name) $set "nodeConfig's linuxNodeConfig has no transparent hugepage or hugepages fields") -}}
{{- end -}}
{{- if or $sysctls $cgroup }}
linuxNodeConfig:
  {{- with $sysctls }}
  sysctls: {{ toJson . }}
  {{- end }}
  {{- with $cgroup }}
  cgroupMode: {{ . | quote }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- $sandbox := include "gke.bool" (list $p.sandbox_enabled $v.sandbox_enabled) -}}
{{- if eq $sandbox "true" }}
sandboxConfig:
  sandboxType: gvisor
{{- end }}
{{- with (default $v.boot_disk_kms_key $p.boot_disk_kms_key) }}
bootDiskKMSCryptoKeyRef:
  external: {{ . | quote }}
{{- end }}
shieldedInstanceConfig:
  enableSecureBoot: {{ include "gke.bool" (list $p.enable_secure_boot false) }}
  enableIntegrityMonitoring: {{ include "gke.bool" (list $p.enable_integrity_monitoring true) }}
{{- if and (not $isDefault) (hasKey $p "enable_confidential_nodes") }}
confidentialNodes:
  enabled: {{ include "gke.bool" (list $p.enable_confidential_nodes false) }}
{{- end }}
{{- end -}}
