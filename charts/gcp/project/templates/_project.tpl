{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Ported from cloud-foundation-fabric modules/project (v60.0.0),
Copyright 2025 Google LLC, Apache-2.0.
*/ -}}

{{/* project.id: "<prefix>-<name>", as fabric names it, with the namePrefix in
front (a project ID is global and never reusable: 6 to 30 characters). */}}
{{- define "project.id" -}}
{{- $n := .Values.name -}}
{{- if .Values.prefix -}}{{- $n = printf "%s-%s" .Values.prefix .Values.name -}}{{- end -}}
{{- include "kcc.cloudName" (list . "project ID" $n 30 "letter") -}}
{{- end -}}

{{/* project.ref: the project as a typed reference (projectRef). */}}
{{- define "project.ref" -}}
{{- if not (kindIs "invalid" .Values.project_reuse) -}}
external: {{ include "project.id" . }}
{{- else -}}
name: {{ .Release.Name }}
{{- end -}}
{{- end -}}

{{/* project.iamRef: the project as an IAM resourceRef. */}}
{{- define "project.iamRef" -}}
apiVersion: resourcemanager.cnrm.cloud.google.com/v1beta1
kind: Project
{{- if not (kindIs "invalid" .Values.project_reuse) }}
external: projects/{{ include "project.id" . }}
{{- else }}
name: {{ .Release.Name }}
{{- end }}
{{- end -}}
