{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

spannerInstance.id: the instance ID, names.instance in full, else
instance.name with the namePrefix (docs/design.md, "Names, labels and
tags"). Computed the same way when instance_create is false, so
names.instance names the existing instance.
*/ -}}
{{- define "spannerInstance.id" -}}
{{- include "kcc.resourceName" (list . "instance" "instance" .Values.instance.name 64 "letter") -}}
{{- end -}}

{{- /*
spannerInstance.cloudLabels: the Google Cloud labels of an object whose
kind takes them from spec.labels (config-connector-extensions'
SpannerInstanceConfig): the unprefixed keys of the chart's tags and labels
and the object's own, as JSON.
  include "spannerInstance.cloudLabels" (list $ $own)
*/ -}}
{{- define "spannerInstance.cloudLabels" -}}
{{- $all := include "kcc.labels" (list (index . 0) (index . 1)) | fromJson -}}
{{- $cloud := dict -}}
{{- range $k, $l := $all }}{{ if not (contains "/" $k) }}{{ $_ := set $cloud $k $l }}{{ end }}{{ end -}}
{{- $cloud | toJson -}}
{{- end -}}
