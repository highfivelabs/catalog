{{/*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Ported from terraform-google-kubernetes-engine modules/beta-private-cluster
main.tf and sa.tf (v47.0.0), Copyright 2022 Google LLC, Apache-2.0.

Helpers of the gke-cluster chart. Names start with "gke." so they never
clash with lib/_kcc.tpl's.
*/}}

{{/*
gke.bool: "true" or "false" from a value that may be a boolean, a string
("true", as Terraform's map(any) node pools carry them) or null, which
takes the default.
  {{ include "gke.bool" (list $pool.autoscaling true) }}
*/}}
{{- define "gke.bool" -}}
{{- $v := index . 0 -}}{{- $d := index . 1 -}}
{{- if kindIs "invalid" $v -}}{{- $v = $d -}}{{- end -}}
{{- if kindIs "string" $v -}}{{- eq (lower $v) "true" -}}{{- else -}}{{- ternary "true" "false" (eq (toString $v) "true") -}}{{- end -}}
{{- end -}}

{{/*
gke.autopilot: "true" when mode is autopilot, else "".
*/}}
{{- define "gke.autopilot" -}}
{{- if eq .Values.mode "autopilot" -}}true{{- end -}}
{{- end -}}

{{/*
gke.clusterName: the cluster's cloud name: names.cluster in full, else the
module's name (with the optional namePrefix). GKE allows 40 characters,
starting with a letter.
*/}}
{{- define "gke.clusterName" -}}
{{- include "kcc.resourceName" (list . "cluster" "cluster" .Values.name 40 "letter") -}}
{{- end -}}

{{/*
gke.location: the module's local.location: the region for a regional
cluster, else the first zone.
*/}}
{{- define "gke.location" -}}
{{- if .Values.regional -}}
{{- required "gke-cluster: region is required for a regional cluster (regional: true)" .Values.region -}}
{{- else -}}
{{- if not .Values.zones -}}{{- fail "gke-cluster: zones is required for a zonal cluster (regional: false): the first zone is the cluster's location" -}}{{- end -}}
{{- first .Values.zones -}}
{{- end -}}
{{- end -}}

{{/*
gke.region: the module's local.region: the region, or the first zone's.
*/}}
{{- define "gke.region" -}}
{{- if .Values.regional -}}{{- .Values.region -}}{{- else -}}{{- splitList "-" (first .Values.zones) | initial | join "-" -}}{{- end -}}
{{- end -}}

{{/*
gke.networkProject: the module's local.network_project_id: the Shared VPC
host project, else the cluster's project.
*/}}
{{- define "gke.networkProject" -}}
{{- default .Values.project_id .Values.network_project_id -}}
{{- end -}}

{{/*
gke.networkTag: the module's local.cluster_network_tag, gke-<cluster name>.
*/}}
{{- define "gke.networkTag" -}}
gke-{{ include "gke.clusterName" . }}
{{- end -}}

{{/*
gke.createSA: "true" when the chart creates the node service account
(create_service_account).
gke.useCreatedSA: "true" when the nodes run as it: the module's
local.service_account, which is var.service_account when one is given,
even if an account is also created.
*/}}
{{- define "gke.createSA" -}}
{{- if .Values.create_service_account -}}true{{- end -}}
{{- end -}}
{{- define "gke.useCreatedSA" -}}
{{- if and .Values.create_service_account (has (toString .Values.service_account) (list "" "create")) -}}true{{- end -}}
{{- end -}}

{{/*
gke.saObject: the Kubernetes name of the IAMServiceAccount the chart makes.
*/}}
{{- define "gke.saObject" -}}
{{- include "kcc.name" (list .Release.Name "nodes") -}}
{{- end -}}

{{/*
gke.saId: the node service account's ID: names.serviceAccount in full,
else service_account_name, else the module's default,
tf-gke-<first 15 characters of name>-<4 characters>. The module's 4
characters are random (random_string); here they are the first 4 hex
characters of the sha256 of "<project_id>/<name>", so a render never
changes. To adopt an account Terraform made, set service_account_name (or
names.serviceAccount) to its ID (README.md, "From Terraform").
*/}}
{{- define "gke.saId" -}}
{{- $derived := .Values.service_account_name -}}
{{- if not $derived -}}
{{- $derived = printf "tf-gke-%s-%s" (trunc 15 .Values.name) (sha256sum (printf "%s/%s" .Values.project_id .Values.name) | trunc 4) -}}
{{- end -}}
{{- $id := include "kcc.resourceName" (list . "serviceAccount" "service account ID" $derived 30 "letter") -}}
{{- if not (regexMatch "^[a-z](?:[-a-z0-9]{4,28}[a-z0-9])$" $id) -}}
{{- fail (printf "gke-cluster: the node service account ID %q must be 6 to 30 lower-case letters, digits or hyphens, start with a letter and not end with a hyphen" $id) -}}
{{- end -}}
{{- $id -}}
{{- end -}}

{{/*
gke.saRef: the serviceAccountRef nodes run as, as JSON ({} for GKE's
default, the Compute Engine default account). An override (a node pool's
service_account) is the second item, "" for none.
*/}}
{{- define "gke.saRef" -}}
{{- $root := index . 0 -}}{{- $override := index . 1 -}}
{{- if $override -}}
{{- toJson (dict "external" $override) -}}
{{- else if include "gke.useCreatedSA" $root -}}
{{- toJson (dict "name" (include "gke.saObject" $root)) -}}
{{- else if $root.Values.service_account -}}
{{- toJson (dict "external" $root.Values.service_account) -}}
{{- else -}}
{}
{{- end -}}
{{- end -}}

{{/*
gke.defaultAutoUpgrade: the module's local.default_auto_upgrade: node
auto-upgrade is on for a regional cluster, or whenever a release channel
other than UNSPECIFIED is set (GKE requires it then).
*/}}
{{- define "gke.defaultAutoUpgrade" -}}
{{- if or .Values.regional (ne (toString .Values.release_channel) "UNSPECIFIED") -}}true{{- else -}}false{{- end -}}
{{- end -}}

{{/*
gke.nodeMetadata: the workload metadata mode for a node metadata value,
with the module's legacy mappings; "" for UNSPECIFIED.
*/}}
{{- define "gke.nodeMetadata" -}}
{{- $m := toString . -}}
{{- $legacy := dict "GKE_METADATA_SERVER" "GKE_METADATA" "EXPOSE" "GCE_METADATA" -}}
{{- if ne $m "UNSPECIFIED" -}}{{- get $legacy $m | default $m -}}{{- end -}}
{{- end -}}

{{/*
gke.poolMap: one of the module's per-pool maps (node_pools_labels, ...)
for a pool: its "all" entry merged with the pool's own. Maps of maps merge
their entries (JSON); maps of lists concatenate them (JSON); maps of
strings take the pool's own when it is set, else "all" (the string).
  {{ include "gke.poolMap" (list $ "node_pools_labels" $name "map") }}
*/}}
{{- define "gke.poolMap" -}}
{{- $root := index . 0 -}}{{- $var := index . 1 -}}{{- $name := index . 2 -}}{{- $shape := index . 3 -}}
{{- $m := index $root.Values $var | default dict -}}
{{- if not (kindIs "map" $m) -}}{{- $m = dict -}}{{- end -}}
{{- $all := index $m "all" -}}{{- $own := index $m $name -}}
{{- if eq $shape "map" -}}
{{- $out := dict -}}
{{- range $k, $x := merge (deepCopy ($own | default dict)) ($all | default dict) }}{{ $_ := set $out $k (toString $x) }}{{ end -}}
{{- toJson $out -}}
{{- else if eq $shape "list" -}}
{{- toJson (concat ($all | default list) ($own | default list)) -}}
{{- else -}}
{{- default "" (coalesce $own $all) -}}
{{- end -}}
{{- end -}}

{{/*
gke.int: an integer from a number or a numeric string; null (or a missing
key) takes the default. Unlike Sprig's default, 0 is kept: min_count: 0 is
a pool that scales to zero.
  {{ include "gke.int" (list $pool.min_count 1) }}
*/}}
{{- define "gke.int" -}}
{{- $v := index . 0 -}}
{{- if or (kindIs "invalid" $v) (eq (toString $v) "") -}}{{- index . 1 | int -}}{{- else -}}{{- int $v -}}{{- end -}}
{{- end -}}

{{/*
gke.setBeyond: "true" when an object variable sets anything beyond its
module default: a key whose value is neither null nor the default's, or a
key the default does not have. For variables the chart refuses whole,
whose defaults are "off" (ray_operator_config, rbac_binding_config).
  {{ include "gke.setBeyond" (list .Values.ray_operator_config (dict "enabled" false)) }}
*/}}
{{- define "gke.setBeyond" -}}
{{- $m := index . 0 | default dict -}}{{- $d := index . 1 -}}
{{- range $k, $x := $m -}}
{{- if and (not (kindIs "invalid" $x)) (ne (toJson $x) (toJson (get $d $k))) -}}true{{- end -}}
{{- end -}}
{{- end -}}
