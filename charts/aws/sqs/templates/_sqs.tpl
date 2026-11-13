{{/*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

The sqs chart's own helpers: the queue's name and ARN, and the queue
policy built as Terraform's aws_iam_policy_document builds them (the
helpers are the iam-role chart's, renamed).
*/}}

{{/*
sqs.names: the queue's AWS name, as main.tf derives it (local.name, with
".fifo" for a FIFO queue), with the namePrefix, or names.queue in full.
Returns JSON {queue}.
*/}}
{{- define "sqs.names" -}}
{{- $v := .Values -}}
{{- $fifo := $v.fifo_queue -}}
{{- $sfx := ternary ".fifo" "" (eq (toString $fifo) "true") -}}
{{- $base := trimSuffix ".fifo" ($v.name | default "") -}}
{{- $queue := "" -}}
{{- $set := index ($v.names | default dict) "queue" -}}
{{- if $set -}}
{{- $queue = include "ack.resourceName" (list $ "queue" "queue" "" 80) -}}
{{- else if $base -}}
{{- $queue = printf "%s%s" (include "ack.cloudName" (list $ "queue" $base (sub 80 (len $sfx)))) $sfx -}}
{{- end -}}
{{- toJson (dict "queue" $queue) -}}
{{- end -}}

{{/*
sqs.arn: a queue's ARN, arn:<partition>:sqs:<region>:<account_id>:<name>,
as the module's queue_arn_static output builds it. A chart cannot look
the region or the account up, so both must be values here.
  (list $ $name "why it is needed")
*/}}
{{- define "sqs.arn" -}}
{{- $root := index . 0 -}}{{- $name := index . 1 -}}{{- $why := index . 2 -}}
{{- $v := $root.Values -}}
{{- if not (and $v.account_id $v.region) -}}
{{- fail (printf "sqs: account_id and region are required for %s: the chart writes the queue's ARN itself, and cannot look the account or region up (values.yaml, account_id)" $why) -}}
{{- end -}}
{{- printf "arn:%s:sqs:%s:%s:%s" $v.partition $v.region $v.account_id $name -}}
{{- end -}}

{{/*
sqs.statement: one IAM policy statement as aws_iam_policy_document
writes it, from a dict in the module's shape. Returns JSON.
*/}}
{{- define "sqs.statement" -}}
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
sqs.statements: the statements of one JSON policy document, as a JSON
list (Statement may be one object or a list).
  (list "source_queue_policy_documents[0]" $json)
*/}}
{{- define "sqs.statements" -}}
{{- $what := index . 0 -}}{{- $json := index . 1 -}}
{{- $doc := $json | fromJson -}}
{{- if or (hasKey $doc "Error") (not (hasKey $doc "Statement")) -}}
{{- fail (printf "sqs: %s is not a JSON policy document with a Statement" $what) -}}
{{- end -}}
{{- $st := $doc.Statement -}}
{{- if kindIs "map" $st }}{{ $st = list $st }}{{ end -}}
{{- toJson (dict "s" $st) -}}
{{- end -}}

{{/*
sqs.merge: statements merged into a document's, as aws_iam_policy_document
does: a statement with a Sid replaces the one with the same Sid in place,
any other is appended. Returns JSON {s: [...]}.
*/}}
{{- define "sqs.merge" -}}
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
sqs.policy: a queue policy as main.tf's data.aws_iam_policy_document
builds it: the source documents, the statements (a map, in key order, each
Sid defaulting to its key, each statement's resources defaulting to the
queue's own ARN), then the override documents, merged by Sid. Returns the
JSON, or "" when it has no statement.
  (list $ "queue" $name $sources $statements $overrides)
*/}}
{{- define "sqs.policy" -}}
{{- $root := index . 0 -}}{{- $what := index . 1 -}}{{- $name := index . 2 -}}
{{- $sources := index . 3 | default list -}}{{- $m := index . 4 | default dict -}}{{- $overrides := index . 5 | default list -}}
{{- $doc := list -}}
{{- $sids := dict -}}
{{- range $i, $j := $sources -}}
{{- $st := (include "sqs.statements" (list (printf "source_%s_policy_documents[%d]" $what $i) $j) | fromJson).s -}}
{{- range $s := $st -}}
{{- with get $s "Sid" -}}
{{- if hasKey $sids . -}}
{{- fail (printf "sqs: source_%s_policy_documents: duplicate Sid (%s); the source documents' Sids must be unique" $what .) -}}
{{- end -}}
{{- $_ := set $sids . true -}}
{{- end -}}
{{- end -}}
{{- $doc = (include "sqs.merge" (list $doc $st) | fromJson).s -}}
{{- end -}}
{{- $own := list -}}
{{- range $k := keys $m | sortAlpha -}}
{{- $s := deepCopy (index $m $k | default dict) -}}
{{- $_ := set $s "sid" ($s.sid | default $k) -}}
{{- if kindIs "invalid" $s.resources -}}
{{- $_ := set $s "resources" (list (include "sqs.arn" (list $root $name (printf "%s_policy_statements.%s, which has no resources (the module's default is the queue's own ARN)" $what $k)))) -}}
{{- end -}}
{{- $own = append $own (include "sqs.statement" $s | fromJson) -}}
{{- end -}}
{{- $doc = (include "sqs.merge" (list $doc $own) | fromJson).s -}}
{{- range $i, $j := $overrides -}}
{{- $st := (include "sqs.statements" (list (printf "override_%s_policy_documents[%d]" $what $i) $j) | fromJson).s -}}
{{- $doc = (include "sqs.merge" (list $doc $st) | fromJson).s -}}
{{- end -}}
{{- if $doc -}}
{{- toJson (dict "Version" "2012-10-17" "Statement" $doc) -}}
{{- end -}}
{{- end -}}
