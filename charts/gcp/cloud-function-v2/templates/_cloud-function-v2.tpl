{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* cloudFunctionV2.prefix: fabric's local.prefix, "<prefix>-" or "". */}}
{{- define "cloudFunctionV2.prefix" -}}
{{- with .Values.prefix }}{{ . }}-{{ end -}}
{{- end -}}

{{/* cloudFunctionV2.function: the function's name: names.function in
full, else <prefix>-<name> with the namePrefix in front (63 characters, a
leading letter). */}}
{{- define "cloudFunctionV2.function" -}}
{{- include "kcc.resourceName" (list . "function" "function" (printf "%s%s" (include "cloudFunctionV2.prefix" .) .Values.name) 63 "letter") -}}
{{- end -}}

{{/* cloudFunctionV2.bucket: fabric's local.bucket. With bucket_config, the
bucket the chart creates: names.bucket in full, else
<prefix>-<bucket_name> with the namePrefix in front. Without, bucket_name
as given: it names a bucket the chart does not make. */}}
{{- define "cloudFunctionV2.bucket" -}}
{{- if .Values.bucket_config -}}
{{- include "kcc.resourceName" (list . "bucket" "bucket" (printf "%s%s" (include "cloudFunctionV2.prefix" .) .Values.bucket_name) 63) -}}
{{- else -}}
{{- .Values.bucket_name -}}
{{- end -}}
{{- end -}}

{{/* cloudFunctionV2.serviceAccount: the account ID of the service account
the chart creates: names.serviceAccount, else service_account_config.name
or name with the namePrefix in front (30 characters, a leading letter). */}}
{{- define "cloudFunctionV2.serviceAccount" -}}
{{- $c := .Values.service_account_config | default dict -}}
{{- include "kcc.resourceName" (list . "serviceAccount" "service account" ($c.name | default .Values.name) 30 "letter") -}}
{{- end -}}

{{/* cloudFunctionV2.triggerServiceAccount: the trigger's account ID:
names.triggerServiceAccount, else tf-cf-trigger-<name> with the
namePrefix in front. */}}
{{- define "cloudFunctionV2.triggerServiceAccount" -}}
{{- include "kcc.resourceName" (list . "triggerServiceAccount" "service account" (printf "tf-cf-trigger-%s" .Values.name) 30 "letter") -}}
{{- end -}}

{{/* cloudFunctionV2.vpcConnector: the connector's name: names.vpcConnector,
else vpc_connector_create.name or name with the namePrefix in front (25
characters, a leading letter). */}}
{{- define "cloudFunctionV2.vpcConnector" -}}
{{- include "kcc.resourceName" (list . "vpcConnector" "VPC connector" (.Values.vpc_connector_create.name | default .Values.name) 25 "letter") -}}
{{- end -}}

{{/* cloudFunctionV2.serviceAccountEmail: fabric's
local.service_account_email: the created account's email, else
service_account_config.email, else "". */}}
{{- define "cloudFunctionV2.serviceAccountEmail" -}}
{{- $c := .Values.service_account_config | default dict -}}
{{- if ne (toString $c.create) "false" -}}
{{- printf "%s@%s.iam.gserviceaccount.com" (include "cloudFunctionV2.serviceAccount" .) .Values.project_id -}}
{{- else -}}
{{- $c.email | default "" -}}
{{- end -}}
{{- end -}}

{{/* cloudFunctionV2.triggerCreate: "true" when the chart creates the
trigger's service account. */}}
{{- define "cloudFunctionV2.triggerCreate" -}}
{{- with .Values.trigger_config }}{{ if .service_account_create }}true{{ end }}{{ end -}}
{{- end -}}

{{/* cloudFunctionV2.triggerServiceAccountEmail: fabric's
local.trigger_sa_email: the created account's email, else
trigger_config.service_account_email, else "". */}}
{{- define "cloudFunctionV2.triggerServiceAccountEmail" -}}
{{- if include "cloudFunctionV2.triggerCreate" . -}}
{{- printf "%s@%s.iam.gserviceaccount.com" (include "cloudFunctionV2.triggerServiceAccount" .) .Values.project_id -}}
{{- else -}}
{{- with .Values.trigger_config }}{{ .service_account_email | default "" }}{{ end -}}
{{- end -}}
{{- end -}}

{{/* cloudFunctionV2.cloudLabels: the unprefixed labels of the chart's tags
and labels, as JSON: the cloud labels of a kind that takes them in
spec.labels. */}}
{{- define "cloudFunctionV2.cloudLabels" -}}
{{- $cloud := dict -}}
{{- range $k, $l := (include "kcc.labels" (list . dict) | fromJson) -}}
{{- if not (contains "/" $k) }}{{ $_ := set $cloud $k $l }}{{ end -}}
{{- end -}}
{{- toJson $cloud -}}
{{- end -}}
