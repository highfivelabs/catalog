{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Helpers for the port of terraform-google-network
modules/hierarchical-firewall-policy (v18.3.1).
*/ -}}

{{/*
hfp.refused: what Config Connector v1.160.0 cannot carry (docs/design.md,
"What Config Connector cannot express is refused, by name"); listed in
upstream.yaml under refused. Renders nothing.
*/}}
{{- define "hfp.refused" -}}
{{- range $i, $r := (.Values.rules | default list) -}}
{{- $m := $r.match | default dict -}}
{{- include "kcc.unsupported" (list $ "rules.match.src_networks" $m.src_networks "ComputeFirewallPolicyRule's match has no srcNetworks") -}}
{{- include "kcc.unsupported" (list $ "rules.match.src_network_scope" $m.src_network_scope "ComputeFirewallPolicyRule's match has no srcNetworkScope") -}}
{{- include "kcc.unsupported" (list $ "rules.match.dest_network_scope" $m.dest_network_scope "ComputeFirewallPolicyRule's match has no destNetworkScope") -}}
{{- end -}}
{{- end -}}
