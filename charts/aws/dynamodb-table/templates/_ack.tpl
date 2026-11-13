{{/*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

Shared helpers for the AWS charts, which render AWS Controllers for
Kubernetes (ACK) objects (docs/aws.md, "Charts"). The canonical copy is
lib/_ack.tpl; every chart under charts/aws carries an identical copy as
templates/_ack.tpl (hack/sync-lib.sh writes them, hack/test.sh checks
them). Names start with "ack." so they never clash with a chart's own.
They follow lib/_kcc.tpl's conventions (docs/design.md): Kubernetes names,
hfl.dev/id, names/namePrefix/labels/tags, refusals by name.
*/}}

{{/*
ack.name: a Kubernetes object name (RFC 1123, at most 63 characters)
from a list of parts joined with "-". Characters other than lower-case
letters, digits and "-" become "-". When that changed anything, or the
name would be longer than 63 characters, the name keeps at most its
first 54 characters and ends with 8 hex characters of the sha256 of the
parts as given, so two different keys never share a name and a name
never changes between renders.
  {{ include "ack.name" (list .Release.Name "subnet" "public" $i) }}
*/}}
{{- define "ack.name" -}}
{{- $raw := join "-" . -}}
{{- $n := regexReplaceAll "[^a-z0-9-]+" (lower $raw) "-" -}}
{{- $n = regexReplaceAll "-+" $n "-" | trimAll "-" -}}
{{- if or (ne $n $raw) (gt (len $n) 63) -}}
{{- $n = printf "%s-%s" (trunc 54 $n | trimSuffix "-") (sha256sum $raw | trunc 8) -}}
{{- end -}}
{{- $n -}}
{{- end -}}

{{/*
ack.metadata: the metadata of one ACK object.
  root        the chart's root context ($)
  name        the object's Kubernetes name
  id          the object's output id (annotation hfl.dev/id), which a
              Package's outputs read as resources.<id> (docs/design.md, "Outputs")
  region      the AWS region (annotation services.k8s.aws/region), or "" to
              take the namespace's or the controller's
  annotations further annotations
The chart's labels value is added to every object (Kubernetes labels only:
ACK does not copy labels to AWS; tags are in each kind's spec, ack.tags).
deletion_policy ABANDON keeps the AWS resource when the object is deleted
(services.k8s.aws/deletion-policy: retain).
*/}}
{{- define "ack.metadata" -}}
name: {{ .name }}
labels:
  app.kubernetes.io/managed-by: {{ .root.Release.Service }}
  app.kubernetes.io/instance: {{ .root.Release.Name | quote }}
  app.kubernetes.io/name: {{ .root.Chart.Name }}
  app.kubernetes.io/version: {{ .root.Chart.Version | quote }}
{{- range $k, $v := (include "ack.labels" .root | fromJson) }}
  {{ $k }}: {{ $v | quote }}
{{- end }}
annotations:
  hfl.dev/id: {{ .id | quote }}
{{- with .region }}
  services.k8s.aws/region: {{ . | quote }}
{{- end }}
{{- if include "ack.abandon" .root }}
  services.k8s.aws/deletion-policy: retain
{{- end }}
{{- range $k, $v := (.annotations | default dict) }}
  {{ $k }}: {{ $v | quote }}
{{- end }}
{{- end -}}

{{/*
ack.labels: the chart's labels value, checked, as JSON. Every key and value
must be a valid Kubernetes label; the standard app.kubernetes.io keys the
chart sets itself are refused.
*/}}
{{- define "ack.labels" -}}
{{- $chart := .Chart.Name -}}
{{- $out := dict -}}
{{- $k8sKey := "^([a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*/)?[A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?$" -}}
{{- $k8sValue := "^([A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?)?$" -}}
{{- $standard := list "app.kubernetes.io/managed-by" "app.kubernetes.io/instance" "app.kubernetes.io/name" "app.kubernetes.io/version" -}}
{{- range $k, $raw := (.Values.labels | default dict) -}}
{{- $v := toString $raw -}}
{{- if kindIs "invalid" $raw }}{{ $v = "" }}{{ end -}}
{{- if has $k $standard -}}
{{- fail (printf "%s: labels %s: the chart sets this label itself" $chart $k) -}}
{{- end -}}
{{- if not (and (regexMatch $k8sKey $k) (regexMatch $k8sValue $v) (le (len (splitList "/" $k | first)) 253)) -}}
{{- fail (printf "%s: labels %s=%q is not a valid Kubernetes label (on AWS, labels stay in Kubernetes; put AWS tags under tags)" $chart $k $v) -}}
{{- end -}}
{{- $_ := set $out $k $v -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/*
ack.tags: the AWS tags of one resource, as JSON {KEY: VALUE}: the maps
given, merged in order, a later one winning, as Terraform's merge() does.
A module merges {Name = ...}, var.tags and a per-resource map
(merge({Name = var.name}, var.tags, var.vpc_tags)); pass them the same way.
The chart's tags value is the module's tags variable (docs/design.md,
"Names, labels and tags"). Each key must be 1 to 128 characters and not
start with "aws:", each value at most 256 characters (AWS's tag rules).
  {{ $tags := include "ack.tags" (list $ (dict "Name" $name) .Values.tags .Values.vpc_tags) | fromJson }}
*/}}
{{- define "ack.tags" -}}
{{- $root := index . 0 -}}
{{- $out := dict -}}
{{- range $m := (rest .) -}}
{{- range $k, $raw := ($m | default dict) -}}
{{- $v := toString $raw -}}
{{- if kindIs "invalid" $raw }}{{ $v = "" }}{{ end -}}
{{- if or (eq (len $k) 0) (gt (len $k) 128) (hasPrefix "aws:" (lower $k)) -}}
{{- fail (printf "%s: tag key %q is not a valid AWS tag key: 1 to 128 characters, not starting with \"aws:\"" $root.Chart.Name $k) -}}
{{- end -}}
{{- if gt (len $v) 256 -}}
{{- fail (printf "%s: tag %s's value is %d characters, more than the 256 AWS allows" $root.Chart.Name $k (len $v)) -}}
{{- end -}}
{{- $_ := set $out $k $v -}}
{{- end -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/*
ack.tagList: tags (a dict from ack.tags) as the YAML list most ACK kinds
take, sorted by key: [{key, value}]. The optional second and third items
name the fields, for kinds that call them otherwise (KMS: tagKey, tagValue).
Renders nothing when there are no tags.
  tags:
  {{- include "ack.tagList" (list $tags) | nindent 4 }}
*/}}
{{- define "ack.tagList" -}}
{{- $tags := index . 0 -}}
{{- $kf := "key" -}}{{- $vf := "value" -}}
{{- if gt (len .) 2 }}{{ $kf = index . 1 }}{{ $vf = index . 2 }}{{ end -}}
{{- $lines := list -}}
{{- range $k := (keys $tags | sortAlpha) -}}
{{- $lines = append $lines (printf "- %s: %s\n  %s: %s" $kf (quote $k) $vf (quote (get $tags $k))) -}}
{{- end -}}
{{- join "\n" $lines -}}
{{- end -}}

{{/*
ack.abandon: "true" when the chart's deletion_policy is ABANDON, else "".
DELETE is ACK's default: deleting the object deletes the AWS resource.
ABANDON renders services.k8s.aws/deletion-policy: retain (docs/design.md,
"Deletion"). PREVENT has no ACK equivalent and is refused.
*/}}
{{- define "ack.abandon" -}}
{{- $p := upper (toString (.Values.deletion_policy | default "DELETE")) -}}
{{- if eq $p "PREVENT" -}}
{{- fail (printf "%s: deletion_policy PREVENT has no ACK equivalent; use ABANDON or a Bundt policy (docs/design.md, \"Deletion\")" .Chart.Name) -}}
{{- end -}}
{{- if eq $p "ABANDON" -}}true{{- end -}}
{{- end -}}

{{/*
ack.unsupported: stop the render when a value that ACK (at the controller
releases in UPSTREAM.md) cannot express is set. Every Terraform variable
stays in the values schema, so a team's tfvars convert one to one; the
ones with no ACK kind or field fail here, naming the gap, instead of being
silently dropped.
  {{ include "ack.unsupported" (list $ "enable_ipv6" .Values.enable_ipv6 "a subnet's IPv6 block ...") }}
*/}}
{{- define "ack.unsupported" -}}
{{- $root := index . 0 -}}{{- $name := index . 1 -}}{{- $value := index . 2 -}}{{- $why := index . 3 -}}
{{- if not (empty $value) -}}
{{- fail (printf "%s: %s is not supported: %s (docs/aws.md)" $root.Chart.Name $name $why) -}}
{{- end -}}
{{- end -}}

{{/*
ack.unchanged: like ack.unsupported, for a variable whose Terraform
default is not empty (a suffix, a flag that defaults to true): stop the
render when its value differs from that default, which is what the chart
renders. The default is given as JSON, as toJson writes it (keys sorted,
no spaces).
  {{ include "ack.unchanged" (list $ "redshift_subnet_suffix" .Values.redshift_subnet_suffix "\"redshift\"" "...") }}
*/}}
{{- define "ack.unchanged" -}}
{{- $root := index . 0 -}}{{- $name := index . 1 -}}{{- $value := index . 2 -}}{{- $default := index . 3 -}}{{- $why := index . 4 -}}
{{- if ne (toJson $value) $default -}}
{{- fail (printf "%s: %s is not supported: %s (docs/aws.md); only its default, %s, is accepted" $root.Chart.Name $name $why $default) -}}
{{- end -}}
{{- end -}}

{{/*
ack.alpha: stop the render when a feature that needs a kind outside ACK's
released controllers (an ack-extensions kind, docs/aws.md) is used without
the chart's allow_alpha value. ACK serves every kind as v1alpha1, so the
API version says nothing; what counts is the controller: a GA (v1.x) ACK
controller's kinds are always on, ack-extensions' and ACK preview (v0.x)
controllers' kinds need the opt-in (docs/design.md, "Alpha kinds").
  {{ include "ack.alpha" (list $ "customer_gateways" .Values.customer_gateways "CustomerGateway (ack-extensions)") }}
*/}}
{{- define "ack.alpha" -}}
{{- $root := index . 0 -}}{{- $name := index . 1 -}}{{- $value := index . 2 -}}{{- $kind := index . 3 -}}
{{- if and (not (empty $value)) (not $root.Values.allow_alpha) -}}
{{- fail (printf "%s: %s needs the alpha kind %s, outside ACK's released controllers: set allow_alpha: true to accept that its schema may change (docs/design.md, \"Alpha kinds\")" $root.Chart.Name $name $kind) -}}
{{- end -}}
{{- end -}}

{{/*
ack.names: stop the render when the chart's names value sets a key the
chart does not have. Every chart lists its names once, in the template of
its core resource.
  {{ include "ack.names" (list $ (list "vpc" "databaseSubnetGroup")) }}
*/}}
{{- define "ack.names" -}}
{{- $root := index . 0 -}}{{- $known := index . 1 -}}
{{- range $k, $_ := ($root.Values.names | default dict) -}}
{{- if not (has $k $known) -}}
{{- fail (printf "%s: names.%s is not a name this chart gives; it takes names.%s" $root.Chart.Name $k (join ", names." $known)) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
ack.resourceName: the AWS name of one resource the chart names
(docs/design.md, "Names, labels and tags").
  - names.<key> set: that name, in full: no namePrefix is added. Bundt
    supplies these from a team's naming convention. Its length (and, with
    "letter", its first character) is checked.
  - otherwise the name derived as the Terraform module derives it, with the
    optional namePrefix in front (ack.cloudName).
  {{ include "ack.resourceName" (list $ "bucket" "bucket" $derived 63) }}
*/}}
{{- define "ack.resourceName" -}}
{{- $root := index . 0 -}}{{- $key := index . 1 -}}{{- $what := index . 2 -}}{{- $derived := index . 3 -}}{{- $max := index . 4 -}}
{{- $letter := and (gt (len .) 5) (eq (index . 5) "letter") -}}
{{- $set := index ($root.Values.names | default dict) $key -}}
{{- if $set -}}
{{- if not (kindIs "string" $set) -}}
{{- fail (printf "%s: names.%s must be a string" $root.Chart.Name $key) -}}
{{- end -}}
{{- if gt (len $set) (int $max) -}}
{{- fail (printf "%s: names.%s %q is %d characters, more than the %d AWS allows for a %s name" $root.Chart.Name $key $set (len $set) (int $max) $what) -}}
{{- end -}}
{{- if and $letter (not (regexMatch "^[a-zA-Z]" $set)) -}}
{{- fail (printf "%s: names.%s %q must start with a letter" $root.Chart.Name $key $set) -}}
{{- end -}}
{{- $set -}}
{{- else if $letter -}}
{{- include "ack.cloudName" (list $root $what $derived $max "letter") -}}
{{- else -}}
{{- include "ack.cloudName" (list $root $what $derived $max) -}}
{{- end -}}
{{- end -}}

{{/*
ack.namePrefix: the optional uniqueness prefix, "<namePrefix>-", or ""
when the chart's namePrefix value is empty (the default: nothing changes
and the names are the Terraform module's).
*/}}
{{- define "ack.namePrefix" -}}
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
ack.fit: stop the render when a name made with a namePrefix is longer than
AWS allows. Returns the name. Nothing is checked without a namePrefix, so
a chart's behaviour with its Terraform-parity values is unchanged.
*/}}
{{- define "ack.fit" -}}
{{- $root := index . 0 -}}{{- $what := index . 1 -}}{{- $name := index . 2 -}}{{- $max := index . 3 -}}
{{- $pre := include "ack.namePrefix" $root -}}
{{- if and $pre (gt (len $name) (int $max)) -}}
{{- fail (printf "%s: %s name %q is %d characters, more than the %d AWS allows; namePrefix %q is %d of them (with its hyphen): shorten the namePrefix or the name" $root.Chart.Name $what $name (len $name) (int $max) $root.Values.namePrefix (len $pre)) -}}
{{- end -}}
{{- $name -}}
{{- end -}}

{{/*
ack.cloudName: a name this chart gives an AWS resource (or its Name tag),
with the namePrefix on it and its length checked. A fifth item, "letter",
says AWS wants the name to start with a letter.
  {{ include "ack.cloudName" (list $ "subnet" $name 256) }}
*/}}
{{- define "ack.cloudName" -}}
{{- $root := index . 0 -}}{{- $what := index . 1 -}}{{- $name := index . 2 -}}{{- $max := index . 3 -}}
{{- $pre := include "ack.namePrefix" $root -}}
{{- if and $pre (gt (len .) 4) (eq (index . 4) "letter") (not (regexMatch "^[a-z]" $pre)) -}}
{{- fail (printf "%s: %s name %q must start with a letter, and namePrefix %q starts with a digit" $root.Chart.Name $what (printf "%s%s" $pre $name) $root.Values.namePrefix) -}}
{{- end -}}
{{- include "ack.fit" (list $root $what (printf "%s%s" $pre $name) $max) -}}
{{- end -}}
