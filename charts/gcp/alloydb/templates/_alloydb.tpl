{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

Helpers of the alloydb chart.
*/ -}}

{{- /* alloydb.prefix: fabric's local.prefix, "<prefix>-" or "". */ -}}
{{- define "alloydb.prefix" -}}
{{- with .Values.prefix }}{{ printf "%s-" . }}{{ end -}}
{{- end -}}

{{- /* alloydb.clusterID: names.cluster in full when set; else
"<prefix>-<cluster_name>", as fabric names the primary cluster, with the
namePrefix in front (63 characters, starting with a letter). */ -}}
{{- define "alloydb.clusterID" -}}
{{- include "kcc.resourceName" (list . "cluster" "cluster" (printf "%s%s" (include "alloydb.prefix" .) .Values.cluster_name) 63 "letter") -}}
{{- end -}}

{{- /* alloydb.instanceID: names.instance, else "<prefix>-<instance_name>". */ -}}
{{- define "alloydb.instanceID" -}}
{{- include "kcc.resourceName" (list . "instance" "instance" (printf "%s%s" (include "alloydb.prefix" .) .Values.instance_name) 63 "letter") -}}
{{- end -}}

{{- /* alloydb.secondaryClusterID: names.secondaryCluster, else
cross_region_replication.secondary_cluster_name, else
"<cluster_name>-sec", as fabric names it (without fabric's prefix). */ -}}
{{- define "alloydb.secondaryClusterID" -}}
{{- $c := .Values.cross_region_replication | default dict -}}
{{- include "kcc.resourceName" (list . "secondaryCluster" "secondary cluster" ($c.secondary_cluster_name | default (printf "%s-sec" .Values.cluster_name)) 63 "letter") -}}
{{- end -}}

{{- /* alloydb.secondaryInstanceID: names.secondaryInstance, else
cross_region_replication.secondary_instance_name, else
"<instance_name>-sec". */ -}}
{{- define "alloydb.secondaryInstanceID" -}}
{{- $c := .Values.cross_region_replication | default dict -}}
{{- include "kcc.resourceName" (list . "secondaryInstance" "secondary instance" ($c.secondary_instance_name | default (printf "%s-sec" .Values.instance_name)) 63 "letter") -}}
{{- end -}}

{{- /* alloydb.readPoolID: a read pool's ID, "<prefix>-<key>", as fabric
names it, with the namePrefix in front. (list $ <key>) */ -}}
{{- define "alloydb.readPoolID" -}}
{{- $root := index . 0 -}}
{{- include "kcc.cloudName" (list $root "read pool" (printf "%s%s" (include "alloydb.prefix" $root) (index . 1)) 63 "letter") -}}
{{- end -}}

{{- /* alloydb.cloudLabels: the Google Cloud labels every resource gets
(the unprefixed keys of labels and tags), as JSON; fabric puts its labels
on the automated backups too. */ -}}
{{- define "alloydb.cloudLabels" -}}
{{- $out := dict -}}
{{- range $k, $v := (include "kcc.labels" (list . dict) | fromJson) -}}
{{- if not (contains "/" $k) }}{{ $_ := set $out $k $v }}{{ end -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{- /* alloydb.clusterSpec: the spec fields both clusters share: backups,
encryption, maintenance and network, as fabric writes them for the
primary or the secondary cluster. (list $ "primary"|"secondary") */ -}}
{{- define "alloydb.clusterSpec" -}}
{{- $root := index . 0 -}}{{- $v := $root.Values -}}
{{- $primary := eq (index . 1) "primary" -}}
{{- $enc := $v.encryption_config | default dict -}}
{{- $kms := ternary $enc.primary_kms_key_name $enc.secondary_kms_key_name $primary -}}
{{- with $v.network_config.psa_config }}
networkConfig:
  networkRef:
    external: {{ .network | quote }}
  {{- with .allocated_ip_range }}
  allocatedIpRange: {{ . | quote }}
  {{- end }}
{{- end }}
{{- $b := $v.automated_backup_configuration | default dict }}
{{- if $b.enabled }}
{{- $w := $b.weekly_schedule | default dict }}
{{- $starts := $w.start_times }}{{ if kindIs "invalid" $starts }}{{ $starts = list (dict "hours" 23) }}{{ end }}
{{- $labels := include "alloydb.cloudLabels" $root | fromJson }}
automatedBackupPolicy:
  enabled: true
  {{- $loc := $b.location }}{{ if not $primary }}{{ $loc = ($v.cross_region_replication | default dict).region }}{{ end }}
  {{- with $loc }}
  location: {{ . | quote }}
  {{- end }}
  backupWindow: {{ $b.backup_window | default "1800s" | quote }}
  {{- with $labels }}
  labels:
    {{- range $k := keys . | sortAlpha }}
    {{ $k }}: {{ index $labels $k | quote }}
    {{- end }}
  {{- end }}
  {{- with $kms }}
  encryptionConfig:
    kmsKeyNameRef:
      external: {{ . | quote }}
  {{- end }}
  weeklySchedule:
    daysOfWeek: {{ toJson ($w.days_of_week | default (list "MONDAY" "TUESDAY" "WEDNESDAY" "THURSDAY" "FRIDAY" "SATURDAY" "SUNDAY")) }}
    startTimes:
      {{- range $starts }}
      - hours: {{ .hours | int }}
        minutes: 0
        seconds: 0
        nanos: 0
      {{- end }}
  quantityBasedRetention:
    count: {{ $b.retention_count | default 7 | int }}
  {{- with $b.retention_period }}
  timeBasedRetention:
    retentionPeriod: {{ . | quote }}
  {{- end }}
{{- end }}
{{- $cb := $v.continuous_backup_configuration | default dict }}
continuousBackupConfig:
  enabled: {{ ternary true $cb.enabled (kindIs "invalid" $cb.enabled) }}
  recoveryWindowDays: {{ ternary 14 $cb.recovery_window_days (kindIs "invalid" $cb.recovery_window_days) | int }}
  {{- with $kms }}
  encryptionConfig:
    kmsKeyNameRef:
      external: {{ . | quote }}
  {{- end }}
{{- with $kms }}
encryptionConfig:
  kmsKeyNameRef:
    external: {{ . | quote }}
{{- end }}
{{- $m := $v.maintenance_config | default dict }}
{{- if $m.enabled }}
maintenanceUpdatePolicy:
  maintenanceWindows:
    - day: {{ $m.day | default "SUNDAY" }}
      startTime:
        hours: {{ ternary 23 ($m.start_time | default dict).hours (kindIs "invalid" ($m.start_time | default dict).hours) | int }}
        minutes: 0
        seconds: 0
        nanos: 0
{{- end }}
{{- end -}}

{{- /* alloydb.instanceSpec: the spec fields every instance shares:
annotations, flags, connection pooling, machine, public IP, insights.
(dict "root" $ "flags" <map> "machine" <machine_config> "network"
<{authorized_external_networks, enable_public_ip, enable_outbound_public_ip}>
"insights" <query_insights_config> "observability" <observability_config>) */ -}}
{{- define "alloydb.instanceSpec" -}}
{{- $v := .root.Values -}}
{{- with $v.annotations }}
annotations:
  {{- range $k := keys . | sortAlpha }}
  {{ $k | quote }}: {{ index $v.annotations $k | quote }}
  {{- end }}
{{- end }}
{{- with .flags }}
{{- $flags := . }}
databaseFlags:
  {{- range $k := keys . | sortAlpha }}
  {{ $k | quote }}: {{ index $flags $k | quote }}
  {{- end }}
{{- end }}
{{- with $v.connection_pool_flags }}
connectionPoolConfig:
  enabled: true
  flags:
    {{- range $k := keys . | sortAlpha }}
    {{ $k | quote }}: {{ index $v.connection_pool_flags $k | quote }}
    {{- end }}
{{- end }}
{{- $mc := .machine | default dict }}
machineConfig:
  cpuCount: {{ $mc.cpu_count | default 2 | int }}
  {{- with $mc.machine_type }}
  machineType: {{ . | quote }}
  {{- end }}
{{- $n := .network | default dict }}
{{- if or $n.enable_public_ip $n.enable_outbound_public_ip }}
networkConfig:
  {{- with $n.authorized_external_networks }}
  authorizedExternalNetworks:
    {{- range uniq . | sortAlpha }}
    - cidrRange: {{ . | quote }}
    {{- end }}
  {{- end }}
  {{- if $n.enable_public_ip }}
  enablePublicIp: true
  {{- end }}
  {{- if $n.enable_outbound_public_ip }}
  enableOutboundPublicIp: true
  {{- end }}
{{- end }}
{{- $obs := .observability | default dict }}
{{- if and (not (kindIs "invalid" .insights)) (not $obs.enabled) }}
{{- $q := .insights }}
queryInsightsConfig:
  queryStringLength: {{ ternary 1024 $q.query_string_length (kindIs "invalid" $q.query_string_length) | int }}
  recordApplicationTags: {{ ternary true $q.record_application_tags (kindIs "invalid" $q.record_application_tags) }}
  recordClientAddress: {{ ternary true $q.record_client_address (kindIs "invalid" $q.record_client_address) }}
  queryPlansPerMinute: {{ ternary 5 $q.query_plans_per_minute (kindIs "invalid" $q.query_plans_per_minute) | int }}
{{- end }}
{{- if $obs.enabled }}
observabilityConfig:
  enabled: true
  preserveComments: {{ $obs.preserve_comments | default false }}
  trackWaitEvents: {{ ternary true $obs.track_wait_events (kindIs "invalid" $obs.track_wait_events) }}
  maxQueryStringLength: {{ ternary 10240 $obs.max_query_string_length (kindIs "invalid" $obs.max_query_string_length) | int }}
  recordApplicationTags: {{ $obs.record_application_tags | default false }}
  queryPlansPerMinute: {{ ternary 20 $obs.query_plans_per_minute (kindIs "invalid" $obs.query_plans_per_minute) | int }}
  trackActiveQueries: {{ $obs.track_active_queries | default false }}
  trackClientAddress: {{ $obs.track_client_address | default false }}
  assistiveExperiencesEnabled: {{ $obs.assistive_experiences_enabled | default false }}
{{- end }}
{{- end -}}
