{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* geapAgentGateway.accessPath: fabric's local.access_path: CLIENT_TO_AGENT
for ingress (any case) or CLIENT_TO_AGENT, else AGENT_TO_ANYWHERE. */}}
{{- define "geapAgentGateway.accessPath" -}}
{{- $p := .Values.access_path -}}
{{- if and (not (kindIs "invalid" $p)) (or (eq (lower (toString $p)) "ingress") (eq (toString $p) "CLIENT_TO_AGENT")) -}}
CLIENT_TO_AGENT
{{- else -}}
AGENT_TO_ANYWHERE
{{- end -}}
{{- end -}}

{{/* geapAgentGateway.gateway: the gateway's ID: names.gateway, else name,
with the namePrefix. */}}
{{- define "geapAgentGateway.gateway" -}}
{{- include "kcc.resourceName" (list . "gateway" "agent gateway" .Values.name 63 "letter") -}}
{{- end -}}

{{/* geapAgentGateway.template: the connectivity template's ID:
names.connectivityTemplate, else networking_config.name or name, with the
namePrefix. */}}
{{- define "geapAgentGateway.template" -}}
{{- $nc := .Values.networking_config | default dict -}}
{{- include "kcc.resourceName" (list . "connectivityTemplate" "agent connectivity template" ($nc.name | default .Values.name) 63 "letter") -}}
{{- end -}}

{{/* geapAgentGateway.cloudLabels: the unprefixed keys of the chart's tags
and labels, and of the object's own labels (given as the second item),
which reach the cloud, as JSON. */}}
{{- define "geapAgentGateway.cloudLabels" -}}
{{- $out := dict -}}
{{- range $k, $l := (include "kcc.labels" (list (index . 0) (index . 1)) | fromJson) -}}
{{- if not (contains "/" $k) }}{{ $_ := set $out $k $l }}{{ end -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}
