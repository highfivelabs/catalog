{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* cbConnection.name: the connection's ID: names.connection in full,
else name with the namePrefix, whether or not the chart creates it
(docs/design.md, "Names, labels and tags"). */}}
{{- define "cbConnection.name" -}}
{{- include "kcc.resourceName" (list . "connection" "connection" .Values.name 63) -}}
{{- end -}}

{{/* cbConnection.id: the connection's full name, fabric's id output. */}}
{{- define "cbConnection.id" -}}
{{- printf "projects/%s/locations/%s/connections/%s" .Values.project_id .Values.location (include "cbConnection.name" .) -}}
{{- end -}}

{{/* cbConnection.repoName: the ID of the repository of one key: the key,
with the namePrefix. */}}
{{- define "cbConnection.repoName" -}}
{{- include "kcc.cloudName" (list (index . 0) "repository" (index . 1) 63) -}}
{{- end -}}

{{/* cbConnection.ref: the connection as an IAM resourceRef: its object
when the chart creates it, else its full name. */}}
{{- define "cbConnection.ref" -}}
apiVersion: cloudbuild.gcp.hfl.dev/v1beta1
kind: CloudBuildConnection
{{- if .Values.connection_create }}
name: {{ .Release.Name }}
{{- else }}
external: {{ include "cbConnection.id" . | quote }}
{{- end }}
{{- end -}}

{{/* cbConnection.int: a GitHub App ID or installation ID as the integer
the kind takes (fabric's variable is a string). */}}
{{- define "cbConnection.int" -}}
{{- $what := index . 1 -}}{{- $v := toString (index . 2) -}}
{{- if not (regexMatch "^[0-9]+$" $v) -}}
{{- fail (printf "%s: %s %q must be a number" (index . 0).Chart.Name $what $v) -}}
{{- end -}}
{{- $v -}}
{{- end -}}

{{/* cbConnection.bool: fabric's string invert_regex ("true", "false") as
the boolean the kind takes. */}}
{{- define "cbConnection.bool" -}}
{{- $what := index . 1 -}}{{- $v := toString (index . 2) -}}
{{- if not (has $v (list "true" "false")) -}}
{{- fail (printf "%s: %s %q must be true or false" (index . 0).Chart.Name $what $v) -}}
{{- end -}}
{{- $v -}}
{{- end -}}
