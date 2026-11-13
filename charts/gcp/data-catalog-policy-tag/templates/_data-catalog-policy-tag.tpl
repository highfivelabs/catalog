{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* dataCatalogPolicyTag.tags: tags merged with the factory file's tags,
as JSON, as fabric's local.tags merges them (the file's tag wins). */}}
{{- define "dataCatalogPolicyTag.tags" -}}
{{- $out := dict -}}
{{- range $k, $t := .Values.tags -}}
{{- $_ := set $out $k ($t | default dict) -}}
{{- end -}}
{{- $f := .Values.factories_data.taxonomy | default dict -}}
{{- range $k, $t := ($f.tags | default dict) -}}
{{- $_ := set $out $k ($t | default dict) -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}
