{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
This chart's own helpers.
*/ -}}

{{/*
vnet.anySet: "true" when a value holds a non-empty leaf anywhere (a string,
a number, a boolean true, or a non-empty list), else "". ignore_body_changes
defaults to empty lists inside maps, which are not a setting.
*/}}
{{- define "vnet.anySet" -}}
{{- if kindIs "map" . -}}
{{- range $_, $v := . -}}{{- include "vnet.anySet" $v -}}{{- end -}}
{{- else if kindIs "slice" . -}}
{{- if gt (len .) 0 -}}true{{- end -}}
{{- else if not (empty .) -}}true
{{- end -}}
{{- end -}}

{{/*
vnet.pow2: 2^n as a decimal string, exact for n up to 80 (Terraform's
numbers are arbitrary precision; an IPv6 pool's size passes int64).
*/}}
{{- define "vnet.pow2" -}}
{{- $n := int . -}}
{{- $big := dict "64" "18446744073709551616" "65" "36893488147419103232" "66" "73786976294838206464" "67" "147573952589676412928" "68" "295147905179352825856" "69" "590295810358705651712" "70" "1180591620717411303424" "71" "2361183241434822606848" "72" "4722366482869645213696" "73" "9444732965739290427392" "74" "18889465931478580854784" "75" "37778931862957161709568" "76" "75557863725914323419136" "77" "151115727451828646838272" "78" "302231454903657293676544" "79" "604462909807314587353088" "80" "1208925819614629174706176" -}}
{{- if hasKey $big (toString $n) -}}{{- index $big (toString $n) -}}
{{- else -}}
{{- $r := 1 -}}{{- range until $n -}}{{- $r = mul $r 2 -}}{{- end -}}{{- $r -}}
{{- end -}}
{{- end -}}

{{/*
vnet.peering: one VirtualNetworksVirtualNetworkPeering spec body, from the
peering module's inputs with prefix "" (the peering) or "reverse_" (the
reverse peering), as modules/peering/main.tf builds each of its three
shapes (full, address space, subnet).
*/}}
{{- define "vnet.peering" -}}
{{- $p := .p -}}{{- $pre := .pre -}}
{{- $get := dict -}}
{{- range $k := list "allow_forwarded_traffic" "allow_gateway_transit" "use_remote_gateways" "do_not_verify_remote_gateways" "enable_only_ipv6_peering" -}}
{{- $_ := set $get $k (eq (index $p (printf "%s%s" $pre $k)) true) -}}
{{- end -}}
{{- range $k := list "allow_virtual_network_access" "peer_complete_vnets" -}}
{{- $_ := set $get $k (ne (index $p (printf "%s%s" $pre $k)) false) -}}
{{- end -}}
allowVirtualNetworkAccess: {{ $get.allow_virtual_network_access }}
allowForwardedTraffic: {{ $get.allow_forwarded_traffic }}
allowGatewayTransit: {{ $get.allow_gateway_transit }}
useRemoteGateways: {{ $get.use_remote_gateways }}
doNotVerifyRemoteGateways: {{ $get.do_not_verify_remote_gateways }}
enableOnlyIPv6Peering: {{ $get.enable_only_ipv6_peering }}
peerCompleteVnets: {{ $get.peer_complete_vnets }}
{{- if eq .shape "address" }}
localAddressSpace:
  addressPrefixes:
    {{- range (index $p (printf "%slocal_peered_address_spaces" $pre)) }}
    - {{ .address_prefix | quote }}
    {{- end }}
remoteAddressSpace:
  addressPrefixes:
    {{- range (index $p (printf "%sremote_peered_address_spaces" $pre)) }}
    - {{ .address_prefix | quote }}
    {{- end }}
{{- else if eq .shape "subnet" }}
localSubnetNames:
  {{- range (index $p (printf "%slocal_peered_subnets" $pre)) }}
  - {{ .subnet_name | quote }}
  {{- end }}
remoteSubnetNames:
  {{- range (index $p (printf "%sremote_peered_subnets" $pre)) }}
  - {{ .subnet_name | quote }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
vnet.peeringShape: "full", "address" or "subnet", as modules/peering/locals.tf
decides, for prefix "" or "reverse_"; "" when none applies.
*/}}
{{- define "vnet.peeringShape" -}}
{{- $p := .p -}}{{- $pre := .pre -}}
{{- if ne (index $p (printf "%speer_complete_vnets" $pre)) false -}}full
{{- else if and (index $p (printf "%slocal_peered_address_spaces" $pre)) (index $p (printf "%sremote_peered_address_spaces" $pre)) -}}address
{{- else if and (index $p (printf "%slocal_peered_subnets" $pre)) (index $p (printf "%sremote_peered_subnets" $pre)) -}}subnet
{{- end -}}
{{- end -}}
