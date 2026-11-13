{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Helpers of this chart, ported from cloud-foundation-fabric
modules/net-lb-app-int-cross-region (v60.0.0), Copyright 2026 Google
LLC, Apache-2.0.
*/ -}}

{{- /* netlbaxr.link: a resource link without the Compute API's URL prefix,
as Config Connector's external references take it. */ -}}
{{- define "netlbaxr.link" -}}
{{- trimPrefix "https://www.googleapis.com/compute/beta/" (trimPrefix "https://www.googleapis.com/compute/v1/" (toString .)) -}}
{{- end -}}

{{- /* netlbaxr.project: an entry's project_id, else the chart's. (list $ entry) */ -}}
{{- define "netlbaxr.project" -}}
{{- $e := index . 1 | default dict -}}
{{- $e.project_id | default (index . 0).Values.project_id -}}
{{- end -}}

{{- /* netlbaxr.negName: the cloud name of the network endpoint group of a
key, <name>-<key> with the namePrefix. (list $ key) */ -}}
{{- define "netlbaxr.negName" -}}
{{- include "kcc.cloudName" (list (index . 0) "network endpoint group" (printf "%s-%s" (index . 0).Values.name (index . 1)) 63 "letter") -}}
{{- end -}}

{{- /* netlbaxr.bsName: the cloud name of the backend service of a key:
the entry's name, else <name>-<key>, with the namePrefix. (list $ key) */ -}}
{{- define "netlbaxr.bsName" -}}
{{- $root := index . 0 -}}{{- $k := index . 1 -}}
{{- $b := index ($root.Values.backend_service_configs | default dict) $k -}}
{{- include "kcc.cloudName" (list $root "backend service" ($b.name | default (printf "%s-%s" $root.Values.name $k)) 63 "letter") -}}
{{- end -}}

{{- /* netlbaxr.bsRef: a reference to a backend service: one of the chart's
by key (by Kubernetes name), else an existing one's ID or self link.
(list $ service) */ -}}
{{- define "netlbaxr.bsRef" -}}
{{- $root := index . 0 -}}{{- $s := index . 1 -}}
{{- if hasKey ($root.Values.backend_service_configs | default dict) $s -}}
name: {{ include "kcc.name" (list $root.Release.Name "bs" $s) }}
{{- else -}}
external: {{ include "netlbaxr.link" $s | quote }}
{{- end -}}
{{- end -}}

{{- /* netlbaxr.bsID: a backend service's ID, for fields that take a URL
rather than a reference: projects/<project>/global/backendServices/<name>
for one of the chart's by key, else the value as given. (list $ service) */ -}}
{{- define "netlbaxr.bsID" -}}
{{- $root := index . 0 -}}{{- $s := index . 1 -}}
{{- $bss := $root.Values.backend_service_configs | default dict -}}
{{- if hasKey $bss $s -}}
{{- printf "projects/%s/global/backendServices/%s" (include "netlbaxr.project" (list $root (index $bss $s))) (include "netlbaxr.bsName" (list $root $s)) -}}
{{- else -}}
{{- include "netlbaxr.link" $s -}}
{{- end -}}
{{- end -}}

{{- /* netlbaxr.duration: {seconds, nanos} as Config Connector's duration
(seconds is a string in ComputeURLMap). (list duration secondsAsString) */ -}}
{{- define "netlbaxr.duration" -}}
{{- $d := index . 0 -}}
{{- if index . 1 }}
seconds: {{ $d.seconds | toString | quote }}
{{- else }}
seconds: {{ $d.seconds }}
{{- end }}
{{- if not (kindIs "invalid" $d.nanos) }}
nanos: {{ $d.nanos }}
{{- end }}
{{- end -}}

{{- /* netlbaxr.headerAction: fabric's {request_add, request_remove,
response_add, response_remove} as headerAction. */ -}}
{{- define "netlbaxr.headerAction" -}}
{{- $h := . -}}
{{- with $h.request_add }}
requestHeadersToAdd:
  {{- range $n := keys . | sortAlpha }}
  {{- $a := index $h.request_add $n }}
  - headerName: {{ $n | quote }}
    headerValue: {{ $a.value | quote }}
    replace: {{ ternary true $a.replace (kindIs "invalid" $a.replace) }}
  {{- end }}
{{- end }}
{{- with $h.request_remove }}
requestHeadersToRemove: {{ toJson . }}
{{- end }}
{{- with $h.response_add }}
responseHeadersToAdd:
  {{- range $n := keys . | sortAlpha }}
  {{- $a := index $h.response_add $n }}
  - headerName: {{ $n | quote }}
    headerValue: {{ $a.value | quote }}
    replace: {{ ternary true $a.replace (kindIs "invalid" $a.replace) }}
  {{- end }}
{{- end }}
{{- with $h.response_remove }}
responseHeadersToRemove: {{ toJson . }}
{{- end }}
{{- end -}}

{{- /* netlbaxr.redirect: fabric's {host, https, path, prefix,
response_code, strip_query} as a URL redirect. */ -}}
{{- define "netlbaxr.redirect" -}}
{{- $r := . -}}
{{- range $f := list (list "host" "hostRedirect") (list "https" "httpsRedirect") (list "path" "pathRedirect") (list "prefix" "prefixRedirect") (list "response_code" "redirectResponseCode") (list "strip_query" "stripQuery") }}
{{- $val := index $r (index $f 0) }}
{{- if not (kindIs "invalid" $val) }}
{{ index $f 1 }}: {{ toJson $val }}
{{- end }}
{{- end }}
{{- end -}}

{{- /* netlbaxr.routeAction: fabric's route action as routeAction (or
defaultRouteAction). (list $ action) */ -}}
{{- define "netlbaxr.routeAction" -}}
{{- $root := index . 0 -}}{{- $ra := index . 1 -}}
{{- with $ra.cors_policy }}
corsPolicy:
  {{- range $f := list (list "allow_credentials" "allowCredentials") (list "allow_headers" "allowHeaders") (list "allow_methods" "allowMethods") (list "allow_origin_regexes" "allowOriginRegexes") (list "allow_origins" "allowOrigins") (list "disabled" "disabled") (list "expose_headers" "exposeHeaders") }}
  {{- $val := index $ra.cors_policy (index $f 0) }}
  {{- if not (kindIs "invalid" $val) }}
  {{ index $f 1 }}: {{ toJson $val }}
  {{- end }}
  {{- end }}
  {{- if not (kindIs "invalid" .max_age) }}
  maxAge: {{ int .max_age }}
  {{- end }}
{{- end }}
{{- with $ra.fault_injection_policy }}
faultInjectionPolicy:
  {{- with .abort }}
  abort:
    httpStatus: {{ .status }}
    percentage: {{ .percentage }}
  {{- end }}
  {{- with .delay }}
  delay:
    fixedDelay:
      seconds: {{ .fixed.seconds | toString | quote }}
      nanos: {{ .fixed.nanos }}
    percentage: {{ .percentage }}
  {{- end }}
{{- end }}
{{- with $ra.request_mirror_backend }}
requestMirrorPolicy:
  backendServiceRef:
    {{- include "netlbaxr.bsRef" (list $root .) | trim | nindent 4 }}
{{- end }}
{{- with $ra.retry_policy }}
retryPolicy:
  numRetries: {{ .num_retries }}
  {{- with .retry_conditions }}
  retryConditions: {{ toJson . }}
  {{- end }}
  {{- with .per_try_timeout }}
  perTryTimeout:
    {{- include "netlbaxr.duration" (list . true) | trim | nindent 4 }}
  {{- end }}
{{- end }}
{{- with $ra.timeout }}
timeout:
  {{- include "netlbaxr.duration" (list . true) | trim | nindent 2 }}
{{- end }}
{{- with $ra.url_rewrite }}
urlRewrite:
  {{- with .host }}
  hostRewrite: {{ . | quote }}
  {{- end }}
  {{- with .path_prefix }}
  pathPrefixRewrite: {{ . | quote }}
  {{- end }}
  {{- with .path_template }}
  pathTemplateRewrite: {{ . | quote }}
  {{- end }}
{{- end }}
{{- with $ra.weighted_backend_services }}
weightedBackendServices:
  {{- range $s := keys . | sortAlpha }}
  {{- $w := index $ra.weighted_backend_services $s }}
  - backendServiceRef:
      {{- include "netlbaxr.bsRef" (list $root $s) | trim | nindent 6 }}
    weight: {{ $w.weight }}
    {{- with $w.header_action }}
    headerAction:
      {{- include "netlbaxr.headerAction" . | trim | nindent 6 }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end -}}
