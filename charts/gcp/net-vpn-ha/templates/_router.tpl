{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Helpers for the Cloud Router and its route policies, as fabric's VPN and
interconnect modules (net-vpn-ha, net-vpn-dynamic, net-vlan-attachment,
net-ipsec-over-interconnect, v60.0.0) write them: the same in each of
those charts.
*/ -}}

{{/*
router.bgp: a ComputeRouter's bgp from fabric's router_config (asn,
custom_advertise, keepalive). A CUSTOM advertise mode when
custom_advertise is set, as fabric's.
*/}}
{{- define "router.bgp" -}}
{{- $rc := . -}}
asn: {{ int64 $rc.asn }}
advertiseMode: {{ ternary "CUSTOM" "DEFAULT" (not (empty $rc.custom_advertise)) }}
{{- with $rc.custom_advertise }}
{{- if .all_subnets }}
advertisedGroups: [ALL_SUBNETS]
{{- end }}
{{- with .ip_ranges }}
advertisedIpRanges:
  {{- range $range, $desc := . }}
  - range: {{ $range | quote }}
    description: {{ $desc | quote }}
  {{- end }}
{{- end }}
{{- end }}
{{- if not (kindIs "invalid" $rc.keepalive) }}
keepaliveInterval: {{ int64 $rc.keepalive }}
{{- end }}
{{- end -}}

{{/*
router.expr: a route policy term's match or action ({expression, title,
description, location}).
*/}}
{{- define "router.expr" -}}
expression: {{ .expression | quote }}
{{- with .title }}
title: {{ . | quote }}
{{- end }}
{{- with .description }}
description: {{ . | quote }}
{{- end }}
{{- with .location }}
location: {{ . | quote }}
{{- end }}
{{- end -}}

{{/*
router.policies: one config-connector-extensions ComputeRouterRoutePolicy
(v1alpha1, so behind allow_alpha) per entry of router_config.route_policies,
named by its key, on the router the chart makes or the one router_config
names. Checks fabric's validation that a policy's term priorities are
unique (the schema checks the type and the priority's range).
  root      $
  policies  router_config.route_policies
  router    {name: <ComputeRouter object>} or {external: projects/.../routers/<name>}
  abandon   kcc.abandon's result
*/}}
{{- define "router.policies" -}}
{{- $root := .root -}}{{- $v := $root.Values -}}
{{- include "kcc.alpha" (list $root "router_config.route_policies" .policies "ComputeRouterRoutePolicy (config-connector-extensions)") -}}
{{- range $k, $p := .policies }}
{{- $seen := dict }}
{{- range $t := $p.terms }}
{{- if hasKey $seen (toString $t.priority) }}
{{- fail (printf "%s: Route policy term priority must be unique within the policy." $root.Chart.Name) }}
{{- end }}
{{- $_ := set $seen (toString $t.priority) true }}
{{- end }}
{{- end }}
{{- $router := .router }}
{{- $abandon := .abandon }}
{{- range $key, $p := .policies }}
---
apiVersion: compute.gcp.hfl.dev/v1alpha1
kind: ComputeRouterRoutePolicy
metadata:
  {{- include "kcc.metadata" (dict "root" $root "name" (include "kcc.name" (list $root.Release.Name "route-policy" $key)) "id" (printf "route_policy:%s" $key) "project" $v.project_id "abandon" $abandon) | nindent 2 }}
spec:
  resourceID: {{ include "kcc.cloudName" (list $root "route policy" $key 63 "letter") | quote }}
  projectRef:
    external: {{ $v.project_id | quote }}
  region: {{ $v.region | quote }}
  routerRef:
    {{- toYaml $router | nindent 4 }}
  type: {{ printf "ROUTE_POLICY_TYPE_%s" $p.type }}
  terms:
    {{- range $t := $p.terms }}
    - priority: {{ int64 $t.priority }}
      match:
        {{- include "router.expr" $t.match | nindent 8 }}
      {{- with $t.actions }}
      actions:
        {{- range $a := . }}
        - {{ include "router.expr" $a | nindent 10 | trim }}
        {{- end }}
      {{- end }}
    {{- end }}
{{- end }}
{{- end -}}
