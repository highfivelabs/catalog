{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* gcs.bucketName: "<prefix>-<name>", lower-cased, as fabric names it. */}}
{{- define "gcs.bucketName" -}}
{{- if .Values.prefix -}}{{ printf "%s-%s" .Values.prefix (lower .Values.name) }}{{- else -}}{{ lower .Values.name }}{{- end -}}
{{- end -}}

{{/* gcs.iamRef: the bucket as an IAM resourceRef: the object this chart
makes, or the existing bucket by name. */}}
{{- define "gcs.iamRef" -}}
apiVersion: storage.cnrm.cloud.google.com/v1beta1
kind: StorageBucket
{{- if .Values.bucket_create }}
name: {{ .Release.Name }}
{{- else }}
external: {{ include "gcs.bucketName" . }}
{{- end }}
{{- end -}}

{{/* gcs.bucketRef: the bucket as a typed reference (bucketRef). */}}
{{- define "gcs.bucketRef" -}}
{{- if .Values.bucket_create -}}
name: {{ .Release.Name }}
{{- else -}}
external: {{ include "gcs.bucketName" . }}
{{- end -}}
{{- end -}}
