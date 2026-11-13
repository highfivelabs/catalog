{{/*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

cosmos.roleAssignments: the module's role_assignments (or a private
endpoint's) as aso.roleAssignments takes them, as JSON. The module passes
principal_type, condition and condition_version to nothing ("forced to be
here by lint, not supported"), so they are dropped; azurerm sends
principalType ServicePrincipal when skip_service_principal_aad_check is
true.
*/}}
{{- define "cosmos.roleAssignments" -}}
{{- $out := dict -}}
{{- range $k, $r := (. | default dict) -}}
{{- $r2 := omit $r "principal_type" "condition" "condition_version" -}}
{{- if $r.skip_service_principal_aad_check -}}{{- $_ := set $r2 "principal_type" "ServicePrincipal" -}}{{- end -}}
{{- $_ := set $out $k $r2 -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}
