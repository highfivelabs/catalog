{{/*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

Shared helpers for the Config Connector charts. The canonical copy is
lib/_kcc.tpl; every chart carries an identical copy as
templates/_kcc.tpl (hack/sync-lib.sh writes them, hack/test.sh checks
them). Names start with "kcc." so they never clash with a chart's own.
*/}}

{{/*
kcc.name: a Kubernetes object name (RFC 1123, at most 63 characters)
from a list of parts joined with "-". Characters other than lower-case
letters, digits and "-" become "-". When that changed anything, or the
name would be longer than 63 characters, the name keeps at most its
first 54 characters and ends with 8 hex characters of the sha256 of the
parts as given, so two different keys never share a name and a name
never changes between renders.
  {{ include "kcc.name" (list .Release.Name "subnet" $key) }}
*/}}
{{- define "kcc.name" -}}
{{- $raw := join "-" . -}}
{{- $n := regexReplaceAll "[^a-z0-9-]+" (lower $raw) "-" -}}
{{- $n = regexReplaceAll "-+" $n "-" | trimAll "-" -}}
{{- if or (ne $n $raw) (gt (len $n) 63) -}}
{{- $n = printf "%s-%s" (trunc 54 $n | trimSuffix "-") (sha256sum $raw | trunc 8) -}}
{{- end -}}
{{- $n -}}
{{- end -}}

{{/*
kcc.metadata: the metadata of one Config Connector object.
  root        the chart's root context ($)
  name        the object's Kubernetes name
  id          the object's output id (annotation hfl.dev/id), which a
              Package's outputs read as resources.<id> (docs/design.md, "Outputs")
  project     the Google Cloud project, or "" to take the namespace's
              (cnrm.cloud.google.com/project-id on the namespace)
  labels      further labels for this object only, copied to the cloud
              resource (Config Connector copies unprefixed metadata.labels
              to Google Cloud labels); the chart's labels and tags values
              are added to every object (kcc.labels)
  annotations further annotations
  abandon     true to keep the cloud resource when the object is deleted
*/}}
{{- define "kcc.metadata" -}}
name: {{ .name }}
labels:
  app.kubernetes.io/managed-by: {{ .root.Release.Service }}
  app.kubernetes.io/instance: {{ .root.Release.Name | quote }}
  app.kubernetes.io/name: {{ .root.Chart.Name }}
  app.kubernetes.io/version: {{ .root.Chart.Version | quote }}
{{- range $k, $v := (include "kcc.labels" (list .root (.labels | default dict)) | fromJson) }}
  {{ $k }}: {{ $v | quote }}
{{- end }}
annotations:
  hfl.dev/id: {{ .id | quote }}
{{- with .project }}
  cnrm.cloud.google.com/project-id: {{ . | quote }}
{{- end }}
{{- if .abandon }}
  cnrm.cloud.google.com/deletion-policy: abandon
{{- end }}
{{- range $k, $v := (.annotations | default dict) }}
  {{ $k }}: {{ $v | quote }}
{{- end }}
{{- end -}}

{{/*
kcc.labels: the labels every object of the chart carries besides the
standard app.kubernetes.io ones, as JSON: the chart's tags and labels
values and the object's own labels (docs/design.md, "Names, labels and
tags").
  tags    cloud labels, {KEY: VALUE}: on Google Cloud, Config Connector's
          only way to label a resource is an unprefixed metadata.label, so
          each must be a valid Google Cloud label (lower-case letters,
          digits, "_" and "-"; a key starts with a letter) and a valid
          Kubernetes label. A value that is a map or a list is left out
          here, and so is a tags value that is a list: a chart whose module
          has a tags variable of another shape maps or refuses it itself.
  labels  Kubernetes labels, {KEY: VALUE}. A prefixed key (hfl.dev/team)
          stays in Kubernetes; an unprefixed one also reaches the cloud, so
          it must be a valid Google Cloud label too.
A key set twice with different values, or one of the standard
app.kubernetes.io keys, stops the render.
  {{ include "kcc.labels" (list $ $objectLabels) | fromJson }}
*/}}
{{- define "kcc.labels" -}}
{{- $root := index . 0 -}}{{- $own := index . 1 -}}
{{- $chart := $root.Chart.Name -}}
{{- $out := dict -}}
{{- $gcpKey := "^[a-z]([a-z0-9_-]{0,61}[a-z0-9])?$" -}}
{{- $gcpValue := "^([a-z0-9]([a-z0-9_-]{0,61}[a-z0-9])?)?$" -}}
{{- $k8sKey := "^([a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*/)?[A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?$" -}}
{{- $k8sValue := "^([A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?)?$" -}}
{{- $standard := list "app.kubernetes.io/managed-by" "app.kubernetes.io/instance" "app.kubernetes.io/name" "app.kubernetes.io/version" -}}
{{- /* A tags value that is a list is a module's own variable of that name
(gke-nodepool's network tags), not cloud labels: the chart maps it. */ -}}
{{- $tags := $root.Values.tags | default dict -}}
{{- if kindIs "slice" $tags }}{{ $tags = dict }}{{ end -}}
{{- $sources := list (list "tags" $tags) (list "labels" ($root.Values.labels | default dict)) (list "labels of this object" $own) -}}
{{- range $s := $sources -}}
{{- $from := index $s 0 -}}
{{- range $k, $raw := (index $s 1) -}}
{{- if not (and (eq $from "tags") (or (kindIs "map" $raw) (kindIs "slice" $raw))) -}}
{{- $v := toString $raw -}}
{{- if kindIs "invalid" $raw }}{{ $v = "" }}{{ end -}}
{{- if has $k $standard -}}
{{- fail (printf "%s: %s %s: the chart sets this label itself" $chart $from $k) -}}
{{- end -}}
{{- if or (eq $from "tags") (not (contains "/" $k)) -}}
{{- if not (and (regexMatch $gcpKey $k) (regexMatch $gcpValue $v)) -}}
{{- fail (printf "%s: %s %s=%q is not a valid Google Cloud label: a key starts with a lower-case letter; keys and values are at most 63 lower-case letters, digits, \"_\" or \"-\", ending with a letter or digit%s" $chart $from $k $v (ternary "" " (an unprefixed Kubernetes label reaches the cloud through Config Connector: prefix the key, as in hfl.dev/team, to keep it in Kubernetes)" (eq $from "tags"))) -}}
{{- end -}}
{{- else if not (and (regexMatch $k8sKey $k) (regexMatch $k8sValue $v) (le (len (splitList "/" $k | first)) 253)) -}}
{{- fail (printf "%s: %s %s=%q is not a valid Kubernetes label" $chart $from $k $v) -}}
{{- end -}}
{{- if and (hasKey $out $k) (ne (get $out $k) $v) -}}
{{- fail (printf "%s: label %s is set twice, to %q and to %q (by %s)" $chart $k (get $out $k) $v $from) -}}
{{- end -}}
{{- $_ := set $out $k $v -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/*
kcc.abandon: "true" when the chart's deletion_policy is ABANDON, else "".
Fabric's DELETE is Config Connector's default. PREVENT has no Config
Connector equivalent and is refused (docs/design.md, "Deletion").
*/}}
{{- define "kcc.abandon" -}}
{{- $p := upper (toString (.Values.deletion_policy | default "DELETE")) -}}
{{- if eq $p "PREVENT" -}}
{{- fail (printf "%s: deletion_policy PREVENT has no Config Connector equivalent; use ABANDON, a lien (project) or a Bundt policy (docs/design.md, \"Deletion\")" .Chart.Name) -}}
{{- end -}}
{{- if eq $p "ABANDON" -}}true{{- end -}}
{{- end -}}

{{/*
kcc.unsupported: stop the render when a value that Config Connector
v1.160.0 cannot express is set. Every Terraform variable stays in the
values schema, so a team's tfvars convert one to one; the ones with no
Config Connector field fail here, naming the gap, instead of being
silently dropped.
  {{ include "kcc.unsupported" (list $ "rpo" .Values.rpo "StorageBucket has no rpo (Config Connector PR #13713)") }}
*/}}
{{- define "kcc.unsupported" -}}
{{- $root := index . 0 -}}{{- $name := index . 1 -}}{{- $value := index . 2 -}}{{- $why := index . 3 -}}
{{- if not (empty $value) -}}
{{- fail (printf "%s: %s is not supported: %s (docs/gcp-inventory.md, \"Gaps\")" $root.Chart.Name $name $why) -}}
{{- end -}}
{{- end -}}

{{/*
kcc.alpha: stop the render when a feature that needs a v1alpha1 Config
Connector kind is used without the chart's allow_alpha value. Alpha kinds
may change their schema between Config Connector releases, so a team opts
in per component (docs/design.md, "Alpha kinds"); beta (v1beta1) kinds are
always on.
  {{ include "kcc.alpha" (list $ "network_attachments" .Values.network_attachments "ComputeNetworkAttachment") }}
*/}}
{{- define "kcc.alpha" -}}
{{- $root := index . 0 -}}{{- $name := index . 1 -}}{{- $value := index . 2 -}}{{- $kind := index . 3 -}}
{{- if and (not (empty $value)) (not $root.Values.allow_alpha) -}}
{{- fail (printf "%s: %s needs the alpha Config Connector kind %s: set allow_alpha: true to accept that its schema may change (docs/design.md, \"Alpha kinds\")" $root.Chart.Name $name $kind) -}}
{{- end -}}
{{- end -}}

{{/*
kcc.condition: an IAM condition from fabric's {expression, title, description}.
*/}}
{{- define "kcc.condition" -}}
title: {{ .title | quote }}
expression: {{ .expression | quote }}
{{- with .description }}
description: {{ . | quote }}
{{- end }}
{{- end -}}

{{/*
kcc.iam: the IAM a fabric module manages on one resource, from its
standard IAM variables (docs/design.md, "IAM"):
  iam, iam_by_principals                  authoritative for the roles they
                                          name: one IAMPartialPolicy
  iam_bindings                            exact per role: one IAMBinding each
                                          (config-connector-extensions,
                                          iam.gcp.hfl.dev/v1beta1) when the
                                          kind takes the resource; otherwise
                                          bindings of the IAMPartialPolicy
  iam_bindings_additive,
  iam_by_principals_additive              additive: one IAMPolicyMember each
Arguments (a dict):
  root         $
  base         the name the objects' names start with
  idPrefix     the prefix of their output ids
  resourceRef  the resource the policy is on (Config Connector resourceRef)
  v            a dict holding the five variables (missing ones are empty)
*/}}
{{- define "kcc.iam" -}}
{{- $root := .root -}}
{{- $v := .v -}}
{{- $roles := dict -}}
{{- range $role, $members := ($v.iam | default dict) -}}
{{- $_ := set $roles $role (concat (get $roles $role | default list) $members) -}}
{{- end -}}
{{- range $principal, $prs := ($v.iam_by_principals | default dict) -}}
{{- range $role := $prs -}}
{{- $_ := set $roles $role (append (get $roles $role | default list) $principal) -}}
{{- end -}}
{{- end -}}
{{- $bindings := ($v.iam_bindings | default dict) -}}
{{- /* The resource kinds IAMBinding takes (config-connector-extensions
pkg/iampolicy/registry.go) that a catalog chart puts IAM on. */ -}}
{{- $exact := dict -}}
{{- if and $bindings (has .resourceRef.kind (list "Project" "Folder" "Organization" "IAMServiceAccount" "StorageBucket" "SecretManagerSecret" "ArtifactRegistryRepository" "RunService" "PubSubTopic" "PubSubSubscription" "KMSKeyRing" "KMSCryptoKey")) -}}
{{- $exact = $bindings -}}
{{- $bindings = dict -}}
{{- end -}}
{{- range $key, $b := $exact }}
---
apiVersion: iam.gcp.hfl.dev/v1beta1
kind: IAMBinding
metadata:
{{- include "kcc.metadata" (dict "root" $root "name" (include "kcc.name" (list $.base "iam-binding" $key)) "id" (printf "%siam-binding-%s" $.idPrefix $key)) | nindent 2 }}
spec:
  resourceRef:
{{- toYaml $.resourceRef | nindent 4 }}
  role: {{ $b.role | quote }}
  members:
{{- range $m := (uniq $b.members | sortAlpha) }}
    - {{ $m | quote }}
{{- end }}
{{- with $b.condition }}
  condition:
{{- include "kcc.condition" . | nindent 4 }}
{{- end }}
{{- end }}
{{- if or $roles $bindings }}
---
apiVersion: iam.cnrm.cloud.google.com/v1beta1
kind: IAMPartialPolicy
metadata:
{{- include "kcc.metadata" (dict "root" $root "name" (include "kcc.name" (list .base "iam")) "id" (printf "%siam" .idPrefix)) | nindent 2 }}
spec:
  resourceRef:
{{- toYaml .resourceRef | nindent 4 }}
  bindings:
{{- range $role, $members := $roles }}
    - role: {{ $role | quote }}
      members:
{{- range $m := (uniq $members | sortAlpha) }}
        - member: {{ $m | quote }}
{{- end }}
{{- end }}
{{- range $key, $b := $bindings }}
    - role: {{ $b.role | quote }}
      members:
{{- range $m := (uniq $b.members | sortAlpha) }}
        - member: {{ $m | quote }}
{{- end }}
{{- with $b.condition }}
      condition:
{{- include "kcc.condition" . | nindent 8 }}
{{- end }}
{{- end }}
{{- end }}
{{- $additive := dict -}}
{{- range $key, $b := ($v.iam_bindings_additive | default dict) -}}
{{- $_ := set $additive $key $b -}}
{{- end -}}
{{- range $principal, $prs := ($v.iam_by_principals_additive | default dict) -}}
{{- range $role := $prs -}}
{{- $_ := set $additive (printf "iam-bpa:%s-%s" $principal $role) (dict "member" $principal "role" $role) -}}
{{- end -}}
{{- end -}}
{{- range $key, $b := $additive }}
---
apiVersion: iam.cnrm.cloud.google.com/v1beta1
kind: IAMPolicyMember
metadata:
{{- include "kcc.metadata" (dict "root" $root "name" (include "kcc.name" (list $.base "iam" $key)) "id" (printf "%siam-additive-%s" $.idPrefix $key)) | nindent 2 }}
spec:
  resourceRef:
{{- toYaml $.resourceRef | nindent 4 }}
  role: {{ $b.role | quote }}
  member: {{ $b.member | quote }}
{{- with $b.condition }}
  condition:
{{- include "kcc.condition" . | nindent 4 }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
kcc.names: stop the render when the chart's names value sets a key the
chart does not have. Every chart lists its collision-prone cloud names
once, in the template of its core resource.
  {{ include "kcc.names" (list $ (list "bucket" "topic")) }}
*/}}
{{- define "kcc.names" -}}
{{- $root := index . 0 -}}{{- $known := index . 1 -}}
{{- range $k, $_ := ($root.Values.names | default dict) -}}
{{- if not (has $k $known) -}}
{{- fail (printf "%s: names.%s is not a name this chart gives; it takes names.%s" $root.Chart.Name $k (join ", names." $known)) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
kcc.resourceName: the cloud name of one collision-prone resource
(docs/design.md, "Names, labels and tags").
  - names.<key> set: that name, in full: no namePrefix and no module
    prefix are added. Bundt supplies these from a team's naming
    convention. Its length (and, with "letter", its first character) is
    checked.
  - otherwise the name derived from the base name (fabric's naming), with
    the optional namePrefix in front (kcc.cloudName).
  {{ include "kcc.resourceName" (list $ "bucket" "bucket" $derived 63) }}
  {{ include "kcc.resourceName" (list $ "network" "network" .Values.name 63 "letter") }}
*/}}
{{- define "kcc.resourceName" -}}
{{- $root := index . 0 -}}{{- $key := index . 1 -}}{{- $what := index . 2 -}}{{- $derived := index . 3 -}}{{- $max := index . 4 -}}
{{- $letter := and (gt (len .) 5) (eq (index . 5) "letter") -}}
{{- $set := index ($root.Values.names | default dict) $key -}}
{{- if $set -}}
{{- if not (kindIs "string" $set) -}}
{{- fail (printf "%s: names.%s must be a string" $root.Chart.Name $key) -}}
{{- end -}}
{{- if gt (len $set) (int $max) -}}
{{- fail (printf "%s: names.%s %q is %d characters, more than the %d the cloud allows for a %s name" $root.Chart.Name $key $set (len $set) (int $max) $what) -}}
{{- end -}}
{{- if and $letter (not (regexMatch "^[a-z]" $set)) -}}
{{- fail (printf "%s: names.%s %q must start with a lower-case letter" $root.Chart.Name $key $set) -}}
{{- end -}}
{{- $set -}}
{{- else if $letter -}}
{{- include "kcc.cloudName" (list $root $what $derived $max "letter") -}}
{{- else -}}
{{- include "kcc.cloudName" (list $root $what $derived $max) -}}
{{- end -}}
{{- end -}}

{{/*
kcc.namePrefix: the optional uniqueness prefix, "<namePrefix>-", or ""
when the chart's namePrefix value is empty (the default: nothing changes
and the names are the Terraform module's). A convenience: a name set in
full under names.<key> takes no prefix (kcc.resourceName), and Bundt
supplies whole names from a team's naming convention rather than a
prefix (docs/design.md, "Names, labels and tags").
It goes outermost, on top of a module's own prefix variable:
<namePrefix>-<prefix>-<name>.
*/}}
{{- define "kcc.namePrefix" -}}
{{- $p := .Values.namePrefix | default "" -}}
{{- if $p -}}
{{- if not (kindIs "string" $p) -}}
{{- fail (printf "%s: namePrefix must be a string" .Chart.Name) -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $p) -}}
{{- fail (printf "%s: namePrefix %q must be a DNS label: lower-case letters, digits and hyphens, not starting or ending with a hyphen (an Instance's name is one)" .Chart.Name $p) -}}
{{- end -}}
{{- printf "%s-" $p -}}
{{- end -}}
{{- end -}}

{{/*
kcc.fit: stop the render when a name made with a namePrefix is longer than
the cloud allows. Returns the name. Nothing is checked without a
namePrefix, so a chart's behaviour with its Terraform-parity values is
unchanged.
  {{ include "kcc.fit" (list $ "subnet" $name 63) }}
*/}}
{{- define "kcc.fit" -}}
{{- $root := index . 0 -}}{{- $what := index . 1 -}}{{- $name := index . 2 -}}{{- $max := index . 3 -}}
{{- $pre := include "kcc.namePrefix" $root -}}
{{- if and $pre (gt (len $name) (int $max)) -}}
{{- fail (printf "%s: %s name %q is %d characters, more than the %d the cloud allows; namePrefix %q is %d of them (with its hyphen): shorten the namePrefix or the name" $root.Chart.Name $what $name (len $name) (int $max) $root.Values.namePrefix (len $pre)) -}}
{{- end -}}
{{- $name -}}
{{- end -}}

{{/*
kcc.cloudName: a name this chart gives a cloud resource, with the
namePrefix on it and its length checked. A fifth item, "letter", says the
cloud wants the name to start with a letter (service account IDs, project
IDs, networks ...); a namePrefix that starts with a digit, as an Instance
name may, then stops the render naming the resource.
  {{ include "kcc.cloudName" (list $ "bucket" $name 63) }}
  {{ include "kcc.cloudName" (list $ "network" $name 63 "letter") }}
*/}}
{{- define "kcc.cloudName" -}}
{{- $root := index . 0 -}}{{- $what := index . 1 -}}{{- $name := index . 2 -}}{{- $max := index . 3 -}}
{{- $pre := include "kcc.namePrefix" $root -}}
{{- if and $pre (gt (len .) 4) (eq (index . 4) "letter") (not (regexMatch "^[a-z]" $pre)) -}}
{{- fail (printf "%s: %s name %q must start with a lower-case letter, and namePrefix %q starts with a digit" $root.Chart.Name $what (printf "%s%s" $pre $name) $root.Values.namePrefix) -}}
{{- end -}}
{{- include "kcc.fit" (list $root $what (printf "%s%s" $pre $name) $max) -}}
{{- end -}}
