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

{{/*
storage.optional: YAML lines for the pairs (a list: key, value, key,
value ...) whose value is set, as the module merges in only non-null
properties; numbers as integers. "" when none is set.
*/}}
{{- define "storage.optional" -}}
{{- $l := . -}}
{{- $lines := list -}}
{{- range $i := until (div (len $l) 2 | int) -}}
{{- $val := index $l (add1 (mul $i 2)) -}}
{{- if not (kindIs "invalid" $val) -}}
{{- if kindIs "float64" $val }}{{ $val = int64 $val }}{{ end -}}
{{- $lines = append $lines (printf "%s: %v" (index $l (mul $i 2)) $val) -}}
{{- end -}}
{{- end -}}
{{- join "\n" $lines -}}
{{- end -}}

{{/*
storage.block: "<name>:" with the set pairs under it (storage.optional),
or "<name>: {}" when none is set, as the module sends an empty object.
*/}}
{{- define "storage.block" -}}
{{- $o := include "storage.optional" (index . 1) -}}
{{- if $o -}}
{{ index . 0 }}:
{{ $o | indent 2 }}
{{- else -}}
{{ index . 0 }}: {}
{{- end -}}
{{- end -}}

{{/*
storage.cors: a service's cors block from the module's cors_rules ("" when
null; an empty list sends no rules).
*/}}
{{- define "storage.cors" -}}
{{- if not (kindIs "invalid" .) -}}
cors:
  corsRules:
    {{- range . }}
    - allowedHeaders: {{ toJson .allowed_headers }}
      allowedMethods: {{ toJson .allowed_methods }}
      allowedOrigins: {{ toJson .allowed_origins }}
      exposedHeaders: {{ toJson .exposed_headers }}
      maxAgeInSeconds: {{ .max_age_in_seconds | int }}
    {{- else }} []
    {{- end }}
{{- end -}}
{{- end -}}
