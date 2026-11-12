{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* firewall.networkRef: the network, by its id: a name becomes
projects/<project>/global/networks/<name>; a self link is used without
its https://www.googleapis.com/compute/v1/ prefix. */}}
{{- define "firewall.network" -}}
{{- $n := .Values.network -}}
{{- if contains "/" $n -}}
{{- trimPrefix "https://www.googleapis.com/compute/v1/" $n -}}
{{- else -}}
{{- printf "projects/%s/global/networks/%s" .Values.project_id $n -}}
{{- end -}}
{{- end -}}

{{/* firewall.ranges: a rule's ranges with named ranges expanded (the
module's named_ranges over factories_data.cidr_tpl), distinct, as JSON.
(list $ <ranges>) */}}
{{- define "firewall.ranges" -}}
{{- $root := index . 0 -}}
{{- $named := merge (dict) ($root.Values.named_ranges | default dict) ($root.Values.factories_data.cidr_tpl | default dict) -}}
{{- $out := list -}}
{{- range $r := index . 1 -}}
{{- if hasKey $named $r }}{{ $out = concat $out (index $named $r) }}{{ else }}{{ $out = append $out $r }}{{ end -}}
{{- end -}}
{{- toJson (uniq $out) -}}
{{- end -}}
