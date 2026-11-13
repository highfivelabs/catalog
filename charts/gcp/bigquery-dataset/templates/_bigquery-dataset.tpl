{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* bigqueryDataset.name: the dataset's ID: names.dataset in full, else
fabric's id with the namePrefix in front. A dataset ID holds only letters,
digits and "_", so the prefix goes on with its hyphens as underscores:
"<namePrefix>_<id>" ("shop_dev_<id>"). At most 1024 characters. */}}
{{- define "bigqueryDataset.name" -}}
{{- $set := index (.Values.names | default dict) "dataset" -}}
{{- if $set -}}
{{- $set -}}
{{- else -}}
{{- $p := include "kcc.namePrefix" . | trimSuffix "-" -}}
{{- if $p -}}
{{- $name := printf "%s_%s" (replace "-" "_" $p) .Values.id -}}
{{- if gt (len $name) 1024 -}}
{{- fail (printf "%s: dataset ID %q is %d characters, more than the 1024 the cloud allows; namePrefix %q is %d of them (with its \"_\"): shorten the namePrefix or the id" .Chart.Name $name (len $name) $p (add1 (len $p))) -}}
{{- end -}}
{{- $name -}}
{{- else -}}
{{- .Values.id -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* bigqueryDataset.id: the dataset's full name, as fabric's id output:
projects/<project>/datasets/<id>. */}}
{{- define "bigqueryDataset.id" -}}
{{- printf "projects/%s/datasets/%s" .Values.project_id (include "bigqueryDataset.name" .) -}}
{{- end -}}

{{/* bigqueryDataset.identity: the identity of access rule <key>, from
access_identities; fabric's try() fails without one. */}}
{{- define "bigqueryDataset.identity" -}}
{{- $root := index . 0 -}}{{- $key := index . 1 -}}
{{- $ids := $root.Values.access_identities | default dict -}}
{{- if not (hasKey $ids $key) -}}
{{- fail (printf "%s: access.%s has no identity: add access_identities.%s" $root.Chart.Name $key $key) -}}
{{- end -}}
{{- index $ids $key -}}
{{- end -}}

{{/* bigqueryDataset.access: fabric's access locals, as JSON:
  members    {key: {field, role, identity}} for the domain, group,
             special_group and user rules (field is the access entry's:
             domain, groupByEmail, specialGroup, userByEmail)
  views      {"<p>_<d>_<t>": {project_id, dataset_id, table_id}}: the view
             rules (identity "project|dataset|table") and authorized_views
  datasets   {"<p>_<d>": {project_id, dataset_id}}: authorized_datasets
  routines   {"<p>_<d>_<r>": {project_id, dataset_id, routine_id}}:
             authorized_routines */}}
{{- define "bigqueryDataset.access" -}}
{{- $v := .Values -}}
{{- $field := dict "domain" "domain" "group" "groupByEmail" "special_group" "specialGroup" "user" "userByEmail" -}}
{{- $members := dict -}}
{{- $views := dict -}}
{{- range $k, $a := ($v.access | default dict) -}}
{{- $_ := required (printf "%s: access.%s.type is required" $.Chart.Name $k) $a.type -}}
{{- if eq $a.type "view" -}}
{{- $parts := splitList "|" (toString (index ($v.access_identities | default dict) $k | default "")) -}}
{{- if ne (len $parts) 3 -}}
{{- fail (printf "%s: access.%s is a view: access_identities.%s must be \"project_id|dataset_id|table_id\"" $.Chart.Name $k $k) -}}
{{- end -}}
{{- $view := dict "project_id" (index $parts 0) "dataset_id" (index $parts 1) "table_id" (index $parts 2) -}}
{{- $_ := set $views (printf "%s_%s_%s" $view.project_id $view.dataset_id $view.table_id) $view -}}
{{- else -}}
{{- $_ := required (printf "%s: access.%s.role is required" $.Chart.Name $k) $a.role -}}
{{- $_ := set $members $k (dict "field" (get $field $a.type) "role" $a.role "identity" (include "bigqueryDataset.identity" (list $ $k))) -}}
{{- end -}}
{{- end -}}
{{- range $view := ($v.authorized_views | default list) -}}
{{- include "bigqueryDataset.require" (list $ "authorized_views" $view (list "project_id" "dataset_id" "table_id")) -}}
{{- $_ := set $views (printf "%s_%s_%s" $view.project_id $view.dataset_id $view.table_id) $view -}}
{{- end -}}
{{- $datasets := dict -}}
{{- range $d := ($v.authorized_datasets | default list) -}}
{{- include "bigqueryDataset.require" (list $ "authorized_datasets" $d (list "project_id" "dataset_id")) -}}
{{- $_ := set $datasets (printf "%s_%s" $d.project_id $d.dataset_id) $d -}}
{{- end -}}
{{- $routines := dict -}}
{{- range $r := ($v.authorized_routines | default list) -}}
{{- include "bigqueryDataset.require" (list $ "authorized_routines" $r (list "project_id" "dataset_id" "routine_id")) -}}
{{- $_ := set $routines (printf "%s_%s_%s" $r.project_id $r.dataset_id $r.routine_id) $r -}}
{{- end -}}
{{- toJson (dict "members" $members "views" $views "datasets" $datasets "routines" $routines) -}}
{{- end -}}

{{/* bigqueryDataset.partitioning: a table's rangePartitioning or
timePartitioning, as fabric's: range takes partitioning.field, time its
own time.field. */}}
{{- define "bigqueryDataset.partitioning" -}}
{{- with .range }}
rangePartitioning:
  field: {{ $.field | quote }}
  range:
    start: {{ .start }}
    end: {{ .end }}
    interval: {{ .interval }}
{{- end }}
{{- with .time }}
timePartitioning:
  type: {{ .type | quote }}
  {{- if not (kindIs "invalid" .expiration_ms) }}
  expirationMs: {{ int64 .expiration_ms }}
  {{- end }}
  {{- with .field }}
  field: {{ . | quote }}
  {{- end }}
{{- end }}
{{- end -}}

{{/* bigqueryDataset.require: stop the render when an entry of a variable
lacks a field fabric requires. The schema leaves these to the chart, so
that a variable that needs allow_alpha says so first. */}}
{{- define "bigqueryDataset.require" -}}
{{- $root := index . 0 -}}{{- $var := index . 1 -}}{{- $entry := index . 2 -}}
{{- range $f := index . 3 -}}
{{- if not (index $entry $f) -}}
{{- fail (printf "%s: every entry of %s needs %s" $root.Chart.Name $var $f) -}}
{{- end -}}
{{- end -}}
{{- end -}}
