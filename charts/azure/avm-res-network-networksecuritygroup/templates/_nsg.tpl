{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
This chart's own helpers.
*/ -}}

{{/*
nsg.anySet: "true" when a value holds a non-empty leaf anywhere (a string,
a number, a boolean true, or a non-empty list), else "". ignore_body_changes
defaults to empty lists inside a map, which are not a setting.
*/}}
{{- define "nsg.anySet" -}}
{{- if kindIs "map" . -}}
{{- range $_, $v := . -}}{{- include "nsg.anySet" $v -}}{{- end -}}
{{- else if kindIs "slice" . -}}
{{- if gt (len .) 0 -}}true{{- end -}}
{{- else if not (empty .) -}}true
{{- end -}}
{{- end -}}

{{/*
nsg.strings: a Terraform set(string) as a sorted YAML list (Terraform sorts
a set's members).
*/}}
{{- define "nsg.strings" -}}
{{- range (uniq . | sortAlpha) }}
- {{ . | quote }}
{{- end -}}
{{- end -}}

{{/*
nsg.asgs: a set of application security group IDs as ASO references,
sorted.
*/}}
{{- define "nsg.asgs" -}}
{{- range (uniq . | sortAlpha) }}
- reference:
    armId: {{ . | quote }}
{{- end -}}
{{- end -}}
