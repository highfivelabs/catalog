{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

Helpers of the network-firewall-policy chart.
*/ -}}

{{/*
nfp.policyName: the policy's cloud name: names.policy, else policy_name
with the namePrefix in front.
*/}}
{{- define "nfp.policyName" -}}
{{- include "kcc.resourceName" (list . "policy" "network firewall policy" .Values.policy_name 63 "letter") -}}
{{- end -}}

{{/*
nfp.policyObject: the policy's Kubernetes name.
*/}}
{{- define "nfp.policyObject" -}}
{{- include "kcc.name" (list .Release.Name "policy") -}}
{{- end -}}

{{/*
nfp.selfLink: a network as Terraform records an association's
attachment_target, its self link
(https://www.googleapis.com/compute/v1/projects/<p>/global/networks/<n>),
from the VPC ID the module is given (projects/<p>/global/networks/<n>) or
a self link.
*/}}
{{- define "nfp.selfLink" -}}
{{- if contains "projects/" . -}}
{{- printf "https://www.googleapis.com/compute/v1/%s" (regexReplaceAll "^.*?(projects/)" . "${1}") -}}
{{- else -}}
{{- fail (printf "network-firewall-policy: target VPC %q is not a VPC ID (projects/<project>/global/networks/<name>) or a self link" .) -}}
{{- end -}}
{{- end -}}

{{/*
nfp.list: a YAML list of strings under a key, indented; nothing when the
list is empty or null (the module sends an empty list as no value).
  {{ include "nfp.list" (list "srcIpRanges" $m.src_ip_ranges 4) }}
*/}}
{{- define "nfp.list" -}}
{{- $key := index . 0 -}}{{- $items := index . 1 -}}{{- $n := index . 2 -}}
{{- with $items }}
{{ printf "%s:" $key | indent $n }}
{{- range . }}
{{ printf "- %s" (toString . | quote) | indent (add $n 2 | int) }}
{{- end }}
{{- end }}
{{- end -}}
