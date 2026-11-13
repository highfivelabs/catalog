{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Helpers of the binauthz chart.
*/ -}}

{{/*
binauthz.attestor: the Kubernetes name of the attestor with key KEY.
  {{ include "binauthz.attestor" (list $ $key) }}
*/}}
{{- define "binauthz.attestor" -}}
{{- include "kcc.name" (list (index . 0).Release.Name "attestor" (index . 1)) -}}
{{- end -}}

{{/*
binauthz.note: the Kubernetes name of the note made for the attestor KEY.
*/}}
{{- define "binauthz.note" -}}
{{- include "kcc.name" (list (index . 0).Release.Name "note" (index . 1)) -}}
{{- end -}}

{{/*
binauthz.requireAttestationsBy: an admission rule's attestors as references
to the attestors this chart makes. fabric indexes
google_binary_authorization_attestor.attestors by the name, so a name that
is not a key of attestors_config fails there too.
  {{ include "binauthz.requireAttestationsBy" (list $ $where $attestors) }}
*/}}
{{- define "binauthz.requireAttestationsBy" -}}
{{- $root := index . 0 -}}{{- $where := index . 1 -}}{{- $attestors := index . 2 | default list -}}
{{- $config := $root.Values.attestors_config | default dict -}}
{{- range $a := $attestors }}
{{- if not (hasKey $config $a) }}
{{- fail (printf "binauthz: %s names the attestor %q, which is not a key of attestors_config" $where $a) }}
{{- end }}
- name: {{ include "binauthz.attestor" (list $root $a) }}
{{- end }}
{{- end -}}
