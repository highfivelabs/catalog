{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Ported from terraform-google-org-policy modules/org_policy_v2/main.tf
(v7.4.0), Copyright 2025 Google LLC, Apache-2.0: the module's locals, and
the rule blocks boolean_constraints.tf and list_constraints.tf repeat.
*/ -}}

{{/*
orgpolicy.check: the checks every template makes before it renders.
*/}}
{{- define "orgpolicy.check" -}}
{{- $v := .Values -}}
{{- if empty (toString ($v.policy_root_id | default "")) -}}
{{- fail (printf "%s: policy_root_id is needed: the ID of the %s the policy is set on" .Chart.Name $v.policy_root) -}}
{{- end -}}
{{- range $i, $r := ($v.rules | default list) -}}
{{- if gt (len ($r.conditions | default list)) 1 -}}
{{- fail (printf "%s: rules[%d] has %d conditions: a rule takes at most one (the provider's rules.condition holds one, and so does OrgPolicyPolicy's)" $.Chart.Name $i (len $r.conditions)) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
orgpolicy.parent: the parent reference of a policy on "<plural>/<id>"
(organizations/123, folders/456, projects/my-project), as JSON.
*/}}
{{- define "orgpolicy.parent" -}}
{{- $kind := index (splitList "/" .) 0 -}}
{{- $field := get (dict "organizations" "organizationRef" "folders" "folderRef" "projects" "projectRef") $kind -}}
{{- toJson (dict $field (dict "external" .)) -}}
{{- end -}}

{{/*
orgpolicy.parameters: a rule's parameters (the module's JSON string) as the
OrgPolicyPolicy parameters object, as JSON. Config Connector v1.160.0 knows
the parameters below; another is refused, naming the gap.
  (list $ $ruleIndex $parametersString)
*/}}
{{- define "orgpolicy.parameters" -}}
{{- $root := index . 0 -}}{{- $i := index . 1 -}}{{- $s := index . 2 -}}
{{- $known := list "allowAnyGKEPath" "allowPaths" "allowedAWSAccountIDs" "allowedDataSources" "allowedDomains" "allowedEgressFQDNs" "allowedEncryptions" "allowedMemberSubjects" "allowedParents" "allowedPreviewFeatures" "allowedPrincipalSets" "allowedProviders" "allowedRetentionDurationSeconds" "allowedRetentionPeriods" "allowedSchemes" "allowedServiceList" "allowedServices" "defaultAWSProvider" "defaultXMLServiceProvider" "deniedEditions" "enforcedProjects" "minimumDestroyScheduleDurationInDays" "nonFIPSMachineTypes" -}}
{{- if not (regexMatch "^\\s*\\{" $s) -}}
{{- fail (printf "%s: rules[%d].parameters must be a JSON object, as jsonencode({...}) writes it" $root.Chart.Name $i) -}}
{{- end -}}
{{- $p := fromJson $s -}}
{{- range $k, $_ := $p -}}
{{- if not (has $k $known) -}}
{{- include "kcc.unsupported" (list $root "rules.parameters" $k (printf "OrgPolicyPolicy's rule parameters have no %s (Config Connector v1.160.0 knows %s)" $k (join ", " $known))) -}}
{{- end -}}
{{- end -}}
{{- toJson $p -}}
{{- end -}}

{{/*
orgpolicy.rules: the module's local.rules (dry: false) or
local.rules_dry_run (dry: true), each rule as the spec's rules entry for a
boolean or a list constraint, as JSON {"rules": [...]}.
  (dict "root" $ "dry" false)
*/}}
{{- define "orgpolicy.rules" -}}
{{- $root := .root -}}{{- $v := $root.Values -}}
{{- $out := list -}}
{{- range $i, $r := ($v.rules | default list) -}}
{{- if eq (and (kindIs "bool" $r.dry_run) $r.dry_run) $.dry -}}
{{- $allow := $r.allow | default list -}}
{{- $deny := $r.deny | default list -}}
{{- /* local.rules: enforcement is null when allow or deny is set. */ -}}
{{- $isBool := and (not (or $allow $deny)) (kindIs "bool" $r.enforcement) -}}
{{- $enforcement := and $isBool $r.enforcement -}}
{{- $rule := dict -}}
{{- $cond := dict -}}
{{- with first ($r.conditions | default list) -}}
{{- $c := . -}}
{{- range $k := list "description" "expression" "location" "title" -}}
{{- $val := toString (get $c $k | default "") -}}
{{- if $val }}{{ $_ := set $cond $k $val }}{{ end -}}
{{- end -}}
{{- end -}}
{{- if $cond }}{{ $_ := set $rule "condition" $cond }}{{ end -}}
{{- if eq $v.policy_type "boolean" -}}
{{- /* enforce = enforcement != false ? "TRUE" : "FALSE" */ -}}
{{- $_ := set $rule "enforce" (not (and $isBool (not $enforcement))) -}}
{{- with $r.parameters -}}
{{- $_ := set $rule "parameters" (include "orgpolicy.parameters" (list $root $i .) | fromJson) -}}
{{- end -}}
{{- else -}}
{{- /* allow_all = enforcement == false; deny_all = enforcement == true */ -}}
{{- if $isBool -}}
{{- if $enforcement }}{{ $_ := set $rule "denyAll" true }}{{ else }}{{ $_ := set $rule "allowAll" true }}{{ end -}}
{{- end -}}
{{- if and $allow (not $deny) }}{{ $_ := set $rule "values" (dict "allowedValues" $allow) }}{{ end -}}
{{- if and $deny (not $allow) }}{{ $_ := set $rule "values" (dict "deniedValues" $deny) }}{{ end -}}
{{- end -}}
{{- $out = append $out $rule -}}
{{- end -}}
{{- end -}}
{{- toJson (dict "rules" $out) -}}
{{- end -}}

{{/*
orgpolicy.policy: one OrgPolicyPolicy.
  root    $
  name    the Kubernetes name
  id      the hfl.dev/id
  parent  "<plural>/<id>" (organizations/123, folders/456, projects/p)
  spec    the policy's spec (a dict), or empty for none
  dryRun  the policy's dryRunSpec (a dict), or empty for none
*/}}
{{- define "orgpolicy.policy" -}}
---
apiVersion: orgpolicy.cnrm.cloud.google.com/v1beta1
kind: OrgPolicyPolicy
metadata:
  {{- include "kcc.metadata" (dict "root" .root "name" .name "id" .id "abandon" (include "kcc.abandon" .root)) | nindent 2 }}
spec:
  {{- include "orgpolicy.parent" .parent | fromJson | toYaml | nindent 2 }}
  resourceID: {{ .root.Values.constraint | quote }}
{{- with .spec }}
  spec:
    {{- toYaml . | nindent 4 }}
{{- end }}
{{- with .dryRun }}
  dryRunSpec:
    {{- toYaml . | nindent 4 }}
{{- end }}
{{- end -}}
