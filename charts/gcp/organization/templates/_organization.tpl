{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Helpers for the port of cloud-foundation-fabric modules/organization
(v60.0.0), Copyright 2025 Google LLC, Apache-2.0.
*/ -}}

{{/* organization.number: the organization's number, from organization_id
(organizations/N, fabric's check). The chart never makes an organization:
everything it renders goes on the one organization_id names. */}}
{{- define "organization.number" -}}
{{- $id := toString (.Values.organization_id | default "") -}}
{{- if not (regexMatch "^organizations/[0-9]+$" $id) -}}
{{- fail "organization: The organization_id must in the form organizations/nnn." -}}
{{- end -}}
{{- trimPrefix "organizations/" $id -}}
{{- end -}}

{{/* organization.id: organizations/N, the form Config Connector's direct
controllers take in organizationRef.external. */}}
{{- define "organization.id" -}}
organizations/{{ include "organization.number" . }}
{{- end -}}

{{/* organization.ref: the organization as an organizationRef. */}}
{{- define "organization.ref" -}}
external: {{ include "organization.id" . | quote }}
{{- end -}}

{{/* organization.iamRef: the organization as an IAM resourceRef (its
number, as Config Connector's IAM kinds take it). */}}
{{- define "organization.iamRef" -}}
kind: Organization
external: {{ include "organization.number" . | quote }}
{{- end -}}

{{/* organization.tagIAM: a tag key's or value's IAM, as the module-level
IAM variables (kcc.iam); conditions are refused, since tag keys and values
take none. Arguments: root, what (the variable path, for messages), base,
idPrefix, ref (the resourceRef), v (iam, iam_bindings,
iam_bindings_additive). The project chart's project.tagIAM. */}}
{{- define "organization.tagIAM" -}}
{{- $root := .root -}}
{{- range $k, $b := (.v.iam_bindings | default dict) -}}
{{- include "kcc.unsupported" (list $root (printf "%s.iam_bindings.%s.condition" $.what $k) $b.condition "tag keys and values take no IAM conditions") -}}
{{- end -}}
{{- range $k, $b := (.v.iam_bindings_additive | default dict) -}}
{{- include "kcc.unsupported" (list $root (printf "%s.iam_bindings_additive.%s.condition" $.what $k) $b.condition "tag keys and values take no IAM conditions") -}}
{{- end -}}
{{- include "kcc.iam" (dict "root" $root "base" .base "idPrefix" .idPrefix "resourceRef" .ref "v" (dict "iam" (.v.iam | default dict) "iam_bindings" (.v.iam_bindings | default dict) "iam_bindings_additive" (.v.iam_bindings_additive | default dict))) -}}
{{- end -}}

{{/* organization.context: refuse a fabric $context lookup in a value
(Bundt replaces them with ${...} expressions). The vpc-sc chart's
vpcsc.context. */}}
{{- define "organization.context" -}}
{{- $root := index . 0 -}}{{- $where := index . 1 -}}{{- $value := index . 2 -}}
{{- if hasPrefix "$" (toString $value) -}}
{{- include "kcc.unsupported" (list $root "context" "x" (printf "%s %q is a fabric $context lookup; Bundt replaces them with ${...} expressions and valueFrom in the component's inputs" $where $value)) -}}
{{- end -}}
{{- end -}}

{{/* organization.levelName: an access level's name: its key, or, with a
namePrefix, <namePrefix>_<key> ("-" becomes "_": access level names take
letters, digits and "_", at most 50). The vpc-sc chart's vpcsc.shortName. */}}
{{- define "organization.levelName" -}}
{{- $root := index . 0 -}}{{- $key := index . 1 -}}
{{- $p := include "kcc.namePrefix" $root | trimSuffix "-" -}}
{{- if $p -}}
{{- if not (regexMatch "^[a-z]" $p) -}}
{{- fail (printf "organization: access level name %q must start with a letter, and namePrefix %q starts with a digit" (printf "%s_%s" $p $key) $p) -}}
{{- end -}}
{{- $name := printf "%s_%s" (replace "-" "_" $p) $key -}}
{{- if gt (len $name) 50 -}}
{{- fail (printf "organization: access level name %q is %d characters, more than the 50 the cloud allows; namePrefix %q is %d of them (with its \"_\"): shorten the namePrefix or the name" $name (len $name) $p (add1 (len $p))) -}}
{{- end -}}
{{- $name -}}
{{- else -}}
{{- $key -}}
{{- end -}}
{{- end -}}

{{/* organization.levelRef: a reference to an access level:
"$access_levels:<NAME>" is this chart's level <NAME> (fabric's
local.ctx_access_levels), by its object's name; anything else is an access
level's resource name (accessPolicies/<policy>/accessLevels/<name>),
external. The vpc-sc chart's vpcsc.levelRef. */}}
{{- define "organization.levelRef" -}}
{{- $root := index . 0 -}}{{- $where := index . 1 -}}{{- $ref := toString (index . 2) -}}
{{- if hasPrefix "$access_levels:" $ref -}}
{{- $k := trimPrefix "$access_levels:" $ref -}}
{{- if not (hasKey ($root.Values.access_levels | default dict) $k) -}}
{{- fail (printf "organization: %s: access level %q is not defined in access_levels" $where $k) -}}
{{- end -}}
name: {{ include "kcc.name" (list $root.Release.Name "level" $k) }}
{{- else -}}
{{- include "organization.context" (list $root $where $ref) -}}
external: {{ $ref | quote }}
{{- end -}}
{{- end -}}
