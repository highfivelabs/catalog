{{/*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

Shared helpers for the Azure Service Operator (ASO) charts, the Azure
counterpart of lib/_kcc.tpl. The canonical copy is lib/_aso.tpl; every
chart under charts/azure carries an identical copy as templates/_aso.tpl
(hack/sync-lib.sh writes them, hack/test.sh checks them). Names start with
"aso." so they never clash with a chart's own (docs/azure.md, "Charts").
*/}}

{{/*
aso.name: a Kubernetes object name (RFC 1123, at most 63 characters) from
a list of parts joined with "-", as kcc.name: characters other than
lower-case letters, digits and "-" become "-", and when that changed
anything, or the name would pass 63 characters, it keeps at most its first
54 characters and ends with 8 hex characters of the sha256 of the parts.
  {{ include "aso.name" (list .Release.Name "subnet" $key) }}
*/}}
{{- define "aso.name" -}}
{{- $raw := join "-" . -}}
{{- $n := regexReplaceAll "[^a-z0-9-]+" (lower $raw) "-" -}}
{{- $n = regexReplaceAll "-+" $n "-" | trimAll "-" -}}
{{- if or (ne $n $raw) (gt (len $n) 63) -}}
{{- $n = printf "%s-%s" (trunc 54 $n | trimSuffix "-") (sha256sum $raw | trunc 8) -}}
{{- end -}}
{{- $n -}}
{{- end -}}

{{/*
aso.metadata: the metadata of one ASO (or aso-extensions) object.
  root        the chart's root context ($)
  name        the object's Kubernetes name
  id          the object's output id (annotation hfl.dev/id), which a
              Package's outputs read as resources.<id> (docs/design.md, "Outputs")
  labels      further Kubernetes labels for this object only
  abandon     true to keep the Azure resource when the object is deleted
              (ASO's reconcile-policy detach-on-delete)
ASO never copies metadata.labels to Azure: Azure tags are spec.tags
(aso.tags), so the chart's labels value stays in Kubernetes.
*/}}
{{- define "aso.metadata" -}}
name: {{ .name }}
labels:
  app.kubernetes.io/managed-by: {{ .root.Release.Service }}
  app.kubernetes.io/instance: {{ .root.Release.Name | quote }}
  app.kubernetes.io/name: {{ .root.Chart.Name }}
  app.kubernetes.io/version: {{ .root.Chart.Version | quote }}
{{- range $k, $v := (include "aso.labels" (list .root (.labels | default dict)) | fromJson) }}
  {{ $k }}: {{ $v | quote }}
{{- end }}
annotations:
  hfl.dev/id: {{ .id | quote }}
{{- if .abandon }}
  serviceoperator.azure.com/reconcile-policy: detach-on-delete
{{- end }}
{{- end -}}

{{/*
aso.labels: the chart's labels value and an object's own labels, as JSON.
Each must be a valid Kubernetes label; one of the chart's app.kubernetes.io
keys, or a key set twice with different values, stops the render.
*/}}
{{- define "aso.labels" -}}
{{- $root := index . 0 -}}{{- $own := index . 1 -}}
{{- $chart := $root.Chart.Name -}}
{{- $out := dict -}}
{{- $k8sKey := "^([a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*/)?[A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?$" -}}
{{- $k8sValue := "^([A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?)?$" -}}
{{- $standard := list "app.kubernetes.io/managed-by" "app.kubernetes.io/instance" "app.kubernetes.io/name" "app.kubernetes.io/version" -}}
{{- $sources := list (list "labels" ($root.Values.labels | default dict)) (list "labels of this object" $own) -}}
{{- range $s := $sources -}}
{{- $from := index $s 0 -}}
{{- range $k, $raw := (index $s 1) -}}
{{- $v := toString $raw -}}
{{- if kindIs "invalid" $raw }}{{ $v = "" }}{{ end -}}
{{- if has $k $standard -}}
{{- fail (printf "%s: %s %s: the chart sets this label itself" $chart $from $k) -}}
{{- end -}}
{{- if not (and (regexMatch $k8sKey $k) (regexMatch $k8sValue $v) (le (len (splitList "/" $k | first)) 253)) -}}
{{- fail (printf "%s: %s %s=%q is not a valid Kubernetes label (Azure tags go in tags)" $chart $from $k $v) -}}
{{- end -}}
{{- if and (hasKey $out $k) (ne (get $out $k) $v) -}}
{{- fail (printf "%s: label %s is set twice, to %q and to %q (by %s)" $chart $k (get $out $k) $v $from) -}}
{{- end -}}
{{- $_ := set $out $k $v -}}
{{- end -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/*
aso.tags: the Azure tags of one resource, as JSON: the chart's tags value
(every Azure Verified Module has a tags variable of the same meaning) and
the resource's own tags (a subnet's, a container's), the latter winning.
Azure allows 50 tags; a key is at most 512 characters, a value 256, and a
key holds none of < > % & \ ? /. Empty is {}.
  {{ include "aso.tags" (list $ $own) | fromJson }}
*/}}
{{- define "aso.tags" -}}
{{- $root := index . 0 -}}{{- $own := index . 1 | default dict -}}
{{- $chart := $root.Chart.Name -}}
{{- $out := dict -}}
{{- range $src := list ($root.Values.tags | default dict) $own -}}
{{- range $k, $raw := $src -}}
{{- $v := toString $raw -}}
{{- if kindIs "invalid" $raw }}{{ $v = "" }}{{ end -}}
{{- if or (gt (len $k) 512) (regexMatch "[<>%&\\\\?/]" $k) (eq $k "") -}}
{{- fail (printf "%s: tag key %q is not a valid Azure tag name: 1 to 512 characters, none of < > %% & \\ ? /" $chart $k) -}}
{{- end -}}
{{- if gt (len $v) 256 -}}
{{- fail (printf "%s: tag %s has a value of %d characters, more than the 256 Azure allows" $chart $k (len $v)) -}}
{{- end -}}
{{- $_ := set $out $k $v -}}
{{- end -}}
{{- end -}}
{{- if gt (len $out) 50 -}}
{{- fail (printf "%s: %d tags, more than the 50 Azure allows on a resource" $chart (len $out)) -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/*
aso.abandon: "true" when the chart's deletion_policy is ABANDON, else "".
DELETE is ASO's default. PREVENT has no ASO equivalent and is refused: a
CanNotDelete lock (the module's lock variable) is Azure's way.
*/}}
{{- define "aso.abandon" -}}
{{- $p := upper (toString (.Values.deletion_policy | default "DELETE")) -}}
{{- if eq $p "PREVENT" -}}
{{- fail (printf "%s: deletion_policy PREVENT has no Azure Service Operator equivalent; use lock: {kind: CanNotDelete}, ABANDON or a Bundt policy (docs/azure.md, \"Charts\")" .Chart.Name) -}}
{{- end -}}
{{- if eq $p "ABANDON" -}}true{{- end -}}
{{- end -}}

{{/*
aso.unsupported: stop the render when a value that ASO (v2.22.0) and
aso-extensions cannot express is set. Every Terraform variable stays in the
values schema, so a team's tfvars convert one to one; the ones with no kind
or field fail here, naming the gap, instead of being silently dropped.
  {{ include "aso.unsupported" (list $ "ignore_tag_changes" .Values.ignore_tag_changes "ASO always applies the tags it is given") }}
*/}}
{{- define "aso.unsupported" -}}
{{- $root := index . 0 -}}{{- $name := index . 1 -}}{{- $value := index . 2 -}}{{- $why := index . 3 -}}
{{- if not (empty $value) -}}
{{- fail (printf "%s: %s is not supported: %s (docs/azure.md, \"Charts\")" $root.Chart.Name $name $why) -}}
{{- end -}}
{{- end -}}

{{/*
aso.owner: an ASO owner reference from an Azure resource ID (a module's
parent_id, resource_group_id ...), checked to be one.
  {{ include "aso.owner" (list $ "parent_id" .Values.parent_id) }}
*/}}
{{- define "aso.owner" -}}
{{- $root := index . 0 -}}{{- $what := index . 1 -}}{{- $id := index . 2 -}}
{{- if not (and (kindIs "string" $id) (regexMatch "(?i)^/subscriptions/[^/]+(/resourcegroups/[^/]+)?(/providers/[^/]+/[^/]+/[^/]+(/[^/]+/[^/]+)*)?$" $id)) -}}
{{- fail (printf "%s: %s %q is not an Azure resource ID (/subscriptions/<id>/resourceGroups/<name>...)" $root.Chart.Name $what (toString $id)) -}}
{{- end -}}
armId: {{ $id | quote }}
{{- end -}}

{{/*
aso.roleAssignments: the role_assignments interface of an Azure Verified
Module (avm-utl-interfaces) on one resource, as ASO RoleAssignment objects
(authorization.azure.com/v20220401). A role_definition_id_or_name that is a
role definition ID becomes roleDefinitionReference.armId; a name becomes
wellKnownName, which ASO resolves by name as the module's lookup does. An
entry's name, a GUID, is the assignment's azureName; without one ASO gives
it a stable UUID. skip_service_principal_aad_check is accepted and has no
effect, as in the module's azapi resources.
Arguments (a dict):
  root      $
  base      the name the objects' names start with
  idPrefix  the prefix of their output ids
  owner     the owner reference (a dict: group, kind, name of the object)
  v         the role_assignments map
*/}}
{{- define "aso.roleAssignments" -}}
{{- $root := .root -}}
{{- $roleID := "^(/subscriptions/[0-9a-fA-F-]+)?/providers/Microsoft\\.Authorization/roleDefinitions/[0-9a-fA-F-]+$" -}}
{{- range $key, $r := (.v | default dict) }}
{{- if not $r.principal_id }}
{{- fail (printf "%s: role_assignments.%s needs a principal_id" $root.Chart.Name $key) }}
{{- end }}
{{- if not $r.role_definition_id_or_name }}
{{- fail (printf "%s: role_assignments.%s needs a role_definition_id_or_name" $root.Chart.Name $key) }}
{{- end }}
---
apiVersion: authorization.azure.com/v20220401
kind: RoleAssignment
metadata:
{{- include "aso.metadata" (dict "root" $root "name" (include "aso.name" (list $.base "role" $key)) "id" (printf "%srole-assignment-%s" $.idPrefix $key) "abandon" (include "aso.abandon" $root)) | nindent 2 }}
spec:
  {{- with $r.name }}
  azureName: {{ . | quote }}
  {{- end }}
  owner:
{{- toYaml $.owner | nindent 4 }}
  principalId: {{ $r.principal_id | quote }}
  {{- with $r.principal_type }}
  principalType: {{ . | quote }}
  {{- end }}
  roleDefinitionReference:
    {{- if regexMatch $roleID $r.role_definition_id_or_name }}
    armId: {{ $r.role_definition_id_or_name | quote }}
    {{- else }}
    wellKnownName: {{ $r.role_definition_id_or_name | quote }}
    {{- end }}
  {{- with $r.description }}
  description: {{ . | quote }}
  {{- end }}
  {{- with $r.condition }}
  condition: {{ . | quote }}
  {{- end }}
  {{- with $r.condition_version }}
  conditionVersion: {{ . | quote }}
  {{- end }}
  {{- with $r.delegated_managed_identity_resource_id }}
  delegatedManagedIdentityResourceReference:
    armId: {{ . | quote }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
aso.lock: the lock interface of an Azure Verified Module on one resource,
as an aso-extensions ManagementLock (authorization.azure.hfl.dev/v1; ASO
has no lock kind, issue #3756). Its name is the module's: lock.name, else
"lock-<kind>" (or the module's own default, defaultName).
Arguments (a dict): root, base, idPrefix, owner, v (the lock), defaultName.
*/}}
{{- define "aso.lock" -}}
{{- $root := .root -}}
{{- with .v }}
{{- if not (has .kind (list "CanNotDelete" "ReadOnly")) }}
{{- fail (printf "%s: Lock kind must be either `\"CanNotDelete\"` or `\"ReadOnly\"`." $root.Chart.Name) }}
{{- end }}
---
apiVersion: authorization.azure.hfl.dev/v1
kind: ManagementLock
metadata:
{{- include "aso.metadata" (dict "root" $root "name" (include "aso.name" (list $.base "lock")) "id" (printf "%slock" $.idPrefix) "abandon" (include "aso.abandon" $root)) | nindent 2 }}
spec:
  azureName: {{ .name | default $.defaultName | default (printf "lock-%s" .kind) | quote }}
  owner:
{{- toYaml $.owner | nindent 4 }}
  level: {{ .kind }}
  {{- with .notes }}
  notes: {{ . | quote }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
aso.diagnosticSettings: the diagnostic_settings interface of an Azure
Verified Module on one resource, as ASO DiagnosticSetting objects
(insights.azure.com/v1api20210501preview, Azure's only API version): one
log entry per log group (categoryGroup) and per log category, one metric
entry per metric category, the destinations by ARM ID. An entry's name,
else the module's default (defaultName), is its azureName.
Arguments (a dict): root, base, idPrefix, owner, v (the map), defaultName.
*/}}
{{- define "aso.diagnosticSettings" -}}
{{- $root := .root -}}
{{- range $key, $d := (.v | default dict) }}
{{- $dest := ($d.log_analytics_destination_type | default "Dedicated") }}
{{- if not (has $dest (list "Dedicated" "AzureDiagnostics")) }}
{{- fail (printf "%s: Log analytics destination type must be one of: 'Dedicated', 'AzureDiagnostics'." $root.Chart.Name) }}
{{- end }}
{{- if not (or $d.workspace_resource_id $d.storage_account_resource_id $d.event_hub_authorization_rule_resource_id $d.marketplace_partner_resource_id) }}
{{- fail (printf "%s: At least one of `workspace_resource_id`, `storage_account_resource_id`, `marketplace_partner_resource_id`, or `event_hub_authorization_rule_resource_id`, must be set." $root.Chart.Name) }}
{{- end }}
{{- $groups := ternary (list "allLogs") $d.log_groups (kindIs "invalid" $d.log_groups) }}
{{- $metrics := ternary (list "AllMetrics") $d.metric_categories (kindIs "invalid" $d.metric_categories) }}
---
apiVersion: insights.azure.com/v1api20210501preview
kind: DiagnosticSetting
metadata:
{{- include "aso.metadata" (dict "root" $root "name" (include "aso.name" (list $.base "diag" $key)) "id" (printf "%sdiagnostic-setting-%s" $.idPrefix $key) "abandon" (include "aso.abandon" $root)) | nindent 2 }}
spec:
  azureName: {{ $d.name | default $.defaultName | quote }}
  owner:
{{- toYaml $.owner | nindent 4 }}
  logAnalyticsDestinationType: {{ $dest | quote }}
  {{- if or $groups $d.log_categories }}
  logs:
    {{- range $g := (uniq $groups | sortAlpha) }}
    - categoryGroup: {{ $g | quote }}
      enabled: true
    {{- end }}
    {{- range $c := (uniq ($d.log_categories | default list) | sortAlpha) }}
    - category: {{ $c | quote }}
      enabled: true
    {{- end }}
  {{- end }}
  {{- with $metrics }}
  metrics:
    {{- range $c := (uniq . | sortAlpha) }}
    - category: {{ $c | quote }}
      enabled: true
    {{- end }}
  {{- end }}
  {{- with $d.workspace_resource_id }}
  workspaceReference:
    armId: {{ . | quote }}
  {{- end }}
  {{- with $d.storage_account_resource_id }}
  storageAccountReference:
    armId: {{ . | quote }}
  {{- end }}
  {{- with $d.event_hub_authorization_rule_resource_id }}
  eventHubAuthorizationRuleReference:
    armId: {{ . | quote }}
  {{- end }}
  {{- with $d.event_hub_name }}
  eventHubName: {{ . | quote }}
  {{- end }}
  {{- with $d.marketplace_partner_resource_id }}
  marketplacePartnerReference:
    armId: {{ . | quote }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
aso.names: stop the render when the chart's names value sets a key the
chart does not have. Every chart lists its collision-prone cloud names
once, in the template of its core resource.
  {{ include "aso.names" (list $ (list "resourceGroup")) }}
*/}}
{{- define "aso.names" -}}
{{- $root := index . 0 -}}{{- $known := index . 1 -}}
{{- range $k, $_ := ($root.Values.names | default dict) -}}
{{- if not (has $k $known) -}}
{{- fail (printf "%s: names.%s is not a name this chart gives; it takes names.%s" $root.Chart.Name $k (join ", names." $known)) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
aso.resourceName: the Azure name of one collision-prone resource
(docs/design.md, "Names, labels and tags"): names.<key> in full when set,
its length and pattern checked; otherwise the module's name with the
optional namePrefix in front (aso.cloudName).
  {{ include "aso.resourceName" (list $ "resourceGroup" "resource group" .Values.name 90 "^[-\\w._()]*[-\\w_()]$") }}
A sixth item, "compact", joins the namePrefix without a hyphen (storage
accounts take only lower-case letters and digits).
*/}}
{{- define "aso.resourceName" -}}
{{- $root := index . 0 -}}{{- $key := index . 1 -}}{{- $what := index . 2 -}}{{- $derived := index . 3 -}}{{- $max := index . 4 -}}{{- $pattern := index . 5 -}}
{{- $compact := and (gt (len .) 6) (eq (index . 6) "compact") -}}
{{- $set := index ($root.Values.names | default dict) $key -}}
{{- $name := "" -}}
{{- if $set -}}
{{- if not (kindIs "string" $set) -}}
{{- fail (printf "%s: names.%s must be a string" $root.Chart.Name $key) -}}
{{- end -}}
{{- if gt (len $set) (int $max) -}}
{{- fail (printf "%s: names.%s %q is %d characters, more than the %d Azure allows for a %s name" $root.Chart.Name $key $set (len $set) (int $max) $what) -}}
{{- end -}}
{{- $name = $set -}}
{{- else -}}
{{- $name = include "aso.cloudName" (list $root $what $derived $max $compact) -}}
{{- end -}}
{{- if not (regexMatch $pattern $name) -}}
{{- fail (printf "%s: %s name %q is not one Azure accepts (%s)" $root.Chart.Name $what $name $pattern) -}}
{{- end -}}
{{- $name -}}
{{- end -}}

{{/*
aso.namePrefix: the optional uniqueness prefix, "<namePrefix>-" ("<namePrefix>"
with compact), or "" when the chart's namePrefix value is empty (the
default: the names are the Terraform module's).
*/}}
{{- define "aso.namePrefix" -}}
{{- $root := index . 0 -}}{{- $compact := index . 1 -}}
{{- $p := $root.Values.namePrefix | default "" -}}
{{- if $p -}}
{{- if not (kindIs "string" $p) -}}
{{- fail (printf "%s: namePrefix must be a string" $root.Chart.Name) -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $p) -}}
{{- fail (printf "%s: namePrefix %q must be a DNS label: lower-case letters, digits and hyphens, not starting or ending with a hyphen (an Instance's name is one)" $root.Chart.Name $p) -}}
{{- end -}}
{{- if $compact -}}{{- replace "-" "" $p -}}{{- else -}}{{- printf "%s-" $p -}}{{- end -}}
{{- end -}}
{{- end -}}

{{/*
aso.cloudName: a name this chart gives an Azure resource, with the
namePrefix on it and its length checked when a namePrefix is set.
  {{ include "aso.cloudName" (list $ "subnet" $name 80 false) }}
*/}}
{{- define "aso.cloudName" -}}
{{- $root := index . 0 -}}{{- $what := index . 1 -}}{{- $name := index . 2 -}}{{- $max := index . 3 -}}{{- $compact := index . 4 -}}
{{- $pre := include "aso.namePrefix" (list $root $compact) -}}
{{- $full := printf "%s%s" $pre $name -}}
{{- if and $pre (gt (len $full) (int $max)) -}}
{{- fail (printf "%s: %s name %q is %d characters, more than the %d Azure allows; namePrefix %q is %d of them: shorten the namePrefix or the name" $root.Chart.Name $what $full (len $full) (int $max) $root.Values.namePrefix (len $pre)) -}}
{{- end -}}
{{- $full -}}
{{- end -}}
