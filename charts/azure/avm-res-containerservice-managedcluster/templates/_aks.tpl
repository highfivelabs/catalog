{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

This chart's own helpers. The module converts its snake_case inputs to the
ARM body's camelCase field by field (locals.resource_body.tf,
locals.network_profile.tf, modules/agentpool/locals.tf,
modules/maintenanceconfiguration/locals.tf, modules/namespace); aks.conv
does the same conversion once, with the module's exceptions, and turns the
fields that are ARM IDs into ASO's references ({armId: ...}).
*/ -}}

{{- /*
aks.key: the camelCase name of a snake_case key, as the module writes it:
words joined with their first letter upper-cased, a few written in capitals
(FIPS, IP, SSD, GB, MB, DNS, RBAC, FQDN, API, CSI, VTPM, OS, CA) unless
first, and the module's irregular names.
*/ -}}
{{- define "aks.key" -}}
{{- $irregular := dict "os_sku" "osSKU" "trusted_ca" "trustedCa" "count_i_pv6" "countIPv6" "admin_group_object_ids" "adminGroupObjectIDs" "client_app_id" "clientAppID" "server_app_id" "serverAppID" "tenant_id" "tenantID" "count_of" "count" -}}
{{- if hasKey $irregular . -}}
{{- index $irregular . -}}
{{- else -}}
{{- $caps := dict "fips" "FIPS" "ip" "IP" "ips" "IPs" "ssd" "SSD" "gb" "GB" "mb" "MB" "dns" "DNS" "rbac" "RBAC" "fqdn" "FQDN" "api" "API" "csi" "CSI" "vtpm" "VTPM" "os" "OS" "ca" "CA" -}}
{{- $out := "" -}}
{{- range $i, $w := splitList "_" . -}}
{{- if eq $i 0 -}}{{- $out = $w -}}
{{- else if hasKey $caps $w -}}{{- $out = print $out (index $caps $w) -}}
{{- else -}}{{- $out = print $out (title $w) -}}
{{- end -}}
{{- end -}}
{{- $out -}}
{{- end -}}
{{- end -}}

{{- /*
aks.conv: a module input converted to its ARM body, as JSON {"v": ...}.
  {{ index (include "aks.conv" (dict "k" "network_profile" "v" $v.network_profile) | fromJson) "v" }}
Nulls are dropped. The keys of node_labels, tags, annotations, labels,
pod_labels and an add-on's config are kept as given; so are those of
kube_dns_overrides and vnet_dns_overrides, whose values are converted.
An ARM ID field becomes ASO's reference: an object's "id" is
reference.armId, the fields below their <name>Reference.armId, and the
lists below a list of {armId}.
*/ -}}
{{- define "aks.conv" -}}
{{- $k := .k -}}{{- $v := .v -}}
{{- $refs := dict "capacity_reservation_group_id" "capacityReservationGroupReference" "host_group_id" "hostGroupReference" "node_public_ip_prefix_id" "nodePublicIPPrefixReference" "pod_subnet_id" "podSubnetReference" "proximity_placement_group_id" "proximityPlacementGroupReference" "vnet_subnet_id" "vnetSubnetReference" "source_resource_id" "sourceResourceReference" "subnet_id" "subnetReference" "container_registry_id" "containerRegistryReference" "node_subnet_id" "nodeSubnetReference" "system_node_subnet_id" "systemNodeSubnetReference" "log_analytics_workspace_resource_id" "logAnalyticsWorkspaceResourceReference" "key_vault_resource_id" "keyVaultResourceReference" "key_vault_id" "keyVaultReference" "resource_id" "resourceReference" "disk_encryption_set_id" "diskEncryptionSetReference" -}}
{{- $refLists := dict "application_security_groups" "applicationSecurityGroupsReferences" "dns_zone_resource_ids" "dnsZoneResourceReferences" -}}
{{- $out := $v -}}
{{- if kindIs "map" $v -}}
{{- $out = dict -}}
{{- if has $k (list "node_labels" "tags" "annotations" "labels" "pod_labels" "config") -}}
{{- range $kk, $vv := $v }}{{ if not (kindIs "invalid" $vv) }}{{ $_ := set $out $kk $vv }}{{ end }}{{ end -}}
{{- else if has $k (list "kube_dns_overrides" "vnet_dns_overrides") -}}
{{- range $kk, $vv := $v }}{{ if not (kindIs "invalid" $vv) }}{{ $_ := set $out $kk (index (include "aks.conv" (dict "k" "" "v" $vv) | fromJson) "v") }}{{ end }}{{ end -}}
{{- else -}}
{{- range $kk, $vv := $v -}}
{{- if not (kindIs "invalid" $vv) -}}
{{- if eq $kk "id" -}}
{{- $_ := set $out "reference" (dict "armId" $vv) -}}
{{- else if hasKey $refs $kk -}}
{{- $_ := set $out (index $refs $kk) (dict "armId" $vv) -}}
{{- else if hasKey $refLists $kk -}}
{{- $l := list -}}{{- range $vv }}{{ $l = append $l (dict "armId" .) }}{{ end -}}
{{- $_ := set $out (index $refLists $kk) $l -}}
{{- else -}}
{{- $_ := set $out (include "aks.key" $kk) (index (include "aks.conv" (dict "k" $kk "v" $vv) | fromJson) "v") -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- else if kindIs "slice" $v -}}
{{- $out = list -}}
{{- range $v }}{{ $out = append $out (index (include "aks.conv" (dict "k" "" "v" .) | fromJson) "v") }}{{ end -}}
{{- end -}}
{{- toJson (dict "v" $out) -}}
{{- end -}}

{{- /*
aks.pool: an agent pool's ARM properties (modules/agentpool/locals.tf),
as JSON, from a default_agent_pool or agent_pools entry, for ASO's agent
pool at 2025-10-02-preview (the module's agent pools take
2026-01-02-preview). Its count is dropped when both min_count and
max_count are set, as the module does. With stable, for the cluster's
agentPoolProfiles at 2026-05-01: the properties only the preview has are
dropped too. Arguments (a dict): root, p (the entry), where (for
messages), stable, drop (further keys not sent).
*/ -}}
{{- define "aks.pool" -}}
{{- $root := .root -}}{{- $p := deepCopy .p -}}
{{- include "aso.unsupported" (list $root (printf "%s.enable_os_disk_full_caching" .where) $p.enable_os_disk_full_caching "ASO's agent pool (up to API 2025-10-02-preview) has no enableOSDiskFullCaching") }}
{{- with $p.gpu_profile }}
{{- include "aso.unsupported" (list $root (printf "%s.gpu_profile.nvidia" $.where) .nvidia "ASO's agent pool (up to API 2025-10-02-preview) has no gpuProfile.nvidia") }}
{{- end }}
{{- with $p.local_dns_profile }}{{ $_ := unset . "state" }}{{ end }}
{{- if and (not (kindIs "invalid" $p.min_count)) (not (kindIs "invalid" $p.max_count)) }}{{ $_ := unset $p "count_of" }}{{ end }}
{{- range concat (list "name" "delete_options" "output_data_only" "power_state" "status") (.drop | default list) }}{{ $_ := unset $p . }}{{ end }}
{{- if .stable }}
{{- range list "node_customization_profile" "node_initialization_taints" "upgrade_settings_blue_green" "upgrade_strategy" }}{{ $_ := unset $p . }}{{ end }}
{{- with $p.upgrade_settings }}{{ $_ := unset . "max_blocked_nodes" }}{{ end }}
{{- with $p.kubelet_config }}{{ $_ := unset . "seccomp_default" }}{{ end }}
{{- with $p.gpu_profile }}{{ $_ := unset . "driver_type" }}{{ end }}
{{- end }}
{{- $out := index (include "aks.conv" (dict "k" "" "v" $p) | fromJson) "v" -}}
{{- with $out.nodeCustomizationProfile }}{{ with .nodeCustomizationId }}{{ $_ := set $out "nodeCustomizationProfile" (dict "nodeCustomizationReference" (dict "armId" .)) }}{{ end }}{{ end -}}
{{- toJson $out -}}
{{- end -}}
