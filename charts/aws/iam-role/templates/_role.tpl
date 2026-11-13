{{/*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

The iam-role chart's own helpers: IAM policy documents built as
Terraform's aws_iam_policy_document builds them.
*/}}

{{/*
iamrole.statement: one IAM policy statement as aws_iam_policy_document
writes it, from a dict {sid, effect, actions, not_actions, resources,
not_resources, principals, not_principals, condition} in the module's
shape. Returns JSON.
*/}}
{{- define "iamrole.statement" -}}
{{- $s := . -}}
{{- $o := dict "Effect" ($s.effect | default "Allow") -}}
{{- with $s.sid }}{{ $_ := set $o "Sid" . }}{{ end -}}
{{- with $s.actions }}{{ $_ := set $o "Action" . }}{{ end -}}
{{- with $s.not_actions }}{{ $_ := set $o "NotAction" . }}{{ end -}}
{{- with $s.resources }}{{ $_ := set $o "Resource" . }}{{ end -}}
{{- with $s.not_resources }}{{ $_ := set $o "NotResource" . }}{{ end -}}
{{- range $f := list (list "principals" "Principal") (list "not_principals" "NotPrincipal") -}}
{{- $ps := index $s (index $f 0) | default list -}}
{{- if $ps -}}
{{- $m := dict -}}
{{- range $p := $ps -}}
{{- $_ := set $m $p.type (concat (get $m $p.type | default list) $p.identifiers) -}}
{{- end -}}
{{- $_ := set $o (index $f 1) $m -}}
{{- end -}}
{{- end -}}
{{- if $s.condition -}}
{{- $c := dict -}}
{{- range $x := $s.condition -}}
{{- $t := get $c $x.test | default dict -}}
{{- $vals := list -}}
{{- range $x.values }}{{ $vals = append $vals (toString .) }}{{ end -}}
{{- $_ := set $t $x.variable (concat (get $t $x.variable | default list) $vals | uniq) -}}
{{- $_ := set $c $x.test $t -}}
{{- end -}}
{{- $_ := set $o "Condition" $c -}}
{{- end -}}
{{- toJson $o -}}
{{- end -}}

{{/*
iamrole.statements: the statements of one JSON policy document, as a JSON
list (Statement may be one object or a list).
  (list $ "source_trust_policy_documents[0]" $json)
*/}}
{{- define "iamrole.statements" -}}
{{- $root := index . 0 -}}{{- $what := index . 1 -}}{{- $json := index . 2 -}}
{{- $doc := $json | fromJson -}}
{{- if or (hasKey $doc "Error") (not (hasKey $doc "Statement")) -}}
{{- fail (printf "%s: %s is not a JSON policy document with a Statement" $root.Chart.Name $what) -}}
{{- end -}}
{{- $st := $doc.Statement -}}
{{- if kindIs "map" $st }}{{ $st = list $st }}{{ end -}}
{{- toJson (dict "s" $st) -}}
{{- end -}}

{{/*
iamrole.merge: statements (a list of dicts) merged into a document's, as
aws_iam_policy_document's Merge does: a statement with a Sid replaces the
one with the same Sid in place, any other is appended. Returns JSON {s: [...]}.
  (list $existing $new)
*/}}
{{- define "iamrole.merge" -}}
{{- $out := index . 0 -}}
{{- range $n := index . 1 -}}
{{- $sid := get $n "Sid" | default "" -}}
{{- $done := false -}}
{{- if $sid -}}
{{- $next := list -}}
{{- range $e := $out -}}
{{- if and (not $done) (eq (get $e "Sid" | default "") $sid) -}}
{{- $next = append $next $n -}}{{- $done = true -}}
{{- else -}}
{{- $next = append $next $e -}}
{{- end -}}
{{- end -}}
{{- $out = $next -}}
{{- end -}}
{{- if not $done }}{{ $out = append $out $n }}{{ end -}}
{{- end -}}
{{- toJson (dict "s" $out) -}}
{{- end -}}

{{/*
iamrole.document: a policy document as aws_iam_policy_document builds it
from source_policy_documents, its statement blocks and
override_policy_documents (in that order, merged by Sid). Returns the JSON,
or "" when it has no statement.
  (list $ "trust" $sources $statements $overrides)
  $statements: dicts in the module's shape (iamrole.statement)
*/}}
{{- define "iamrole.document" -}}
{{- $root := index . 0 -}}{{- $what := index . 1 -}}
{{- $sources := index . 2 | default list -}}{{- $blocks := index . 3 -}}{{- $overrides := index . 4 | default list -}}
{{- $doc := list -}}
{{- $sids := dict -}}
{{- range $i, $j := $sources -}}
{{- $st := (include "iamrole.statements" (list $root (printf "source_%s_policy_documents[%d]" $what $i) $j) | fromJson).s -}}
{{- range $s := $st -}}
{{- with get $s "Sid" -}}
{{- if hasKey $sids . -}}
{{- fail (printf "%s: source_%s_policy_documents: duplicate Sid (%s); the source documents' Sids must be unique" $root.Chart.Name $what .) -}}
{{- end -}}
{{- $_ := set $sids . true -}}
{{- end -}}
{{- end -}}
{{- $doc = (include "iamrole.merge" (list $doc $st) | fromJson).s -}}
{{- end -}}
{{- $own := list -}}
{{- range $s := $blocks }}{{ $own = append $own (include "iamrole.statement" $s | fromJson) }}{{ end -}}
{{- $doc = (include "iamrole.merge" (list $doc $own) | fromJson).s -}}
{{- range $i, $j := $overrides -}}
{{- $st := (include "iamrole.statements" (list $root (printf "override_%s_policy_documents[%d]" $what $i) $j) | fromJson).s -}}
{{- $doc = (include "iamrole.merge" (list $doc $st) | fromJson).s -}}
{{- end -}}
{{- if $doc -}}
{{- toJson (dict "Version" "2012-10-17" "Statement" $doc) -}}
{{- end -}}
{{- end -}}

{{/*
iamrole.permissions: a map of statements in the module's shape
(trust_policy_permissions, inline_policy_permissions), in key order, each
Sid defaulting to its key. Returns JSON {s: [...]}.
*/}}
{{- define "iamrole.permissions" -}}
{{- $m := . | default dict -}}
{{- $out := list -}}
{{- range $k := keys $m | sortAlpha -}}
{{- $s := deepCopy (index $m $k | default dict) -}}
{{- $_ := set $s "sid" ($s.sid | default $k) -}}
{{- $out = append $out $s -}}
{{- end -}}
{{- toJson (dict "s" $out) -}}
{{- end -}}

{{/*
iamrole.trust: the trust policy's statement blocks, as main.tf's
data.aws_iam_policy_document.this writes them: generic OIDC (one per
provider), GitHub OIDC, Bitbucket OIDC, SAML, then
trust_policy_permissions. Returns JSON {s: [...]} of dicts in the module's
shape.
*/}}
{{- define "iamrole.trust" -}}
{{- $v := .Values -}}
{{- $chart := .Chart.Name -}}
{{- $st := list -}}
{{- $conds := $v.trust_policy_conditions | default list -}}
{{- $web := list "sts:TagSession" "sts:AssumeRoleWithWebIdentity" -}}
{{- $acct := $v.account_id | default "" -}}
{{- $providers := list -}}
{{- range $u := $v.oidc_provider_urls | default list }}{{ $providers = append $providers (replace "https://" "" $u) }}{{ end -}}
{{- $needAccount := false -}}
{{- if $v.enable_oidc -}}
{{- range $p := $providers -}}
{{- $c := list -}}
{{- with $v.oidc_subjects }}{{ $c = append $c (dict "test" "StringEquals" "variable" (printf "%s:sub" $p) "values" .) }}{{ end -}}
{{- with $v.oidc_wildcard_subjects }}{{ $c = append $c (dict "test" "StringLike" "variable" (printf "%s:sub" $p) "values" .) }}{{ end -}}
{{- with $v.oidc_audiences }}{{ $c = append $c (dict "test" "StringEquals" "variable" (printf "%s:aud" $p) "values" .) }}{{ end -}}
{{- $a := $v.oidc_account_id | default $acct -}}
{{- if not $v.oidc_account_id }}{{ $needAccount = true }}{{ end -}}
{{- $st = append $st (dict "actions" $web "principals" (list (dict "type" "Federated" "identifiers" (list (printf "arn:%s:iam::%s:oidc-provider/%s" $v.partition $a $p)))) "condition" (concat $c $conds)) -}}
{{- end -}}
{{- end -}}
{{- if $v.enable_github_oidc -}}
{{- $needAccount = true -}}
{{- $gh := $v.github_provider -}}
{{- $c := list (dict "test" "ForAllValues:StringEquals" "variable" (printf "%s:iss" $gh) "values" (list (printf "https://%s" $gh))) (dict "test" "ForAllValues:StringEquals" "variable" (printf "%s:aud" $gh) "values" ($v.oidc_audiences | default (list "sts.amazonaws.com"))) -}}
{{- with $v.oidc_subjects }}{{ $s := list }}{{ range . }}{{ $s = append $s (printf "repo:%s" (trimPrefix "repo:" .)) }}{{ end }}{{ $c = append $c (dict "test" "StringEquals" "variable" (printf "%s:sub" $gh) "values" $s) }}{{ end -}}
{{- with $v.oidc_wildcard_subjects }}{{ $s := list }}{{ range . }}{{ $s = append $s (printf "repo:%s" (trimPrefix "repo:" .)) }}{{ end }}{{ $c = append $c (dict "test" "StringLike" "variable" (printf "%s:sub" $gh) "values" $s) }}{{ end -}}
{{- $st = append $st (dict "sid" "GithubOidcAuth" "actions" $web "principals" (list (dict "type" "Federated" "identifiers" (list (printf "arn:%s:iam::%s:oidc-provider/%s" $v.partition $acct $gh)))) "condition" (concat $c $conds)) -}}
{{- end -}}
{{- if $v.enable_bitbucket_oidc -}}
{{- $needAccount = true -}}
{{- if not $providers -}}
{{- fail (printf "%s: enable_bitbucket_oidc needs oidc_provider_urls: the module trusts the first of them" $chart) -}}
{{- end -}}
{{- $bb := first $providers -}}
{{- $c := list (dict "test" "ForAllValues:StringEquals" "variable" (printf "%s:aud" $bb) "values" ($v.oidc_audiences | default (list "sts.amazonaws.com"))) -}}
{{- with $v.oidc_subjects }}{{ $c = append $c (dict "test" "StringEquals" "variable" (printf "%s:sub" $bb) "values" .) }}{{ end -}}
{{- with $v.oidc_wildcard_subjects }}{{ $c = append $c (dict "test" "StringLike" "variable" (printf "%s:sub" $bb) "values" .) }}{{ end -}}
{{- $st = append $st (dict "sid" "BitbucketOidcAuth" "actions" $web "principals" (list (dict "type" "Federated" "identifiers" (list (printf "arn:%s:iam::%s:oidc-provider/%s" $v.partition $acct $bb)))) "condition" (concat $c $conds)) -}}
{{- end -}}
{{- if $v.enable_saml -}}
{{- $actions := concat (list "sts:TagSession" "sts:AssumeRoleWithSAML") ($v.saml_trust_actions | default list) | uniq | compact -}}
{{- $st = append $st (dict "actions" $actions "principals" (list (dict "type" "Federated" "identifiers" ($v.saml_provider_ids | default list))) "condition" (concat (list (dict "test" "StringEquals" "variable" "SAML:aud" "values" ($v.saml_endpoints | default list))) $conds)) -}}
{{- end -}}
{{- $st = concat $st (include "iamrole.permissions" $v.trust_policy_permissions | fromJson).s -}}
{{- if and $needAccount (not $acct) -}}
{{- fail (printf "%s: account_id is required for this trust policy: the module puts the role's account in the OIDC provider's ARN (enable_oidc without oidc_account_id, enable_github_oidc, enable_bitbucket_oidc), and a chart cannot look the account up (values.yaml, account_id)" $chart) -}}
{{- end -}}
{{- toJson (dict "s" $st) -}}
{{- end -}}
