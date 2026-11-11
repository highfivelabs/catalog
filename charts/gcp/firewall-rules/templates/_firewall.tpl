{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

Helpers of the firewall-rules chart.
*/ -}}

{{/*
fw.networkSelfLink: the network as Terraform records it in a
google_compute_firewall's network attribute, its self link
(https://www.googleapis.com/compute/v1/projects/<p>/global/networks/<n>).
The module passes network_name as given; the provider accepts a name, a
projects/... path or a self link and stores the self link. A plain name is
in project_id.
*/}}
{{- define "fw.networkSelfLink" -}}
{{- $n := .Values.network_name -}}
{{- if contains "projects/" $n -}}
{{- printf "https://www.googleapis.com/compute/v1/%s" (regexReplaceAll "^.*?(projects/)" $n "${1}") -}}
{{- else if contains "/" $n -}}
{{- fail (printf "firewall-rules: network_name %q is neither a network name, a projects/<project>/global/networks/<name> path nor a self link" $n) -}}
{{- else -}}
{{- printf "https://www.googleapis.com/compute/v1/projects/%s/global/networks/%s" .Values.project_id $n -}}
{{- end -}}
{{- end -}}

{{/*
fw.protocols: the allow or deny blocks of one rule (the module's dynamic
"allow" and "deny" blocks): protocol, and ports when set.
*/}}
{{- define "fw.protocols" -}}
{{- range $p := . }}
- protocol: {{ $p.protocol | quote }}
{{- with $p.ports }}
  ports:
{{- range $port := . }}
    - {{ toString $port | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
fw.rule: one google_compute_firewall as a ComputeFirewall.
  root       $
  id         the object's hfl.dev/id
  rule       the rule's entry, with direction set
  sources    source ranges, or nil
  dests      destination ranges, or nil
*/}}
{{- define "fw.rule" -}}
{{- $ := .root -}}
{{- $r := .rule -}}
---
apiVersion: compute.cnrm.cloud.google.com/v1beta1
kind: ComputeFirewall
metadata:
  {{- include "kcc.metadata" (dict "root" $ "name" (include "kcc.name" (list $.Release.Name $r.name)) "id" .id "project" $.Values.project_id "abandon" (include "kcc.abandon" $)) | nindent 2 }}
spec:
  resourceID: {{ include "kcc.cloudName" (list $ "firewall rule" $r.name 63 "letter") }}
  networkRef:
    external: {{ include "fw.networkSelfLink" $ | quote }}
  direction: {{ $r.direction }}
{{- with $r.description }}
  description: {{ . | quote }}
{{- end }}
  {{- /* disabled and priority: what Terraform records when the module passes null (false, and the provider's default 1000) */}}
  disabled: {{ ternary false $r.disabled (kindIs "invalid" $r.disabled) }}
  priority: {{ ternary 1000 (int64 ($r.priority | default 0)) (kindIs "invalid" $r.priority) }}
{{- with .sources }}
  sourceRanges:
{{- range . }}
    - {{ . | quote }}
{{- end }}
{{- end }}
{{- with .dests }}
  destinationRanges:
{{- range . }}
    - {{ . | quote }}
{{- end }}
{{- end }}
{{- with $r.source_tags }}
  sourceTags:
{{- range . }}
    - {{ . | quote }}
{{- end }}
{{- end }}
{{- with $r.source_service_accounts }}
  sourceServiceAccounts:
{{- range . }}
    - external: {{ . | quote }}
{{- end }}
{{- end }}
{{- with $r.target_tags }}
  targetTags:
{{- range . }}
    - {{ . | quote }}
{{- end }}
{{- end }}
{{- with $r.target_service_accounts }}
  targetServiceAccounts:
{{- range . }}
    - external: {{ . | quote }}
{{- end }}
{{- end }}
{{- with $r.allow }}
  allow:
{{- include "fw.protocols" . | trim | nindent 4 }}
{{- end }}
{{- with $r.deny }}
  deny:
{{- include "fw.protocols" . | trim | nindent 4 }}
{{- end }}
{{- with $r.log_config }}
  logConfig:
    metadata: {{ .metadata | quote }}
{{- end }}
{{- end -}}
