{{/*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

The kms chart's own helpers.
*/}}

{{/*
kms.statement: one IAM policy statement as aws_iam_policy_document writes
it, from a dict {sid, effect, actions, not_actions, resources,
not_resources, principals, not_principals, condition} in the module's
shape. Returns JSON.
*/}}
{{- define "kms.statement" -}}
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
{{- $_ := set $t $x.variable (concat (get $t $x.variable | default list) $vals) -}}
{{- $_ := set $c $x.test $t -}}
{{- end -}}
{{- $_ := set $o "Condition" $c -}}
{{- end -}}
{{- toJson $o -}}
{{- end -}}

{{/*
kms.policy: the key policy, as the module's data.aws_iam_policy_document
builds it (main.tf, "Policy"), as JSON; or "" when the chart sets no
policy: policy unset and the Default statement alone, which is what KMS's
default key policy grants.
*/}}
{{- define "kms.policy" -}}
{{- $v := .Values -}}
{{- if $v.policy -}}
{{- $v.policy -}}
{{- else -}}
{{- $aws := list (dict "type" "AWS") -}}
{{- $grantForAWS := list (dict "test" "Bool" "variable" "kms:GrantIsForAWSResource" "values" (list "true")) -}}
{{- $suffix := ternary "amazonaws.com.cn" "amazonaws.com" (eq $v.partition "aws-cn") -}}
{{- $st := list -}}
{{- $groups := list
  (list "KeyOwner" $v.key_owners (list "kms:*") list)
  (list "KeyAdministration" $v.key_administrators (list "kms:Create*" "kms:Describe*" "kms:Enable*" "kms:List*" "kms:Put*" "kms:Update*" "kms:Revoke*" "kms:Disable*" "kms:Get*" "kms:Delete*" "kms:TagResource" "kms:UntagResource" "kms:ScheduleKeyDeletion" "kms:CancelKeyDeletion" "kms:ReplicateKey" "kms:ImportKeyMaterial") list)
  (list "KeyUsage" $v.key_users (list "kms:Encrypt" "kms:Decrypt" "kms:ReEncrypt*" "kms:GenerateDataKey*" "kms:DescribeKey") list)
  (list "KeyServiceUsage" $v.key_service_users (list "kms:CreateGrant" "kms:ListGrants" "kms:RevokeGrant") $grantForAWS)
  (list "KeyServiceRolesASG" $v.key_service_roles_for_autoscaling (list "kms:Encrypt" "kms:Decrypt" "kms:ReEncrypt*" "kms:GenerateDataKey*" "kms:DescribeKey") list)
  (list "KeyServiceRolesASGPersistentVol" $v.key_service_roles_for_autoscaling (list "kms:CreateGrant") $grantForAWS)
  (list "KeySymmetricEncryption" $v.key_symmetric_encryption_users (list "kms:Decrypt" "kms:DescribeKey" "kms:Encrypt" "kms:GenerateDataKey*" "kms:ReEncrypt*") list)
  (list "KeyHMAC" $v.key_hmac_users (list "kms:DescribeKey" "kms:GenerateMac" "kms:VerifyMac") list)
  (list "KeyAsymmetricPublicEncryption" $v.key_asymmetric_public_encryption_users (list "kms:Encrypt" "kms:Decrypt" "kms:ReEncrypt*" "kms:DescribeKey" "kms:GetPublicKey") list)
  (list "KeyAsymmetricSignVerify" $v.key_asymmetric_sign_verify_users (list "kms:DescribeKey" "kms:GetPublicKey" "kms:Sign" "kms:Verify") list) -}}
{{- range $g := $groups -}}
{{- if index $g 1 -}}
{{- $st = append $st (dict "sid" (index $g 0) "actions" (index $g 2) "resources" (list "*") "principals" (list (dict "type" "AWS" "identifiers" (index $g 1))) "condition" (index $g 3)) -}}
{{- end -}}
{{- end -}}
{{- $needAccount := false -}}
{{- if $v.enable_route53_dnssec -}}
{{- $svc := list (dict "type" "Service" "identifiers" (list (printf "dnssec-route53.%s" $suffix))) -}}
{{- $st = append $st (dict "sid" "Route53DnssecService" "actions" (list "kms:DescribeKey" "kms:GetPublicKey" "kms:Sign") "resources" (list "*") "principals" $svc) -}}
{{- $cond := $grantForAWS -}}
{{- range $src := $v.route53_dnssec_sources | default list -}}
{{- $ids := $src.account_ids | default list -}}
{{- if not $ids }}{{ $needAccount = true }}{{ $ids = list ($v.account_id | default "") }}{{ end -}}
{{- $cond = append $cond (dict "test" "StringEquals" "variable" "aws:SourceAccount" "values" $ids) -}}
{{- end -}}
{{- range $src := $v.route53_dnssec_sources | default list -}}
{{- $cond = append $cond (dict "test" "ArnLike" "variable" "aws:SourceArn" "values" (list ($src.hosted_zone_arn | default (printf "arn:%s:route53:::hostedzone/*" $v.partition)))) -}}
{{- end -}}
{{- $st = append $st (dict "sid" "Route53DnssecGrant" "actions" (list "kms:CreateGrant") "resources" (list "*") "principals" $svc "condition" $cond) -}}
{{- end -}}
{{- range $s := $v.key_statements | default list -}}
{{- $st = append $st $s -}}
{{- end -}}
{{- if and $v.enable_default_policy (gt (len $st) 0) -}}
{{- $needAccount = true -}}
{{- $st = prepend $st (dict "sid" "Default" "actions" (list "kms:*") "resources" (list "*") "principals" (list (dict "type" "AWS" "identifiers" (list (printf "arn:%s:iam::%s:root" $v.partition ($v.account_id | default "")))))) -}}
{{- end -}}
{{- if and $needAccount (not $v.account_id) -}}
{{- fail "kms: account_id is required for this key policy: the module puts the key's account in it (the Default statement's root principal, or a DNSSEC source without account_ids), and a chart cannot look the account up (values.yaml, account_id)" -}}
{{- end -}}
{{- if $st -}}
{{- $out := list -}}
{{- range $s := $st }}{{ $out = append $out (include "kms.statement" $s | fromJson) }}{{ end -}}
{{- toJson (dict "Version" "2012-10-17" "Statement" $out) -}}
{{- end -}}
{{- end -}}
{{- end -}}
