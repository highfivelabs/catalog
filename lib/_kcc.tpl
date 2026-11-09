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
  labels      labels copied to the cloud resource (Config Connector copies
              unprefixed metadata.labels to Google Cloud labels)
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
{{- range $k, $v := (.labels | default dict) }}
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
  iam, iam_by_principals, iam_bindings    authoritative for the roles they
                                          name: one IAMPartialPolicy
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
