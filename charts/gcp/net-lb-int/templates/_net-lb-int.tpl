{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Helpers of this chart, ported from cloud-foundation-fabric
modules/net-lb-int (v60.0.0), Copyright 2026 Google LLC, Apache-2.0.
*/ -}}

{{- /* netlbint.link: a resource link without the Compute API's URL prefix,
as Config Connector's external references take it. */ -}}
{{- define "netlbint.link" -}}
{{- trimPrefix "https://www.googleapis.com/compute/beta/" (trimPrefix "https://www.googleapis.com/compute/v1/" (toString .)) -}}
{{- end -}}

{{- /* netlbint.frName: fabric's local.forwarding_rule_names[key]: name for
the "" key, else <name>-<key>, with the namePrefix. (list $ key) */ -}}
{{- define "netlbint.frName" -}}
{{- $root := index . 0 }}{{ $k := index . 1 -}}
{{- $n := ternary $root.Values.name (printf "%s-%s" $root.Values.name $k) (eq $k "") -}}
{{- include "kcc.cloudName" (list $root "forwarding rule" $n 63 "letter") -}}
{{- end -}}

{{- /* netlbint.k8sName: the Kubernetes name of an object made per key: the
release name for the "" key, else <release>-<part>-<key>. (list $ part key) */ -}}
{{- define "netlbint.k8sName" -}}
{{- $root := index . 0 }}{{ $part := index . 1 }}{{ $k := index . 2 -}}
{{- if eq $k "" -}}{{ include "kcc.name" (list $root.Release.Name $part) }}{{- else -}}{{ include "kcc.name" (list $root.Release.Name $part $k) }}{{- end -}}
{{- end -}}
