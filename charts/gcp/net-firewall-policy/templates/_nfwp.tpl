{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Helpers for the port of cloud-foundation-fabric modules/net-firewall-policy
(v60.0.0), Copyright 2024 Google LLC, Apache-2.0.
*/ -}}

{{/*
nfwp.rules: main.tf's local.rules (mirror false) or local.mirroring_rules
(mirror true), as JSON: the factory's rules (factory.tf, its CIDR names
expanded from factories_data.cidrs) and the variables' rules, keyed
"<direction>/<name>" ("mirror/<direction>/<name>" for mirroring rules),
each with its name, direction, and fabric's defaults (action allow for
ingress, deny for egress, mirror for mirroring; disabled false;
layer4_configs [{protocol: all}]).
  {{ include "nfwp.rules" (list $ false) | fromJson }}
*/}}
{{- define "nfwp.rules" -}}
{{- $root := index . 0 -}}{{- $mirror := index . 1 -}}
{{- $v := $root.Values -}}
{{- $fd := $v.factories_data | default dict -}}
{{- $cidrs := $fd.cidrs | default dict -}}
{{- $out := dict -}}
{{- range $source := list "factory" "variables" -}}
{{- range $dir := list "egress" "ingress" -}}
{{- $var := printf "%s_%srules" $dir (ternary "mirroring_" "" $mirror) -}}
{{- $set := ternary (index $fd $var) (index $v $var) (eq $source "factory") | default dict -}}
{{- range $name, $r := $set -}}
{{- $m := deepCopy ($r.match | default dict) -}}
{{- if eq $source "factory" -}}
{{- range $f := list "destination_ranges" "source_ranges" -}}
{{- if not (kindIs "invalid" (index $m $f)) -}}
{{- $expanded := list -}}
{{- range $x := index $m $f -}}
{{- if hasKey $cidrs $x }}{{ $expanded = concat $expanded (index $cidrs $x) }}{{ else }}{{ $expanded = append $expanded $x }}{{ end -}}
{{- end -}}
{{- $_ := set $m $f $expanded -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $l4 := list (dict "protocol" "all") -}}
{{- if not (kindIs "invalid" $m.layer4_configs) -}}
{{- $l4 = list -}}
{{- range $c := $m.layer4_configs -}}
{{- $l4 = append $l4 (dict "protocol" ($c.protocol | default "all") "ports" $c.ports) -}}
{{- end -}}
{{- end -}}
{{- $_ := set $m "layer4_configs" $l4 -}}
{{- $action := $r.action -}}
{{- if kindIs "invalid" $action -}}
{{- $action = ternary "mirror" (ternary "allow" "deny" (eq $dir "ingress")) $mirror -}}
{{- end -}}
{{- $rule := merge (dict "name" $name "direction" (upper $dir) "action" $action "match" $m "disabled" (ternary false $r.disabled (kindIs "invalid" $r.disabled))) (omit $r "match" "action" "disabled") -}}
{{- $_ := set $out (printf "%s%s/%s" (ternary "mirror/" "" $mirror) $dir $name) $rule -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/*
nfwp.list: a match field ("srcIPRanges") from a list, distinct, or nothing
when the list is null or empty.
  {{ include "nfwp.list" (list "srcIPRanges" $list 4) }}
*/}}
{{- define "nfwp.list" -}}
{{- $name := index . 0 -}}{{- $items := index . 1 -}}{{- $indent := index . 2 -}}
{{- if $items }}
{{ printf "%s:" $name | indent $indent }}
{{- range $x := (uniq $items) }}
{{ printf "- %s" ($x | toString | quote) | indent $indent }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
nfwp.l4: a rule's layer4Configs.
*/}}
{{- define "nfwp.l4" -}}
{{- $l4 := index . 0 -}}{{- $indent := index . 1 -}}
{{ "layer4Configs:" | indent $indent }}{{ if not $l4 }} []{{ end }}
{{- range $c := $l4 }}
{{ printf "- ipProtocol: %s" ($c.protocol | quote) | indent $indent }}
{{- with $c.ports }}
{{ "  ports:" | indent $indent }}
{{- range $p := . }}
{{ printf "    - %s" ($p | toString | quote) | indent $indent }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}
