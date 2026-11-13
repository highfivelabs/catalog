{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Helpers of this chart, ported from cloud-foundation-fabric
modules/compute-mig (v60.0.0), Copyright 2022 Google LLC, Apache-2.0.
*/ -}}

{{- /* computeMig.regional: "true" when location is a region. fabric's
local.is_regional: a location ending in -<letter> (europe-west1-b) or
-ai<digit><letter> (europe-west2-ai2c) is a zone, anything else a region. */ -}}
{{- define "computeMig.regional" -}}
{{- if not (regexMatch "-[a-zA-Z]$|-ai[0-9][a-zA-Z]$" (toString .Values.location)) -}}true{{- end -}}
{{- end -}}

{{- /* computeMig.groupName: the group's cloud name (and its instances'
base name): names.group, else name with the namePrefix. */ -}}
{{- define "computeMig.groupName" -}}
{{- include "kcc.resourceName" (list . "group" "managed instance group" .Values.name 63 "letter") -}}
{{- end -}}

{{- /* computeMig.scaleIn: an autoscalingPolicy.scaleInControl from one of
fabric's scaling_control entries ({max_replicas_fixed,
max_replicas_percent, time_window_sec}), as JSON. */ -}}
{{- define "computeMig.scaleIn" -}}
{{- $out := dict -}}
{{- if not (kindIs "invalid" .time_window_sec) }}{{ $_ := set $out "timeWindowSec" (int64 .time_window_sec) }}{{ end -}}
{{- if or (not (kindIs "invalid" .max_replicas_fixed)) (not (kindIs "invalid" .max_replicas_percent)) -}}
{{- $m := dict -}}
{{- if not (kindIs "invalid" .max_replicas_fixed) }}{{ $_ := set $m "fixed" (int64 .max_replicas_fixed) }}{{ end -}}
{{- if not (kindIs "invalid" .max_replicas_percent) }}{{ $_ := set $m "percent" (int64 .max_replicas_percent) }}{{ end -}}
{{- $_ := set $out "maxScaledInReplicas" $m -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}
