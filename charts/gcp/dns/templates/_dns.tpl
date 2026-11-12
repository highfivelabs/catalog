{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* dns.zoneName: the zone name: names.zone in full when set; else name,
as fabric names it, with the namePrefix in front (at most 63 characters,
starting with a letter). With zone_config null it names the existing zone
the same way. */}}
{{- define "dns.zoneName" -}}
{{- include "kcc.resourceName" (list . "zone" "zone" .Values.name 63 "letter") -}}
{{- end -}}

{{/* dns.zoneRef: the zone as a Config Connector reference: the rendered
DNSManagedZone, or the existing one by its name. */}}
{{- define "dns.zoneRef" -}}
{{- if .Values.zone_config -}}
name: {{ .Release.Name }}
{{- else -}}
external: {{ include "dns.zoneName" . | quote }}
{{- end -}}
{{- end -}}
