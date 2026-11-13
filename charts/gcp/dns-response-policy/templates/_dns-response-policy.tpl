{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* dnsResponsePolicy.rules: the factory file's rules merged with the
rules variable, as JSON, as fabric's merge(local.factory_rules, var.rules)
does (a rule of the variable wins, whole), with fabric's defaults filled
in: behavior bypassResponsePolicy, and each local data entry's ttl null
and rrdatas []. */}}
{{- define "dnsResponsePolicy.rules" -}}
{{- $out := dict -}}
{{- range $src := list ((.Values.factories_data | default dict).rules | default dict) (.Values.rules | default dict) -}}
{{- range $k, $r := $src -}}
{{- $r = $r | default dict -}}
{{- $ld := dict -}}
{{- range $t, $d := ($r.local_data | default dict) -}}
{{- $d = $d | default dict -}}
{{- $_ := set $ld $t (dict "ttl" $d.ttl "rrdatas" ($d.rrdatas | default list)) -}}
{{- end -}}
{{- $_ := set $out $k (dict "dns_name" $r.dns_name "behavior" ($r.behavior | default "bypassResponsePolicy") "local_data" $ld) -}}
{{- end -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/* dnsResponsePolicy.name: the response policy's name: names.policy in
full, else name with the namePrefix. The same whether the chart makes the
policy or (policy_create: false) only names an existing one. */}}
{{- define "dnsResponsePolicy.name" -}}
{{- include "kcc.resourceName" (list . "policy" "response policy" .Values.name 63) -}}
{{- end -}}
