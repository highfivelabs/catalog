{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* loggingBucket.name: the bucket's ID: names.bucket, else name, with the
namePrefix. */}}
{{- define "loggingBucket.name" -}}
{{- include "kcc.resourceName" (list . "bucket" "log bucket" .Values.name 100) -}}
{{- end -}}

{{/* loggingBucket.parentRef: the parent reference of the bucket and its
views, by parent_type, as YAML. */}}
{{- define "loggingBucket.parentRef" -}}
{{- $field := get (dict "project" "projectRef" "folder" "folderRef" "organization" "organizationRef" "billing_account" "billingAccountRef") (.Values.parent_type | default "project") -}}
{{ $field }}:
  external: {{ .Values.parent | quote }}
{{- end -}}

{{/* loggingBucket.id: the bucket's full name, as fabric's id output:
projects/<p>, folders/<f>, organizations/<o> or billingAccounts/<b>, then
/locations/<location>/buckets/<id>. */}}
{{- define "loggingBucket.id" -}}
{{- $v := .Values -}}
{{- $t := $v.parent_type | default "project" -}}
{{- $p := $v.parent -}}
{{- $parent := "" -}}
{{- if eq $t "project" }}{{ $parent = printf "projects/%s" $p }}
{{- else if eq $t "folder" }}{{ $parent = ternary $p (printf "folders/%s" $p) (hasPrefix "folders/" $p) }}
{{- else if eq $t "organization" }}{{ $parent = ternary $p (printf "organizations/%s" $p) (hasPrefix "organizations/" $p) }}
{{- else }}{{ $parent = ternary $p (printf "billingAccounts/%s" $p) (hasPrefix "billingAccounts/" $p) }}
{{- end -}}
{{- printf "%s/locations/%s/buckets/%s" $parent $v.location (include "loggingBucket.name" .) -}}
{{- end -}}

{{/* loggingBucket.project: the project annotation: the parent for a
project bucket, else "". */}}
{{- define "loggingBucket.project" -}}
{{- if eq (.Values.parent_type | default "project") "project" }}{{ .Values.parent }}{{ end -}}
{{- end -}}
