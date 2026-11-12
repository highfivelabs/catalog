{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* artifactRegistry.id: the repository ID: names.repository in full when
set; else name, as fabric names it (repository_id = var.name), with the
namePrefix in front (at most 63 characters, starting with a letter). */}}
{{- define "artifactRegistry.id" -}}
{{- include "kcc.resourceName" (list . "repository" "repository" .Values.name 63 "letter") -}}
{{- end -}}

{{/* artifactRegistry.format: the one format set ("docker"), checked as
fabric's validations check it. */}}
{{- define "artifactRegistry.format" -}}
{{- $set := list -}}
{{- range $k, $f := .Values.format -}}
{{- if not (kindIs "invalid" $f) }}{{ $set = append $set $k }}{{ end -}}
{{- end -}}
{{- if ne (len $set) 1 -}}
{{- fail "artifact-registry: format: Multiple or zero formats are not supported." -}}
{{- end -}}
{{- first $set -}}
{{- end -}}

{{/* artifactRegistry.mode: standard, remote or virtual, for the format
set: the one key whose value is neither null nor false. */}}
{{- define "artifactRegistry.mode" -}}
{{- $f := index .Values.format (include "artifactRegistry.format" .) -}}
{{- $set := list -}}
{{- range $k, $m := $f -}}
{{- if and (not (kindIs "invalid" $m)) (not (and (kindIs "bool" $m) (not $m))) }}{{ $set = append $set $k }}{{ end -}}
{{- end -}}
{{- if ne (len $set) 1 -}}
{{- fail "artifact-registry: format: Repository can only be one of standard, remote or virtual." -}}
{{- end -}}
{{- first $set -}}
{{- end -}}
