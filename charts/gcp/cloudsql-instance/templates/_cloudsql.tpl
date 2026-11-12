{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

Helpers of the cloudsql-instance chart.
*/ -}}

{{- /* cloudsql.prefix: fabric's local.prefix, "<prefix>-" or "". */ -}}
{{- define "cloudsql.prefix" -}}
{{- with .Values.prefix }}{{ printf "%s-" . }}{{ end -}}
{{- end -}}

{{- /* cloudsql.instanceName: names.instance in full when set; else
"<prefix>-<name>", as fabric names the primary, with the namePrefix in
front. Cloud SQL takes lower-case letters, digits and hyphens, starting
with a letter, and at most 98 characters with the project ID; the chart
checks the name alone against 98 and the cloud checks the rest. */ -}}
{{- define "cloudsql.instanceName" -}}
{{- include "kcc.resourceName" (list . "instance" "instance" (printf "%s%s" (include "cloudsql.prefix" .) .Values.name) 98 "letter") -}}
{{- end -}}

{{- /* cloudsql.replicaName: a read replica's name, "<prefix>-<key>", as
fabric names it, with the namePrefix in front. (list $ <key>) */ -}}
{{- define "cloudsql.replicaName" -}}
{{- $root := index . 0 -}}
{{- include "kcc.cloudName" (list $root "instance" (printf "%s%s" (include "cloudsql.prefix" $root) (index . 1)) 98 "letter") -}}
{{- end -}}

{{- /* cloudsql.ipConfiguration: settings.ipConfiguration, the same on the
primary and its replicas but for the allocated range (primary or
replica) and, on the primary only, the PSC write endpoint (refused).
(list $ "primary"|"replica") */ -}}
{{- define "cloudsql.ipConfiguration" -}}
{{- $v := (index . 0).Values -}}
{{- $role := index . 1 -}}
{{- $nc := $v.network_config -}}
{{- $c := $nc.connectivity | default dict -}}
ipv4Enabled: {{ $c.public_ipv4 | default false }}
{{- with $c.psa_config }}
privateNetworkRef:
  external: {{ .private_network | quote }}
{{- with .allocated_ip_ranges }}
{{- with index . $role }}
allocatedIpRange: {{ . | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- with $v.ssl.mode }}
sslMode: {{ . }}
{{- end }}
enablePrivatePathForGoogleCloudServices: {{ $c.enable_private_path_for_services | default false }}
{{- with $nc.authorized_networks }}
authorizedNetworks:
{{- range $name := keys . | sortAlpha }}
  - name: {{ $name | quote }}
    value: {{ index $nc.authorized_networks $name | quote }}
{{- end }}
{{- end }}
{{- with $c.psc_config }}
pscConfig:
  - pscEnabled: true
    {{- with .allowed_consumer_projects }}
    allowedConsumerProjects: {{ toJson . }}
    {{- end }}
{{- end }}
{{- end -}}

{{- /* cloudsql.flags: settings.databaseFlags, sorted by name. */ -}}
{{- define "cloudsql.flags" -}}
{{- $flags := .Values.flags -}}
{{- if $flags -}}
databaseFlags:
{{- range $name := keys $flags | sortAlpha }}
  - name: {{ $name | quote }}
    value: {{ index $flags $name | quote }}
{{- end }}
{{- end }}
{{- end -}}
