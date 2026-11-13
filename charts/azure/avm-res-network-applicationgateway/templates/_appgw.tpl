{{/*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Ported from terraform-azurerm-avm-res-network-applicationgateway
locals.child_reference_inputs.tf and locals.child_reference_resolution.tf
(v0.6.0), Copyright (c) Microsoft Corporation, MIT.

This chart's own helpers (names start with "appgw.").
*/}}

{{/*
appgw.pick: the fields of one module object that are set (not null), under
their ARM names, as JSON. Arguments (a list): the object, then a list of
"module_name:armName" pairs.
*/}}
{{- define "appgw.pick" -}}
{{- $o := index . 0 | default dict -}}
{{- $out := dict -}}
{{- range $pair := index . 1 -}}
{{- $p := splitList ":" $pair -}}
{{- $val := index $o (index $p 0) -}}
{{- if not (kindIs "invalid" $val) -}}
{{- $_ := set $out (index $p 1) $val -}}
{{- end -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/*
appgw.ref: one internal child reference of the module, resolved as the
module resolves it, as JSON ({"reference": {"armId": ...}}), or "" when the
reference is not set. A reference gives either id (any ARM ID, sent as it
is) or its type's key, which must case-insensitively match the configured
name of exactly one component of the target collection; it becomes the
gateway's ARM ID, the collection's ARM segment and that component's name.
Arguments (a dict):
  chart    the chart's name, for messages
  gw       the gateway's ARM ID
  items    the target collection (a list, or null)
  segment  its ARM segment (backendAddressPools, ...)
  key      the key attribute (backend_address_pool_key, ...)
  ref      the reference object
  path     where it is, for messages
*/}}
{{- define "appgw.ref" -}}
{{- $r := .ref -}}
{{- if and (not (kindIs "invalid" $r)) (kindIs "map" $r) -}}
{{- $key := index $r .key -}}
{{- $id := $r.id -}}
{{- if and (not (kindIs "invalid" $id)) (not (kindIs "invalid" $key)) -}}
{{- fail (printf "%s: Internal child references must use either id or their nested *_key, not both. Invalid references: %s" .chart .path) -}}
{{- else if not (kindIs "invalid" $key) -}}
{{- if or (eq (trim (toString $key)) "") (contains "/" (toString $key)) -}}
{{- fail (printf "%s: Internal child reference keys, including parent URL path map keys, must be nonblank single component names without '/'. Invalid references: %s" .chart .path) -}}
{{- end -}}
{{- $found := list -}}
{{- range $item := (.items | default list) -}}
{{- if and $item (not (kindIs "invalid" $item.name)) (eq (lower (toString $item.name)) (lower (toString $key))) -}}
{{- $found = append $found $item.name -}}
{{- end -}}
{{- end -}}
{{- if ne (len $found) 1 -}}
{{- fail (printf "%s: Each internal reference key must case-insensitively match exactly one corresponding component's configured name. Missing or ambiguous references: %s" .chart .path) -}}
{{- end -}}
{{- toJson (dict "reference" (dict "armId" (printf "%s/%s/%s" .gw .segment (first $found)))) -}}
{{- else if not (kindIs "invalid" $id) -}}
{{- toJson (dict "reference" (dict "armId" $id)) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
appgw.pathRuleRef: a redirect configuration's path rule reference: id, or
path_rule_key with url_path_map_key (the path rule's URL path map), as
JSON, or "". Arguments (a dict): chart, gw, maps (url_path_maps), ref, path.
*/}}
{{- define "appgw.pathRuleRef" -}}
{{- $r := .ref -}}
{{- if and (not (kindIs "invalid" $r)) (kindIs "map" $r) -}}
{{- $rk := $r.path_rule_key -}}{{- $mk := $r.url_path_map_key -}}
{{- if and (not (kindIs "invalid" $r.id)) (or (not (kindIs "invalid" $rk)) (not (kindIs "invalid" $mk))) -}}
{{- fail (printf "%s: Redirect path rule references require path_rule_key together with url_path_map_key and cannot combine id with either key. Invalid references: %s" .chart .path) -}}
{{- else if or (not (kindIs "invalid" $rk)) (not (kindIs "invalid" $mk)) -}}
{{- if or (kindIs "invalid" $rk) (kindIs "invalid" $mk) -}}
{{- fail (printf "%s: Redirect path rule references require path_rule_key together with url_path_map_key and cannot combine id with either key. Invalid references: %s" .chart .path) -}}
{{- end -}}
{{- range $k := list $rk $mk -}}
{{- if or (eq (trim (toString $k)) "") (contains "/" (toString $k)) -}}
{{- fail (printf "%s: Internal child reference keys, including parent URL path map keys, must be nonblank single component names without '/'. Invalid references: %s" $.chart $.path) -}}
{{- end -}}
{{- end -}}
{{- $found := list -}}
{{- range $m := (.maps | default list) -}}
{{- if and $m (not (kindIs "invalid" $m.name)) (eq (lower (toString $m.name)) (lower (toString $mk))) -}}
{{- range $pr := ($m.path_rules | default list) -}}
{{- if and $pr (not (kindIs "invalid" $pr.name)) (eq (lower (toString $pr.name)) (lower (toString $rk))) -}}
{{- $found = append $found (printf "urlPathMaps/%s/pathRules/%s" $m.name $pr.name) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if ne (len $found) 1 -}}
{{- fail (printf "%s: Each internal reference key must case-insensitively match exactly one corresponding component's configured name. Path rule keys must identify exactly one URL path map and one path rule within it. Missing or ambiguous references: %s" .chart .path) -}}
{{- end -}}
{{- toJson (dict "reference" (dict "armId" (printf "%s/%s" .gw (first $found)))) -}}
{{- else if not (kindIs "invalid" $r.id) -}}
{{- toJson (dict "reference" (dict "armId" $r.id)) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
appgw.sslPolicy: an SSL policy (the gateway's or a profile's) as JSON; a
Predefined policy sends only its name and type, as the module does.
*/}}
{{- define "appgw.sslPolicy" -}}
{{- $p := . -}}
{{- $out := dict -}}
{{- if ne (toString $p.policy_type) "Predefined" -}}
{{- $out = include "appgw.pick" (list $p (list "cipher_suites:cipherSuites" "disabled_ssl_protocols:disabledSslProtocols" "min_protocol_version:minProtocolVersion")) | fromJson -}}
{{- end -}}
{{- $out = merge $out (include "appgw.pick" (list $p (list "policy_name:policyName" "policy_type:policyType")) | fromJson) -}}
{{- toJson $out -}}
{{- end -}}

{{/*
appgw.subId: {"reference": {"armId": id}} for an ID-only reference object
({id}), or "" when it or its id is null.
*/}}
{{- define "appgw.subId" -}}
{{- if and . (kindIs "map" .) (not (kindIs "invalid" .id)) -}}
{{- toJson (dict "reference" (dict "armId" .id)) -}}
{{- end -}}
{{- end -}}
