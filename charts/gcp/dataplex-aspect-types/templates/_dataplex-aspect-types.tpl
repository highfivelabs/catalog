{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* dataplexAspectTypes.all: aspect_types merged with the factory's files,
as JSON, as fabric's local.aspect_types merges them (a file wins over the
variable's entry of the same key, whole). */}}
{{- define "dataplexAspectTypes.all" -}}
{{- $out := dict -}}
{{- range $k, $t := (.Values.aspect_types | default dict) -}}
{{- $_ := set $out $k ($t | default dict) -}}
{{- end -}}
{{- range $k, $t := ((.Values.factories_data | default dict).aspect_types | default dict) -}}
{{- $_ := set $out $k ($t | default dict) -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/* dataplexAspectTypes.object: the Kubernetes name of one aspect type's
object. */}}
{{- define "dataplexAspectTypes.object" -}}
{{- include "kcc.name" (list (index . 0).Release.Name (index . 1)) -}}
{{- end -}}
