{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Helpers of the api-gateway chart.
*/ -}}

{{/*
apigw.api: the API's cloud name: names.api, else api_id (fabric's), with
the namePrefix. 63 characters is an assumption: the API documents no limit
for an API ID.
*/}}
{{- define "apigw.api" -}}
{{- include "kcc.resourceName" (list . "api" "API" .Values.api_id 63) -}}
{{- end -}}

{{/*
apigw.gateway: the gateway's cloud name: names.gateway, else gw-<api_id>
(fabric's), with the namePrefix. 63 characters, as for the API.
*/}}
{{- define "apigw.gateway" -}}
{{- include "kcc.resourceName" (list . "gateway" "gateway" (printf "gw-%s" .Values.api_id) 63) -}}
{{- end -}}

{{/*
apigw.serviceAccount: the account ID of the service account the chart
makes: names.serviceAccount, else sa-api-cfg-<api_id> (fabric's), with the
namePrefix; 30 characters, starting with a letter.
*/}}
{{- define "apigw.serviceAccount" -}}
{{- include "kcc.resourceName" (list . "serviceAccount" "service account" (printf "sa-api-cfg-%s" .Values.api_id) 30 "letter") -}}
{{- end -}}

{{/*
apigw.hash: the 32 hex characters that name the API config after its
spec. fabric takes md5(spec); Helm has no md5, so this is the first 32
characters of sha256(spec): a new spec still gets a new config, but the
ID differs from the one Terraform made (README, "From Terraform").
*/}}
{{- define "apigw.hash" -}}
{{- sha256sum .Values.spec | trunc 32 -}}
{{- end -}}

{{/*
apigw.config: the API config's ID, api-cfg-<API name>-<hash> as fabric
names it, under the API.
*/}}
{{- define "apigw.config" -}}
{{- include "kcc.fit" (list . "API config" (printf "api-cfg-%s-%s" (include "apigw.api" .) (include "apigw.hash" .)) 63) -}}
{{- end -}}

{{/*
apigw.configObject: the API config's Kubernetes name. It changes with the
spec, as the config's ID does (resourceID is immutable): a new spec is a
new object, and Bundt prunes the old one once the gateway has moved, as
fabric's create_before_destroy does.
*/}}
{{- define "apigw.configObject" -}}
{{- include "kcc.name" (list .Release.Name "config" (include "apigw.hash" . | trunc 8)) -}}
{{- end -}}

{{/*
apigw.serviceAccountEmail: the service account API configs use: the one
the chart makes with service_account_create, else service_account_email
(fabric's local.service_account_email), or "".
*/}}
{{- define "apigw.serviceAccountEmail" -}}
{{- if .Values.service_account_create -}}
{{- printf "%s@%s.iam.gserviceaccount.com" (include "apigw.serviceAccount" .) .Values.project_id -}}
{{- else -}}
{{- .Values.service_account_email | default "" -}}
{{- end -}}
{{- end -}}
