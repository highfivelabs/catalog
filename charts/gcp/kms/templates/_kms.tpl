{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* kms.keyringName: the keyring name: names.keyring in full when set;
else keyring.name, as fabric names it, with the namePrefix in front (at
most 63 characters). With keyring_create false it names the existing
keyring the same way. */}}
{{- define "kms.keyringName" -}}
{{- include "kcc.resourceName" (list . "keyring" "keyring" .Values.keyring.name 63) -}}
{{- end -}}

{{/* kms.keyringId: projects/<project>/locations/<location>/keyRings/<name>. */}}
{{- define "kms.keyringId" -}}
{{- printf "projects/%s/locations/%s/keyRings/%s" .Values.project_id .Values.keyring.location (include "kms.keyringName" .) -}}
{{- end -}}

{{/* kms.keyringRef: the keyring as a Config Connector reference: the
rendered KMSKeyRing, or the existing one by its id. */}}
{{- define "kms.keyringRef" -}}
{{- if .Values.keyring_create -}}
name: {{ .Release.Name }}
{{- else -}}
external: {{ include "kms.keyringId" . | quote }}
{{- end -}}
{{- end -}}

{{/* kms.keyObject: a key's Kubernetes name. (list $ <key>) */}}
{{- define "kms.keyObject" -}}
{{- include "kcc.name" (list (index . 0).Release.Name "key" (index . 1)) -}}
{{- end -}}
