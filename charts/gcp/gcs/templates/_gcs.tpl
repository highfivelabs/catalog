{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* gcs.bucketName: names.bucket in full when set; else "<prefix>-<name>",
lower-cased, as fabric names it, with the namePrefix in front (a bucket
name is global, at most 63 characters). */}}
{{- define "gcs.bucketName" -}}
{{- $n := lower .Values.name -}}
{{- if .Values.prefix -}}{{- $n = printf "%s-%s" .Values.prefix $n -}}{{- end -}}
{{- include "kcc.resourceName" (list . "bucket" "bucket" $n 63) -}}
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
