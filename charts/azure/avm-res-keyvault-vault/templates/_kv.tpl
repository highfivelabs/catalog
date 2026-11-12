{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
This chart's own helpers.
*/ -}}

{{/*
kv.anySet: "true" when a value holds a non-empty leaf anywhere (a string,
a number, a boolean true, or a non-empty list), else "".
ignore_body_changes and resource_types default to objects of empty lists
or API versions in the module; an empty map is not a setting.
*/}}
{{- define "kv.anySet" -}}
{{- if kindIs "map" . -}}
{{- range $_, $v := . -}}{{- include "kv.anySet" $v -}}{{- end -}}
{{- else if kindIs "slice" . -}}
{{- if gt (len .) 0 -}}true{{- end -}}
{{- else if not (empty .) -}}true
{{- end -}}
{{- end -}}

{{/*
kv.vaultName: the vault's Azure name, names.keyVault else name with the
namePrefix, checked as the module checks name.
*/}}
{{- define "kv.vaultName" -}}
{{- $n := include "aso.resourceName" (list . "keyVault" "key vault" .Values.name 24 "^[a-zA-Z0-9-]{3,24}$") -}}
{{- if regexMatch "--" $n }}{{ fail "avm-res-keyvault-vault: The name must not contain two consecutive dashes" }}{{ end -}}
{{- if not (regexMatch "^[a-zA-Z]" $n) }}{{ fail "avm-res-keyvault-vault: The name must start with a letter" }}{{ end -}}
{{- if not (regexMatch "[a-zA-Z0-9]$" $n) }}{{ fail "avm-res-keyvault-vault: The name must end with a letter or number" }}{{ end -}}
{{- $n -}}
{{- end -}}
