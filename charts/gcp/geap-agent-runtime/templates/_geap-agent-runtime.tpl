{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* geapAgentRuntime.package: deployment_config.package_config with
fabric's optional defaults filled in, as JSON, or "" when it is not set. A
false given by the caller is kept (sprig's default would replace it). */}}
{{- define "geapAgentRuntime.package" -}}
{{- $p := (.Values.deployment_config | default dict).package_config -}}
{{- if not (kindIs "invalid" $p) -}}
{{- $out := dict
  "are_paths_local" (ternary $p.are_paths_local true (and (hasKey $p "are_paths_local") (not (kindIs "invalid" $p.are_paths_local))))
  "dependencies_path" ($p.dependencies_path | default "./src/dependencies.tar.gz")
  "pickle_path" ($p.pickle_path | default "./src/pickle.pkl")
  "requirements_path" ($p.requirements_path | default "./src/requirements.txt") -}}
{{- toJson $out -}}
{{- end -}}
{{- end -}}

{{/* geapAgentRuntime.saCreate: "true" when the chart makes the service
account (fabric: service_account_config.create and identity_type
SERVICE_ACCOUNT), else "". */}}
{{- define "geapAgentRuntime.saCreate" -}}
{{- $sa := .Values.service_account_config | default dict -}}
{{- $create := ternary $sa.create true (and (hasKey $sa "create") (not (kindIs "invalid" $sa.create))) -}}
{{- if and $create (eq (toString .Values.agent_runtime_config.identity_type) "SERVICE_ACCOUNT") }}true{{ end -}}
{{- end -}}

{{/* geapAgentRuntime.accountId: the service account ID: names.serviceAccount,
else service_account_config.name or name, with the namePrefix. */}}
{{- define "geapAgentRuntime.accountId" -}}
{{- $sa := .Values.service_account_config | default dict -}}
{{- $id := include "kcc.resourceName" (list . "serviceAccount" "service account ID" ($sa.name | default .Values.name) 30 "letter") -}}
{{- if not (regexMatch "^[a-z](?:[-a-z0-9]{4,28}[a-z0-9])$" $id) -}}
{{- fail (printf "geap-agent-runtime: the service account ID %q must be 6 to 30 lower-case letters, digits or hyphens, start with a letter and not end with a hyphen" $id) -}}
{{- end -}}
{{- $id -}}
{{- end -}}

{{/* geapAgentRuntime.bucket: the bucket's name: names.bucket, else
bucket_config.name or name, with the namePrefix. */}}
{{- define "geapAgentRuntime.bucket" -}}
{{- $b := .Values.bucket_config | default dict -}}
{{- include "kcc.resourceName" (list . "bucket" "bucket" ($b.name | default .Values.name) 63) -}}
{{- end -}}

{{/* geapAgentRuntime.cloudLabels: the unprefixed keys of the chart's tags
and labels, which reach the cloud, as JSON. */}}
{{- define "geapAgentRuntime.cloudLabels" -}}
{{- $out := dict -}}
{{- range $k, $l := (include "kcc.labels" (list . dict) | fromJson) -}}
{{- if not (contains "/" $k) }}{{ $_ := set $out $k $l }}{{ end -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}
