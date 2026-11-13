{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Helpers for the port of cloud-foundation-fabric modules/gke-cluster-autopilot
(v60.0.0), Copyright 2024 Google LLC, Apache-2.0.
*/ -}}

{{/*
gks.d: an object variable with fabric's optional() defaults filled in, as
JSON: each default key the value leaves unset (or null) takes the default.
  {{ include "gks.d" (list $v.enable_addons (dict "dns_cache" true)) | fromJson }}
*/}}
{{- define "gks.d" -}}
{{- $in := index . 0 | default dict -}}{{- $def := index . 1 -}}
{{- $out := deepCopy $in -}}
{{- range $k, $d := $def -}}
{{- if kindIs "invalid" (index $out $k) }}{{ $_ := set $out $k $d }}{{ end -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/*
gks.ref: an ID or self link as Config Connector's external form (no
https://www.googleapis.com/compute/v1/ prefix).
*/}}
{{- define "gks.ref" -}}
{{- trimPrefix "https://www.googleapis.com/compute/v1/" (toString .) -}}
{{- end -}}

{{/*
gks.gk: a list of {resource_group, resource_kind} as Config Connector's
[{resourceGroup, resourceKind}], as JSON.
*/}}
{{- define "gks.gk" -}}
{{- $out := list -}}
{{- range $g := . -}}
{{- $o := dict -}}
{{- with $g.resource_group }}{{ $_ := set $o "resourceGroup" . }}{{ end -}}
{{- with $g.resource_kind }}{{ $_ := set $o "resourceKind" . }}{{ end -}}
{{- $out = append $out $o -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}
