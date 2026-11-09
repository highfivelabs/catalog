{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Ported from cloud-foundation-fabric modules/net-vpc (v60.0.0),
Copyright 2025 Google LLC, Apache-2.0.
*/ -}}

{{/* netvpc.networkRef: the network as a typed reference. */}}
{{- define "netvpc.networkRef" -}}
{{- if not (kindIs "invalid" .Values.vpc_reuse) -}}
external: {{ include "netvpc.networkId" . }}
{{- else -}}
name: {{ .Release.Name }}
{{- end -}}
{{- end -}}

{{/* netvpc.networkName: the network's name in Google Cloud, with the
namePrefix (at most 63 characters). */}}
{{- define "netvpc.networkName" -}}
{{- include "kcc.cloudName" (list . "network" .Values.name 63 "letter") -}}
{{- end -}}

{{/* netvpc.networkId: projects/<project>/global/networks/<name>. */}}
{{- define "netvpc.networkId" -}}
{{- if not .Values.project_id -}}
{{- fail "net-vpc: project_id is needed to name the network outside this chart (vpc_reuse, a remote peering, Shared VPC service projects)" -}}
{{- end -}}
{{- printf "projects/%s/global/networks/%s" .Values.project_id (include "netvpc.networkName" .) -}}
{{- end -}}

{{/*
netvpc.subnets: every subnet as JSON, {"<region>/<name>": SUBNET}, from
subnets, subnets_proxy_only, subnets_private_nat, subnets_psc and the
subnet factory's data, each with _type (regular, proxy_only,
private_nat or psc) and fabric's defaults applied, as subnets.tf does.
*/}}
{{- define "netvpc.subnets" -}}
{{- $all := dict -}}
{{- range $type, $list := dict "regular" .Values.subnets "proxy_only" .Values.subnets_proxy_only "private_nat" .Values.subnets_private_nat "psc" .Values.subnets_psc -}}
{{- range $s := $list -}}
{{- $_ := set $all (printf "%s/%s" $s.region $s.name) (merge (dict "_type" $type) $s) -}}
{{- end -}}
{{- end -}}
{{- range $file, $v := ((.Values.factories_data | default dict).subnets | default dict) -}}
{{- $type := "regular" -}}
{{- if $v.psc }}{{ $type = "psc" }}{{ else if $v.proxy_only }}{{ $type = "proxy_only" }}{{ else if $v.private_nat }}{{ $type = "private_nat" }}{{ end -}}
{{- $s := merge (dict "_type" $type "name" ($v.name | default $file)) (omit $v "psc" "proxy_only" "private_nat") -}}
{{- if not (hasKey $s "enable_private_access") }}{{ $_ := set $s "enable_private_access" true }}{{ end -}}
{{- if not (hasKey $s "active") }}{{ $_ := set $s "active" true }}{{ end -}}
{{- $_ := set $all (printf "%s/%s" $s.region $s.name) $s -}}
{{- end -}}
{{- toJson $all -}}
{{- end -}}
