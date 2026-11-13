{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Helpers for the port of cloud-foundation-fabric modules/folder (v60.0.0),
Copyright 2025 Google LLC, Apache-2.0.
*/ -}}

{{/* folder.create: "true" when the chart makes the Folder (folder_create,
the default), "" when it uses the existing folder id names. */}}
{{- define "folder.create" -}}
{{- if ne (toString .Values.folder_create) "false" -}}true{{- end -}}
{{- end -}}

{{/* folder.number: the existing folder's number, from id (folders/N or N). */}}
{{- define "folder.number" -}}
{{- trimPrefix "folders/" (toString .Values.id) -}}
{{- end -}}

{{/* folder.ref: the folder as a typed reference (folderRef). */}}
{{- define "folder.ref" -}}
{{- if include "folder.create" . -}}
name: {{ .Release.Name }}
{{- else -}}
external: {{ printf "folders/%s" (include "folder.number" .) | quote }}
{{- end -}}
{{- end -}}

{{/* folder.iamRef: the folder as an IAM resourceRef. */}}
{{- define "folder.iamRef" -}}
apiVersion: resourcemanager.cnrm.cloud.google.com/v1beta1
kind: Folder
{{- if include "folder.create" . }}
name: {{ .Release.Name }}
{{- else }}
external: {{ printf "folders/%s" (include "folder.number" .) | quote }}
{{- end }}
{{- end -}}

{{/* folder.idOrName: the folder for a description: folders/N when it
exists already, else its display name (its number is not known until it
is made). */}}
{{- define "folder.idOrName" -}}
{{- if include "folder.create" . -}}
{{- include "folder.displayName" . -}}
{{- else -}}
folders/{{ include "folder.number" . }}
{{- end -}}
{{- end -}}

{{/* folder.displayName: names.folder in full when set, else name with the
namePrefix (a folder's display name is at most 30 characters). */}}
{{- define "folder.displayName" -}}
{{- include "kcc.resourceName" (list . "folder" "folder display" (toString .Values.name) 30) -}}
{{- end -}}
