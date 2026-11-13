{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
This chart's own helpers.
*/ -}}

{{/*
cog.uuidv5: Terraform's uuidv5("url", .), RFC 4122 version 5 in the URL
namespace (6ba7b811-9dad-11d1-80b4-00c04fd430c8, here its 16 bytes in
base64): the SHA-1 of the namespace's bytes and the name, its version
nibble set to 5 and its variant bits to 10.
*/}}
{{- define "cog.uuidv5" -}}
{{- $h := sha1sum (printf "%s%s" (b64dec "a6e4EZ2tEdGAtADAT9QwyA==") .) -}}
{{- $variant := dict "0" "8" "1" "9" "2" "a" "3" "b" "4" "8" "5" "9" "6" "a" "7" "b" "8" "8" "9" "9" "a" "a" "b" "b" "c" "8" "d" "9" "e" "a" "f" "b" -}}
{{- printf "%s-%s-5%s-%s%s-%s" (substr 0 8 $h) (substr 8 12 $h) (substr 13 16 $h) (get $variant (substr 16 17 $h)) (substr 17 20 $h) (substr 20 32 $h) -}}
{{- end -}}

{{/*
cog.anySet: "true" when a value holds a non-empty leaf anywhere, else "".
*/}}
{{- define "cog.anySet" -}}
{{- if kindIs "map" . -}}
{{- range $_, $v := . -}}{{- include "cog.anySet" $v -}}{{- end -}}
{{- else if kindIs "slice" . -}}
{{- if gt (len .) 0 -}}true{{- end -}}
{{- else if not (empty .) -}}true
{{- end -}}
{{- end -}}

{{/*
cog.object: the Kubernetes name of the account object.
cog.accountName: the account's Azure name (names.account, else name with
the namePrefix).
cog.accountId: the account's resource ID as the module's azapi resource
has it (parent_id, the provider and the name), which the module's default
names hash.
*/}}
{{- define "cog.object" -}}
{{- include "aso.name" (list .Release.Name "account") -}}
{{- end -}}

{{- define "cog.accountName" -}}
{{- include "aso.resourceName" (list . "account" "cognitive services account" .Values.name 64 "^[a-zA-Z0-9][a-zA-Z0-9-]{1,63}$") -}}
{{- end -}}

{{- define "cog.accountId" -}}
{{- printf "%s/providers/Microsoft.CognitiveServices/accounts/%s" .Values.parent_id (include "cog.accountName" .) -}}
{{- end -}}
