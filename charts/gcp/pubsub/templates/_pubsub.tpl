{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* pubsub.topic: the topic name: names.topic in full when set; else name,
as fabric names it, with the namePrefix in front (at most 255 characters,
starting with a letter). */}}
{{- define "pubsub.topic" -}}
{{- include "kcc.resourceName" (list . "topic" "topic" .Values.name 255 "letter") -}}
{{- end -}}

{{/* pubsub.subObject: a subscription's Kubernetes name. (list $ <key>) */}}
{{- define "pubsub.subObject" -}}
{{- include "kcc.name" (list (index . 0).Release.Name "sub" (index . 1)) -}}
{{- end -}}

{{/* pubsub.table: a BigQuery table as Config Connector's external
reference, from fabric's "<project>.<dataset>.<table>" or
"<project>:<dataset>.<table>"; any other form is passed as given. */}}
{{- define "pubsub.table" -}}
{{- $p := splitList "." (replace ":" "." .) -}}
{{- if eq (len $p) 3 -}}
{{- printf "projects/%s/datasets/%s/tables/%s" (index $p 0) (index $p 1) (index $p 2) -}}
{{- else -}}
{{- . -}}
{{- end -}}
{{- end -}}
