{{/*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

The eks-pod-identity chart's own helpers: IAM policy documents built as
Terraform's aws_iam_policy_document builds them (the sqs chart's helpers,
renamed).
*/}}

{{/*
epi.statement: one IAM policy statement as aws_iam_policy_document
writes it, from a dict in the module's shape. Returns JSON.
*/}}
{{- define "epi.statement" -}}
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
{{- $conds := concat ($s.condition | default list) ($s.conditions | default list) -}}
{{- if $conds -}}
{{- $c := dict -}}
{{- range $x := $conds -}}
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
epi.statements: the statements of one JSON policy document, as a JSON
list (Statement may be one object or a list).
  (list "source_queue_policy_documents[0]" $json)
*/}}
{{- define "epi.statements" -}}
{{- $what := index . 0 -}}{{- $json := index . 1 -}}
{{- $doc := $json | fromJson -}}
{{- if or (hasKey $doc "Error") (not (hasKey $doc "Statement")) -}}
{{- fail (printf "eks-pod-identity: %s is not a JSON policy document with a Statement" $what) -}}
{{- end -}}
{{- $st := $doc.Statement -}}
{{- if kindIs "map" $st }}{{ $st = list $st }}{{ end -}}
{{- toJson (dict "s" $st) -}}
{{- end -}}

{{/*
epi.merge: statements merged into a document's, as aws_iam_policy_document
does: a statement with a Sid replaces the one with the same Sid in place,
any other is appended. Returns JSON {s: [...]}.
*/}}
{{- define "epi.merge" -}}
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
epi.document: a policy document as main.tf's aws_iam_policy_document
builds it: the source documents, the statements (a list, each in the
module's shape), then the override documents, merged by Sid. Returns the
JSON, or "" when it has no statement.
  (list "custom" $sources $statements $overrides)
*/}}
{{- define "epi.document" -}}
{{- $what := index . 0 -}}
{{- $sources := index . 1 | default list -}}{{- $stmts := index . 2 | default list -}}{{- $overrides := index . 3 | default list -}}
{{- $doc := list -}}
{{- range $i, $j := $sources -}}
{{- $st := (include "epi.statements" (list (printf "source_policy_documents[%d]" $i) $j) | fromJson).s -}}
{{- $doc = (include "epi.merge" (list $doc $st) | fromJson).s -}}
{{- end -}}
{{- $own := list -}}
{{- range $s := $stmts -}}
{{- $own = append $own (include "epi.statement" $s | fromJson) -}}
{{- end -}}
{{- $doc = (include "epi.merge" (list $doc $own) | fromJson).s -}}
{{- range $i, $j := $overrides -}}
{{- $st := (include "epi.statements" (list (printf "override_policy_documents[%d]" $i) $j) | fromJson).s -}}
{{- $doc = (include "epi.merge" (list $doc $st) | fromJson).s -}}
{{- end -}}
{{- if $doc -}}
{{- toJson (dict "Version" "2012-10-17" "Statement" $doc) -}}
{{- end -}}
{{- end -}}
