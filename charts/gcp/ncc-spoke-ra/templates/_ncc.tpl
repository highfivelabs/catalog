{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Helpers for the port of cloud-foundation-fabric modules/ncc-spoke-ra
(v60.0.0).
*/ -}}

{{/*
ncc.expr: a route policy term's match or action ({expression, title,
description, location}).
*/}}
{{- define "ncc.expr" -}}
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
