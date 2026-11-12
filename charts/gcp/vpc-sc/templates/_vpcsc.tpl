{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Ported from cloud-foundation-fabric modules/vpc-sc (v60.0.0), Copyright
Google LLC, Apache-2.0: the helpers the chart's templates share.
*/ -}}

{{/*
vpcsc.context: stop the render when a value is one of fabric's $context
lookups ($identity_sets:, $resource_sets:, $iam_principals:, ...). The
module's own keys ($access_levels:, $egress_policies:, $ingress_policies:)
are resolved by the caller before this is reached.
  {{ include "vpcsc.context" (list $ "perimeters.p.spec.resources" $value) }}
*/}}
{{- define "vpcsc.context" -}}
{{- $root := index . 0 -}}{{- $where := index . 1 -}}{{- $value := index . 2 -}}
{{- if hasPrefix "$" (toString $value) -}}
{{- include "kcc.unsupported" (list $root "context" "x" (printf "%s %q is a fabric $context lookup; Bundt replaces them with ${...} expressions and valueFrom in the component's inputs" $where $value)) -}}
{{- end -}}
{{- end -}}

{{/*
vpcsc.data: the access levels, ingress and egress policies and perimeters
as fabric merges them (factory.tf's local.data, then the variables: a key
in both is the variable's), as JSON {levels, ingress, egress, perimeters}.
Policies are keyed as fabric keys them: "$ingress_policies:<NAME>".
*/}}
{{- define "vpcsc.data" -}}
{{- $v := .Values -}}
{{- $fd := $v.factories_data | default dict -}}
{{- $out := dict "levels" dict "ingress" dict "egress" dict "perimeters" dict -}}
{{- range $pair := list (list "levels" "access_levels" "") (list "ingress" "ingress_policies" "$ingress_policies:") (list "egress" "egress_policies" "$egress_policies:") (list "perimeters" "perimeters" "") -}}
{{- $dst := index $out (index $pair 0) -}}
{{- range $src := list (index $fd (index $pair 1) | default dict) (index $v (index $pair 1) | default dict) -}}
{{- range $k, $item := $src -}}
{{- $_ := set $dst (printf "%s%s" (index $pair 2) $k) ($item | default dict) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/*
vpcsc.shortName: an access level's or perimeter's name: fabric's key,
with the namePrefix in front. These names hold only letters, digits and
"_" and start with a letter, so the prefix goes on with its hyphens as
underscores: "<namePrefix>_<key>" ("shop_dev_<key>"). Checked against the
50 characters the API allows only when a namePrefix is set, as kcc.fit.
  {{ include "vpcsc.shortName" (list $ "access level" $key) }}
*/}}
{{- define "vpcsc.shortName" -}}
{{- $root := index . 0 -}}{{- $what := index . 1 -}}{{- $key := index . 2 -}}
{{- $p := include "kcc.namePrefix" $root | trimSuffix "-" -}}
{{- if $p -}}
{{- if not (regexMatch "^[a-z]" $p) -}}
{{- fail (printf "%s: %s name %q must start with a letter, and namePrefix %q starts with a digit" $root.Chart.Name $what (printf "%s_%s" $p $key) $p) -}}
{{- end -}}
{{- $name := printf "%s_%s" (replace "-" "_" $p) $key -}}
{{- if gt (len $name) 50 -}}
{{- fail (printf "%s: %s name %q is %d characters, more than the 50 the cloud allows; namePrefix %q is %d of them (with its \"_\"): shorten the namePrefix or the name" $root.Chart.Name $what $name (len $name) $p (add1 (len $p))) -}}
{{- end -}}
{{- $name -}}
{{- else -}}
{{- $key -}}
{{- end -}}
{{- end -}}

{{/*
vpcsc.policyRef: accessPolicyRef's body: the chart's AccessContextManagerAccessPolicy
by its object's name when access_policy_create is set (fabric's
try(created, var.access_policy)), else access_policy as an external
reference.
*/}}
{{- define "vpcsc.policyRef" -}}
{{- $v := .Values -}}
{{- if $v.access_policy_create -}}
name: {{ .Release.Name }}
{{- else if $v.access_policy -}}
{{- include "vpcsc.context" (list $ "access_policy" $v.access_policy) -}}
external: {{ printf "accessPolicies/%s" (toString $v.access_policy) | quote }}
{{- else -}}
{{- fail (printf "%s: set access_policy (an existing policy's number) or access_policy_create" .Chart.Name) -}}
{{- end -}}
{{- end -}}

{{/*
vpcsc.levelRef: a reference to an access level: "$access_levels:<NAME>"
is this chart's level <NAME> (fabric's local.ctx_access_levels), by its
object's name; anything else is an access level's resource name
(accessPolicies/<policy>/accessLevels/<name>), external.
  {{ include "vpcsc.levelRef" (list $ $where $ref $levels) }}
*/}}
{{- define "vpcsc.levelRef" -}}
{{- $root := index . 0 -}}{{- $where := index . 1 -}}{{- $ref := toString (index . 2) -}}{{- $levels := index . 3 -}}
{{- if hasPrefix "$access_levels:" $ref -}}
{{- $k := trimPrefix "$access_levels:" $ref -}}
{{- if not (hasKey $levels $k) -}}
{{- fail (printf "%s: %s: access level %q is not defined in access_levels" $root.Chart.Name $where $k) -}}
{{- end -}}
name: {{ include "kcc.name" (list $root.Release.Name "level" $k) }}
{{- else -}}
{{- include "vpcsc.context" (list $root $where $ref) -}}
external: {{ $ref | quote }}
{{- end -}}
{{- end -}}

{{/*
vpcsc.identities: the identities of an ingress or egress policy's "from",
as Config Connector's list (a user, or a service account by its member
string). Groups and principals have no field.
*/}}
{{- define "vpcsc.identities" -}}
{{- $root := index . 0 -}}{{- $where := index . 1 -}}{{- $list := index . 2 -}}
{{- range $i := $list }}
{{- include "vpcsc.context" (list $root $where $i) }}
{{- if hasPrefix "user:" $i }}
- user: {{ trimPrefix "user:" $i | quote }}
{{- else if hasPrefix "serviceAccount:" $i }}
- serviceAccountRef:
    external: {{ $i | quote }}
{{- else }}
{{- include "kcc.unsupported" (list $root $where "x" (printf "%q: AccessContextManagerServicePerimeter's identities are users and service accounts only (no group:, principal: or principalSet:)" $i)) }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
vpcsc.resources: a list of resources (projects/<number>, or a VPC
network's full name), each as an external projectRef.
*/}}
{{- define "vpcsc.resources" -}}
{{- $root := index . 0 -}}{{- $where := index . 1 -}}{{- $list := index . 2 -}}
{{- range $r := $list }}
{{- include "vpcsc.context" (list $root $where $r) }}
- projectRef:
    external: {{ $r | quote }}
{{- end }}
{{- end -}}

{{/*
vpcsc.operations: an ingress or egress policy's "to" operations.
*/}}
{{- define "vpcsc.operations" -}}
{{- range $o := . }}
- serviceName: {{ $o.service_name | quote }}
{{- if or $o.method_selectors $o.permission_selectors }}
  methodSelectors:
{{- range $m := ($o.method_selectors | default list) }}
    - method: {{ $m | quote }}
{{- end }}
{{- range $m := ($o.permission_selectors | default list) }}
    - permission: {{ $m | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
vpcsc.perimeterBody: one perimeter's spec or status block (perimeters.tf's
dynamic "spec" and "status"): access levels, resources, restricted
services, the ingress and egress policies it names, and VPC accessible
services.
  dict root, where, s (the block), levels, ingress, egress
*/}}
{{- define "vpcsc.perimeterBody" -}}
{{- $root := .root -}}{{- $where := .where -}}{{- $s := .s -}}
{{- with $s.access_levels }}
accessLevels:
{{- range $l := . }}
  - {{ include "vpcsc.levelRef" (list $root (printf "%s.access_levels" $where) $l $.levels) | nindent 4 | trim }}
{{- end }}
{{- end }}
{{- with $s.resources }}
resources:
{{- include "vpcsc.resources" (list $root (printf "%s.resources" $where) .) | trim | nindent 2 }}
{{- end }}
{{- with $s.restricted_services }}
restrictedServices:
{{- range $r := . }}
{{- include "vpcsc.context" (list $root (printf "%s.restricted_services" $where) $r) }}
  - {{ $r | quote }}
{{- end }}
{{- end }}
{{- with $s.egress_policies }}
egressPolicies:
{{- range $k := . }}
{{- $p := index $.egress $k }}
{{- $pw := printf "egress_policies.%s" (trimPrefix "$egress_policies:" $k) }}
{{- include "kcc.unsupported" (list $root (printf "%s.title" $pw) $p.title "AccessContextManagerServicePerimeter's egress policies have no title") }}
{{- $f := $p.from | default dict }}
{{- include "kcc.unsupported" (list $root (printf "%s.from.access_levels" $pw) $f.access_levels "AccessContextManagerServicePerimeter's egressFrom has no sources") }}
{{- include "kcc.unsupported" (list $root (printf "%s.from.resources" $pw) $f.resources "AccessContextManagerServicePerimeter's egressFrom has no sources") }}
{{- include "kcc.unsupported" (list $root (printf "%s.from.psc_endpoints" $pw) $f.psc_endpoints "AccessContextManagerServicePerimeter's egressFrom has no sources") }}
{{- $t := $p.to | default dict }}
{{- include "kcc.unsupported" (list $root (printf "%s.to.roles" $pw) $t.roles "AccessContextManagerServicePerimeter's egressTo has no roles") }}
  - egressFrom:
{{- with $f.identity_type }}
      identityType: {{ . | quote }}
{{- end }}
{{- with $f.identities }}
      identities:
{{- include "vpcsc.identities" (list $root (printf "%s.from.identities" $pw) .) | trim | nindent 8 }}
{{- end }}
    egressTo:
{{- with $t.external_resources }}
      externalResources:
{{- range $r := . }}
        - {{ $r | quote }}
{{- end }}
{{- end }}
{{- with $t.operations }}
      operations:
{{- include "vpcsc.operations" . | trim | nindent 8 }}
{{- end }}
{{- with $t.resources }}
      resources:
{{- include "vpcsc.resources" (list $root (printf "%s.to.resources" $pw) .) | trim | nindent 8 }}
{{- end }}
{{- end }}
{{- end }}
{{- with $s.ingress_policies }}
ingressPolicies:
{{- range $k := . }}
{{- $p := index $.ingress $k }}
{{- $pw := printf "ingress_policies.%s" (trimPrefix "$ingress_policies:" $k) }}
{{- include "kcc.unsupported" (list $root (printf "%s.title" $pw) $p.title "AccessContextManagerServicePerimeter's ingress policies have no title") }}
{{- $f := $p.from | default dict }}
{{- include "kcc.unsupported" (list $root (printf "%s.from.psc_endpoints" $pw) $f.psc_endpoints "AccessContextManagerServicePerimeter's ingress sources are access levels and resources only") }}
{{- $t := $p.to | default dict }}
{{- include "kcc.unsupported" (list $root (printf "%s.to.roles" $pw) $t.roles "AccessContextManagerServicePerimeter's ingressTo has no roles") }}
  - ingressFrom:
{{- with $f.identity_type }}
      identityType: {{ . | quote }}
{{- end }}
{{- with $f.identities }}
      identities:
{{- include "vpcsc.identities" (list $root (printf "%s.from.identities" $pw) .) | trim | nindent 8 }}
{{- end }}
{{- if or $f.access_levels $f.resources }}
      sources:
{{- range $l := ($f.access_levels | default list) }}
        - accessLevelRef:
            {{- include "vpcsc.levelRef" (list $root (printf "%s.from.access_levels" $pw) $l $.levels) | nindent 12 }}
{{- end }}
{{- with $f.resources }}
{{- include "vpcsc.resources" (list $root (printf "%s.from.resources" $pw) .) | trim | nindent 8 }}
{{- end }}
{{- end }}
    ingressTo:
{{- with $t.operations }}
      operations:
{{- include "vpcsc.operations" . | trim | nindent 8 }}
{{- end }}
{{- with $t.resources }}
      resources:
{{- include "vpcsc.resources" (list $root (printf "%s.to.resources" $pw) .) | trim | nindent 8 }}
{{- end }}
{{- end }}
{{- end }}
{{- with $s.vpc_accessible_services }}
{{- include "kcc.unsupported" (list $root (printf "%s.vpc_accessible_services.allowed_service_patterns" $where) .allowed_service_patterns "AccessContextManagerServicePerimeter's vpcAccessibleServices has no allowedServicePatterns") }}
{{- $enable := ternary true .enable_restriction (kindIs "invalid" .enable_restriction) }}
{{- $all := ternary true .allow_all_restricted_services (kindIs "invalid" .allow_all_restricted_services) }}
{{- $allowed := ternary (list "RESTRICTED-SERVICES") list (and $enable $all) }}
{{- range $r := (.allowed_services | default list) }}
{{- include "vpcsc.context" (list $root (printf "%s.vpc_accessible_services.allowed_services" $where) $r) }}
{{- $allowed = append $allowed $r }}
{{- end }}
vpcAccessibleServices:
  enableRestriction: {{ $enable }}
{{- with ($allowed | uniq) }}
  allowedServices:
{{- range $r := . }}
    - {{ $r | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
vpcsc.condition: one access level condition (access-levels.tf's dynamic
"conditions"): device policy, IP ranges, members (users and service
accounts), negate, regions and required access levels.
  dict root, c (the condition), w (where, for messages), levels
*/}}
{{- define "vpcsc.condition" -}}
{{- $root := .root -}}{{- $c := .c -}}{{- $w := .w -}}
{{- with $c.device_policy }}
devicePolicy:
{{- with .allowed_device_management_levels }}
  allowedDeviceManagementLevels: {{ toJson . }}
{{- end }}
{{- with .allowed_encryption_statuses }}
  allowedEncryptionStatuses: {{ toJson . }}
{{- end }}
  requireAdminApproval: {{ .require_admin_approval }}
  requireCorpOwned: {{ .require_corp_owned }}
{{- if not (kindIs "invalid" .require_screen_lock) }}
  requireScreenLock: {{ .require_screen_lock }}
{{- end }}
{{- with .os_constraints }}
  osConstraints:
{{- range $o := . }}
    - osType: {{ $o.os_type | quote }}
{{- with $o.minimum_version }}
      minimumVersion: {{ . | quote }}
{{- end }}
{{- if not (kindIs "invalid" $o.require_verified_chrome_os) }}
      requireVerifiedChromeOs: {{ $o.require_verified_chrome_os }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- with $c.ip_subnetworks }}
ipSubnetworks: {{ toJson . }}
{{- end }}
{{- with $c.members }}
members:
{{- range $m := . }}
{{- include "vpcsc.context" (list $root (printf "%s.members" $w) $m) }}
{{- if hasPrefix "user:" $m }}
  - user: {{ trimPrefix "user:" $m | quote }}
{{- else if hasPrefix "serviceAccount:" $m }}
  - serviceAccountRef:
      external: {{ $m | quote }}
{{- else }}
{{- include "kcc.unsupported" (list $root (printf "%s.members" $w) "x" (printf "%q: an access level's members are users and service accounts only" $m)) }}
{{- end }}
{{- end }}
{{- end }}
{{- if not (kindIs "invalid" $c.negate) }}
negate: {{ $c.negate }}
{{- end }}
{{- with $c.regions }}
regions: {{ toJson . }}
{{- end }}
{{- with $c.required_access_levels }}
requiredAccessLevels:
{{- range $r := . }}
  - {{ include "vpcsc.levelRef" (list $root (printf "%s.required_access_levels" $w) $r $.levels) | trim }}
{{- end }}
{{- end }}
{{- end -}}
