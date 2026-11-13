{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Helpers of this chart, ported from cloud-foundation-fabric
modules/net-lb-proxy-int-cross-region (v60.0.0), Copyright 2026 Google
LLC, Apache-2.0.
*/ -}}

{{- /* netlbpxr.link: a resource link without the Compute API's URL prefix,
as Config Connector's external references take it. */ -}}
{{- define "netlbpxr.link" -}}
{{- trimPrefix "https://www.googleapis.com/compute/beta/" (trimPrefix "https://www.googleapis.com/compute/v1/" (toString .)) -}}
{{- end -}}

{{- /* netlbpxr.project: an entry's project_id, else the chart's. (list $ entry) */ -}}
{{- define "netlbpxr.project" -}}
{{- $e := index . 1 | default dict -}}
{{- $e.project_id | default (index . 0).Values.project_id -}}
{{- end -}}

{{- /* netlbpxr.negName: the cloud name of the network endpoint group of a
key, <name>-<key> with the namePrefix. (list $ key) */ -}}
{{- define "netlbpxr.negName" -}}
{{- include "kcc.cloudName" (list (index . 0) "network endpoint group" (printf "%s-%s" (index . 0).Values.name (index . 1)) 63 "letter") -}}
{{- end -}}
