{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* nodepool.name: the node pool name: names.nodepool in full when set;
else name (or, when it is null, the component's name) with the namePrefix
in front (at most 40 characters, starting with a letter). */}}
{{- define "nodepool.name" -}}
{{- include "kcc.resourceName" (list . "nodepool" "node pool" (.Values.name | default .Release.Name) 40 "letter") -}}
{{- end -}}

{{/* nodepool.saId: the created service account's ID: names.serviceAccount
in full when set; else the local part of service_account.email, or
tf-gke-<name>, as fabric names it, with the namePrefix in front. */}}
{{- define "nodepool.saId" -}}
{{- $sa := .Values.service_account -}}
{{- $derived := ternary (splitList "@" (toString $sa.email) | first) (printf "tf-gke-%s" (.Values.name | default .Release.Name)) (not (empty $sa.email)) -}}
{{- include "kcc.resourceName" (list . "serviceAccount" "service account" $derived 30 "letter") -}}
{{- end -}}

{{/* nodepool.image: {cos, cosContainerd, win} for node_config.image_type,
as fabric's local.image reads it. */}}
{{- define "nodepool.image" -}}
{{- $t := .Values.node_config.image_type -}}
{{- $s := toString ($t | default "-") -}}
{{- toJson (dict "cos" (contains "COS" $s) "cosContainerd" (or (empty $t) (contains "COS_CONTAINERD" $s)) "win" (contains "WIN" $s)) -}}
{{- end -}}
