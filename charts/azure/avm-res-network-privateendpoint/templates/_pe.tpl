{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
This chart's own helpers.
*/ -}}

{{/*
pe.anySet: "true" when a value holds a non-empty leaf anywhere (a string,
a number, a boolean true, or a non-empty list), else "". ignore_body_changes
and resource_types default to empty maps and lists, which are not a
setting.
*/}}
{{- define "pe.anySet" -}}
{{- if kindIs "map" . -}}
{{- range $_, $v := . -}}{{- include "pe.anySet" $v -}}{{- end -}}
{{- else if kindIs "slice" . -}}
{{- if gt (len .) 0 -}}true{{- end -}}
{{- else if not (empty .) -}}true
{{- end -}}
{{- end -}}
