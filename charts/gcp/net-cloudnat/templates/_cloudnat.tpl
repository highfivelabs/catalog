{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Ported from cloud-foundation-fabric modules/net-cloudnat/main.tf
(v60.0.0), Copyright 2024 Google LLC, Apache-2.0.

Helpers of the net-cloudnat chart.
*/ -}}

{{/* cloudnat.natName: names.nat in full when set; else name with the
namePrefix (at most 63 characters, starting with a letter). */}}
{{- define "cloudnat.natName" -}}
{{- include "kcc.resourceName" (list . "nat" "NAT" .Values.name 63 "letter") -}}
{{- end -}}

{{/* cloudnat.routerName: the router's name in Google Cloud. With
router_create: names.router in full when set, else router_name, else
"<name>-nat", as fabric names it, with the namePrefix. Without: router_name
as given, an existing router (no prefix). */}}
{{- define "cloudnat.routerName" -}}
{{- if .Values.router_create -}}
{{- include "kcc.resourceName" (list . "router" "router" (.Values.router_name | default (printf "%s-nat" .Values.name)) 63 "letter") -}}
{{- else -}}
{{- .Values.router_name -}}
{{- end -}}
{{- end -}}

{{/* cloudnat.networkSelfLink: router_network as Terraform records a
google_compute_router's network, its self link. The provider accepts a
name (in project_id), a projects/... path or a self link. */}}
{{- define "cloudnat.networkSelfLink" -}}
{{- $n := .Values.router_network -}}
{{- if contains "projects/" $n -}}
{{- printf "https://www.googleapis.com/compute/v1/%s" (regexReplaceAll "^.*?(projects/)" $n "${1}") -}}
{{- else if contains "/" $n -}}
{{- fail (printf "net-cloudnat: router_network %q is neither a network name, a projects/<project>/global/networks/<name> path nor a self link" $n) -}}
{{- else -}}
{{- printf "https://www.googleapis.com/compute/v1/projects/%s/global/networks/%s" .Values.project_id $n -}}
{{- end -}}
{{- end -}}

{{/* cloudnat.subnetConfig: source_subnetwork_ip_ranges_to_nat, as the
module's local subnet_config computes it. */}}
{{- define "cloudnat.subnetConfig" -}}
{{- $c := .Values.config_source_subnetworks | default dict -}}
{{- $all := true -}}
{{- if hasKey $c "all" }}{{ if not (kindIs "invalid" $c.all) }}{{ $all = $c.all }}{{ end }}{{ end -}}
{{- if ne $all true -}}LIST_OF_SUBNETWORKS
{{- else if eq $c.primary_ranges_only true -}}ALL_SUBNETWORKS_ALL_PRIMARY_IP_RANGES
{{- else -}}ALL_SUBNETWORKS_ALL_IP_RANGES
{{- end -}}
{{- end -}}

{{/* cloudnat.refs: a list of references, each {external: <value>}, as
YAML. */}}
{{- define "cloudnat.refs" -}}
{{- range $i, $x := . }}
{{- if $i }}{{ "\n" }}{{ end -}}
- external: {{ $x | quote }}
{{- end }}
{{- end -}}
