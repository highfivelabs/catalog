{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
This chart's own helpers.
*/ -}}

{{/*
storage.anySet: "true" when a value holds a non-empty leaf anywhere (a
string, a number, a boolean true, or a non-empty list), else "".
resource_types defaults to an object of API versions in the module; an
empty map is not a setting.
*/}}
{{- define "storage.anySet" -}}
{{- if kindIs "map" . -}}
{{- range $_, $v := . -}}{{- include "storage.anySet" $v -}}{{- end -}}
{{- else if kindIs "slice" . -}}
{{- if gt (len .) 0 -}}true{{- end -}}
{{- else if not (empty .) -}}true
{{- end -}}
{{- end -}}

{{/*
storage.accountName: the account's Azure name: names.storageAccount, else
name with the namePrefix in front, its hyphens removed.
*/}}
{{- define "storage.accountName" -}}
{{- include "aso.resourceName" (list . "storageAccount" "storage account" .Values.name 24 "^[a-z0-9]{3,24}$" "compact") -}}
{{- end -}}

{{/*
storage.accountID: the account's ARM ID, from parent_id and its name: the
owner of the containers, queues, tables and shares (by their service,
default) and of the services' diagnostic settings.
*/}}
{{- define "storage.accountID" -}}
{{- printf "%s/providers/Microsoft.Storage/storageAccounts/%s" .Values.parent_id (include "storage.accountName" .) -}}
{{- end -}}
