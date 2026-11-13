{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Helpers of the net-swp chart.
*/ -}}

{{/*
netswp.gateway, netswp.policy, netswp.tlsPolicy, netswp.serviceAttachment:
the cloud names of the four resources fabric names after name: names.<key>,
else name, with the namePrefix. 63 characters starting with a letter is an
assumption for all four: the APIs document a name as a resource ID
(RFC 1035 label) and Compute's service attachment is one.
*/}}
{{- define "netswp.gateway" -}}
{{- include "kcc.resourceName" (list . "gateway" "gateway" .Values.name 63 "letter") -}}
{{- end -}}
{{- define "netswp.policy" -}}
{{- include "kcc.resourceName" (list . "policy" "gateway security policy" .Values.name 63 "letter") -}}
{{- end -}}
{{- define "netswp.tlsPolicy" -}}
{{- include "kcc.resourceName" (list . "tlsInspectionPolicy" "TLS inspection policy" .Values.name 63 "letter") -}}
{{- end -}}
{{- define "netswp.serviceAttachment" -}}
{{- include "kcc.resourceName" (list . "serviceAttachment" "service attachment" .Values.name 63 "letter") -}}
{{- end -}}

{{/*
netswp.urlLists: fabric's local.url_lists, as JSON: url_lists merged with
factories_data.url_lists (the factory's files win, as merge() has it).
*/}}
{{- define "netswp.urlLists" -}}
{{- $out := dict -}}
{{- range $k, $l := (.Values.url_lists | default dict) -}}
{{- $_ := set $out $k (dict "description" $l.description "values" ($l.values | default list)) -}}
{{- end -}}
{{- range $k, $l := ((.Values.factories_data | default dict).url_lists | default dict) -}}
{{- $_ := set $out $k (dict "description" $l.description "values" ($l.values | default list)) -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/*
netswp.urlListName: a URL list's cloud name, its key with the namePrefix.
(list $ key)
*/}}
{{- define "netswp.urlListName" -}}
{{- include "kcc.cloudName" (list (index . 0) "URL list" (index . 1) 63 "letter") -}}
{{- end -}}

{{/*
netswp.description: coalesce(override, description) as fabric's
coalesce(each.value.description, var.description). (list $ override)
*/}}
{{- define "netswp.description" -}}
{{- $o := index . 1 -}}
{{- if and (not (kindIs "invalid" $o)) (ne (toString $o) "") -}}
{{- $o -}}
{{- else -}}
{{- (index . 0).Values.description | default "" -}}
{{- end -}}
{{- end -}}

{{/*
netswp.format: Terraform's format(matcher, args...) for the %s verbs fabric's
matchers use: each %s takes the next argument, %% is a literal %. Any other
verb, or a count that differs from the arguments', stops the render as
Terraform's format() fails the plan. (list $ what matcher args)
*/}}
{{- define "netswp.format" -}}
{{- $root := index . 0 -}}{{- $what := index . 1 -}}{{- $m := index . 2 -}}{{- $args := index . 3 -}}
{{- $parts := splitList "%%" $m -}}
{{- $out := list -}}
{{- $i := 0 -}}
{{- range $p := $parts -}}
{{- if regexMatch "%[^s]|%$" $p -}}
{{- fail (printf "%s: %s: only %%s and %%%% are supported in a matcher (Terraform's format())" $root.Chart.Name $what) -}}
{{- end -}}
{{- $segs := splitList "%s" $p -}}
{{- $s := index $segs 0 -}}
{{- range $j, $seg := (rest $segs) -}}
{{- if ge $i (len $args) -}}
{{- fail (printf "%s: %s: the matcher has more %%s than matcher_args gives (%d)" $root.Chart.Name $what (len $args)) -}}
{{- end -}}
{{- $s = printf "%s%s%s" $s (index $args $i) $seg -}}
{{- $i = add1 $i -}}
{{- end -}}
{{- $out = append $out $s -}}
{{- end -}}
{{- if lt $i (len $args) -}}
{{- fail (printf "%s: %s: matcher_args gives %d arguments and the matcher has %d %%s" $root.Chart.Name $what (len $args) $i) -}}
{{- end -}}
{{- join "%" $out -}}
{{- end -}}
