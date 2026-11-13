{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
This chart's own helpers.
*/ -}}

{{/*
alz.uuidv5: Terraform's uuidv5("url", .), RFC 4122 version 5 in the URL
namespace (6ba7b811-9dad-11d1-80b4-00c04fd430c8, here its 16 bytes in
base64): the SHA-1 of the namespace's bytes and the name, its version
nibble set to 5 and its variant bits to 10. The module keys policy role
assignments and names role assignments with it.
*/}}
{{- define "alz.uuidv5" -}}
{{- $h := sha1sum (printf "%s%s" (b64dec "a6e4EZ2tEdGAtADAT9QwyA==") .) -}}
{{- $variant := dict "0" "8" "1" "9" "2" "a" "3" "b" "4" "8" "5" "9" "6" "a" "7" "b" "8" "8" "9" "9" "a" "a" "b" "b" "c" "8" "d" "9" "e" "a" "f" "b" -}}
{{- printf "%s-%s-5%s-%s%s-%s" (substr 0 8 $h) (substr 8 12 $h) (substr 13 16 $h) (get $variant (substr 16 17 $h)) (substr 17 20 $h) (substr 20 32 $h) -}}
{{- end -}}

{{/*
alz.anySet: "true" when a value holds a non-empty leaf anywhere, else "".
*/}}
{{- define "alz.anySet" -}}
{{- if kindIs "map" . -}}
{{- range $_, $v := . -}}{{- include "alz.anySet" $v -}}{{- end -}}
{{- else if kindIs "slice" . -}}
{{- if gt (len .) 0 -}}true{{- end -}}
{{- else if not (empty .) -}}true
{{- end -}}
{{- end -}}

{{/*
alz.doc: one of the architecture's resources (a policy definition, set
definition, assignment or role definition) as JSON: the data source gives
each as a JSON string (the module jsondecodes it); an object is taken as
it is.
*/}}
{{- define "alz.doc" -}}
{{- if kindIs "string" . -}}{{- . -}}{{- else -}}{{- toJson . -}}{{- end -}}
{{- end -}}

{{/*
alz.mgOwner: the owner of something at management group <id> as YAML: the
chart's ManagementGroup by name when the chart makes it (aso-extensions
kinds only: ASO cannot resolve an aso-extensions kind), else its ID.
Arguments (a list): $, made (a dict of the management groups the chart
makes: id -> object name), id, byName (true for an aso-extensions kind).
*/}}
{{- define "alz.mgOwner" -}}
{{- $made := index . 1 -}}{{- $id := index . 2 -}}{{- $byName := index . 3 -}}
{{- if and $byName (hasKey $made $id) -}}
group: management.azure.hfl.dev
kind: ManagementGroup
name: {{ index $made $id }}
{{- else -}}
armId: {{ printf "/providers/Microsoft.Management/managementGroups/%s" $id | quote }}
{{- end -}}
{{- end -}}

{{/*
alz.parameters: a policy definition's or set definition's parameters as
JSON, in the aso-extensions shape: a parameter's metadata keeps
assignPermissions, description, displayName and strongType, and every
other metadata key (deprecated, portalReview ...) moves to
metadata.additionalProperties, where the ARM type keeps the rest.
*/}}
{{- define "alz.parameters" -}}
{{- $out := dict -}}
{{- range $k, $p := (. | default dict) -}}
{{- $q := omit $p "metadata" -}}
{{- with $p.metadata -}}
{{- $m := pick . "assignPermissions" "description" "displayName" "strongType" -}}
{{- $extra := omit . "assignPermissions" "description" "displayName" "strongType" -}}
{{- if $extra }}{{ $_ := set $m "additionalProperties" $extra }}{{ end -}}
{{- $_ := set $q "metadata" $m -}}
{{- end -}}
{{- $_ := set $out $k $q -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}
