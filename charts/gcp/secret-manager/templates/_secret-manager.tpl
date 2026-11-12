{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* secretManager.id: a secret's cloud ID: names.<key> in full when set;
else the key, as fabric names it (secret_id = each.key), with the
namePrefix in front (at most 255 characters). (list $ <key>) */}}
{{- define "secretManager.id" -}}
{{- $root := index . 0 -}}{{- $key := index . 1 -}}
{{- include "kcc.resourceName" (list $root $key "secret" $key 255) -}}
{{- end -}}

{{/* secretManager.object: a secret's Kubernetes name. (list $ <key>) */}}
{{- define "secretManager.object" -}}
{{- include "kcc.name" (list (index . 0).Release.Name (index . 1)) -}}
{{- end -}}
