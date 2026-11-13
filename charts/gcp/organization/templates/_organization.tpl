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
number, as Config Connector's IAM kinds take it). The apiVersion is needed:
without it Config Connector cannot find the Organization's service mapping
(found in the fake cloud, 2026-11-13). */}}
{{- define "organization.iamRef" -}}
apiVersion: resourcemanager.cnrm.cloud.google.com/v1beta1
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
