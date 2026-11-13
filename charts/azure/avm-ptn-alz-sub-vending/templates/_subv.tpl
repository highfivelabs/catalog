{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
This chart's own helpers.
*/ -}}

{{/*
subv.uuidv5: Terraform's uuidv5("url", .), RFC 4122 version 5 in the URL
namespace (6ba7b811-9dad-11d1-80b4-00c04fd430c8, here its 16 bytes in
base64): the SHA-1 of the namespace's bytes and the name, its version
nibble set to 5 and its variant bits to 10. The module names peerings,
hub connections and role assignments with it.
*/}}
{{- define "subv.uuidv5" -}}
{{- $h := sha1sum (printf "%s%s" (b64dec "a6e4EZ2tEdGAtADAT9QwyA==") .) -}}
{{- $variant := dict "0" "8" "1" "9" "2" "a" "3" "b" "4" "8" "5" "9" "6" "a" "7" "b" "8" "8" "9" "9" "a" "a" "b" "b" "c" "8" "d" "9" "e" "a" "f" "b" -}}
{{- printf "%s-%s-5%s-%s%s-%s" (substr 0 8 $h) (substr 8 12 $h) (substr 13 16 $h) (get $variant (substr 16 17 $h)) (substr 17 20 $h) (substr 20 32 $h) -}}
{{- end -}}

{{/*
subv.pow2: 2^n as a decimal string, exact for n up to 80 (an IPv6 pool's
size passes int64): the number of addresses of an IPAM prefix length.
*/}}
{{- define "subv.pow2" -}}
{{- $n := int . -}}
{{- $big := dict "64" "18446744073709551616" "65" "36893488147419103232" "66" "73786976294838206464" "67" "147573952589676412928" "68" "295147905179352825856" "69" "590295810358705651712" "70" "1180591620717411303424" "71" "2361183241434822606848" "72" "4722366482869645213696" "73" "9444732965739290427392" "74" "18889465931478580854784" "75" "37778931862957161709568" "76" "75557863725914323419136" "77" "151115727451828646838272" "78" "302231454903657293676544" "79" "604462909807314587353088" "80" "1208925819614629174706176" -}}
{{- if hasKey $big (toString $n) -}}{{- index $big (toString $n) -}}
{{- else -}}
{{- $r := 1 -}}{{- range until $n -}}{{- $r = mul $r 2 -}}{{- end -}}{{- $r -}}
{{- end -}}
{{- end -}}

{{/*
subv.peering: one VirtualNetworksVirtualNetworkPeering, as the peering
submodule (avm-res-network-virtualnetwork 0.14.1, modules/peering) makes
its full peering. The sub-vending module passes it the local peered
address spaces and subnets but never the remote ones, so a peering with
peer_complete_vnets false fails there; it fails here with its message.
Arguments (a dict): root, name, id, azureName, owner, remote (a
reference), o (the options, defaults filled in), what.
*/}}
{{- define "subv.peering" -}}
{{- $o := .o }}
{{- if eq $o.peer_complete_vnets false }}
{{- fail (printf "%s: %s: At least one of peered_address_spaces or peered_subnets must be set when peer_complete_vnets is false (the module passes the peering submodule no remote address spaces or subnets)" .root.Chart.Name .what) }}
{{- end }}
---
apiVersion: network.azure.com/v20250301
kind: VirtualNetworksVirtualNetworkPeering
metadata:
  {{- include "aso.metadata" (dict "root" .root "name" .name "id" .id "abandon" (include "aso.abandon" .root)) | nindent 2 }}
spec:
  azureName: {{ .azureName | quote }}
  owner:
    {{- toYaml .owner | nindent 4 }}
  remoteVirtualNetwork:
    reference:
      {{- toYaml .remote | nindent 6 }}
  allowVirtualNetworkAccess: {{ eq $o.allow_virtual_network_access true }}
  allowForwardedTraffic: {{ eq $o.allow_forwarded_traffic true }}
  allowGatewayTransit: {{ eq $o.allow_gateway_transit true }}
  useRemoteGateways: {{ eq $o.use_remote_gateways true }}
  doNotVerifyRemoteGateways: {{ eq $o.do_not_verify_remote_gateways true }}
  enableOnlyIPv6Peering: {{ eq $o.enable_only_ipv6_peering true }}
  peerCompleteVnets: true
{{- end -}}

{{/*
subv.anySet: "true" when a value holds a non-empty leaf anywhere, else "".
*/}}
{{- define "subv.anySet" -}}
{{- if kindIs "map" . -}}
{{- range $_, $v := . -}}{{- include "subv.anySet" $v -}}{{- end -}}
{{- else if kindIs "slice" . -}}
{{- if gt (len .) 0 -}}true{{- end -}}
{{- else if not (empty .) -}}true
{{- end -}}
{{- end -}}

{{/*
subv.sub: the subscription the module's resources go into, as JSON
{"id": <subscription ID>}, or stops the render naming why there is none.
The module takes it from the alias it creates (azapi_resource.subscription's
properties.subscriptionId) or from subscription_id. The alias's ID is known
only once Azure has created the subscription, after the render, and a
resource group, ASO's ResourceGroup, goes into the subscription of ASO's
credential, so a resource in a vended subscription needs a second
instance of this chart given the first one's subscription_id output.
Argument: list $ what (the input that needs it).
*/}}
{{- define "subv.sub" -}}
{{- $root := index . 0 -}}{{- $what := index . 1 -}}
{{- $v := $root.Values -}}
{{- if eq $v.subscription_alias_enabled true -}}
{{- fail (printf "%s: %s is not supported with subscription_alias_enabled: the new subscription's ID is known only once Azure has created it (the alias's status.properties.subscriptionId), after the render; apply this chart again for the resources in it, with subscription_id set to this instance's subscription_id output (docs/azure.md, \"Charts\")" $root.Chart.Name $what) -}}
{{- end -}}
{{- if not $v.subscription_id -}}
{{- fail (printf "%s: %s needs subscription_id: the subscription the module's resources go into" $root.Chart.Name $what) -}}
{{- end -}}
{{- toJson (dict "id" $v.subscription_id) -}}
{{- end -}}

{{/*
subv.rgs: the resource groups the chart makes, as JSON {<key>: {obj, name,
id}}: the Kubernetes object, the Azure name (namePrefix on it) and the
resource ID, or {} when resource_group_creation_enabled is false (the
module makes none, and a resource_group_key then names none).
*/}}
{{- define "subv.rgs" -}}
{{- $v := .Values -}}
{{- $out := dict -}}
{{- if and (eq $v.resource_group_creation_enabled true) $v.resource_groups -}}
{{- $sub := (include "subv.sub" (list . "resource_groups") | fromJson).id -}}
{{- range $k, $rg := ($v.resource_groups | default dict) -}}
{{- $name := include "aso.cloudName" (list $ "resource group" $rg.name 90 false) -}}
{{- $_ := set $out $k (dict "obj" (include "aso.name" (list $.Release.Name "rg" $k)) "name" $name "id" (printf "/subscriptions/%s/resourceGroups/%s" $sub $name)) -}}
{{- end -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/*
subv.parent: the resource group a resource goes into, as JSON {owner,
name, id}: owner is an ASO owner (the chart's ResourceGroup by name for a
resource_group_key, or the existing group's ID), name and id the group's.
Arguments (a list): $, what (for messages), key, existing, exactlyOne
(true where the module's validation says exactly one of the two).
*/}}
{{- define "subv.parent" -}}
{{- $root := index . 0 -}}{{- $what := index . 1 -}}{{- $key := index . 2 -}}{{- $existing := index . 3 -}}{{- $one := index . 4 -}}
{{- $n := $root.Chart.Name -}}
{{- if and $one (eq (empty $key) (empty $existing)) -}}
{{- fail (printf "%s: %s: set exactly one of resource_group_key or resource_group_name_existing." $n $what) -}}
{{- end -}}
{{- $sub := (include "subv.sub" (list $root $what) | fromJson).id -}}
{{- $rgs := include "subv.rgs" $root | fromJson -}}
{{- if $existing -}}
{{- toJson (dict "owner" (dict "armId" (printf "/subscriptions/%s/resourceGroups/%s" $sub $existing)) "name" $existing "id" (printf "/subscriptions/%s/resourceGroups/%s" $sub $existing)) -}}
{{- else if $key -}}
{{- $rg := index $rgs $key -}}
{{- if not $rg -}}
{{- fail (printf "%s: %s: resource_group_key %q is not a resource group this chart makes (a key of resource_groups, with resource_group_creation_enabled)" $n $what $key) -}}
{{- end -}}
{{- toJson (dict "owner" (dict "name" $rg.obj) "name" $rg.name "id" $rg.id) -}}
{{- else -}}
{{- fail (printf "%s: %s: set resource_group_key or resource_group_name_existing" $n $what) -}}
{{- end -}}
{{- end -}}

{{/*
subv.scope: a role assignment's or budget's scope, as JSON {owner, id}:
the chart's resource group for resource_group_scope_key (or
resource_group_key), else the subscription and relative_scope, as the
module computes "${subscription_resource_id}${relative_scope}". Both are
extension resources, so an owner by name names the group's kind too.
Arguments (a list): $, what, key, relative.
*/}}
{{- define "subv.scope" -}}
{{- $root := index . 0 -}}{{- $what := index . 1 -}}{{- $key := index . 2 -}}{{- $rel := index . 3 | default "" -}}
{{- if $key -}}
{{- $p := include "subv.parent" (list $root $what $key "" false) | fromJson -}}
{{- toJson (dict "owner" (dict "group" "resources.azure.com" "kind" "ResourceGroup" "name" $p.owner.name) "id" $p.id) -}}
{{- else -}}
{{- $sub := (include "subv.sub" (list $root $what) | fromJson).id -}}
{{- $id := printf "/subscriptions/%s%s" $sub $rel -}}
{{- toJson (dict "owner" (dict "armId" $id) "id" $id) -}}
{{- end -}}
{{- end -}}

{{/*
subv.roleDefinition: a role assignment's definition as the module sends
it: a scopeless role definition ID gets the subscription's ID in front
(local.role_assignments_definitions), a name stays a name (ASO resolves it
as wellKnownName, where the module reads avm-utl-roledefinitions' table).
Arguments (a list): $, what, definition.
*/}}
{{- define "subv.roleDefinition" -}}
{{- $root := index . 0 -}}{{- $what := index . 1 -}}{{- $d := index . 2 -}}
{{- if contains "/providers/microsoft.authorization/roledefinitions/" (lower $d) -}}
{{- if not (regexMatch "^/providers/Microsoft\\.Authorization/roleDefinitions/[a-f\\d]{4}(?:[a-f\\d]{4}-){4}[a-f\\d]{12}$" $d) -}}
{{- fail (printf "%s: %s: If definition is a role definition ID, it must start with /providers/Microsoft.Authorization/roleDefinitions/ to be a scopeless role definition ID." $root.Chart.Name $what) -}}
{{- end -}}
{{- printf "/subscriptions/%s%s" (include "subv.sub" (list $root $what) | fromJson).id $d -}}
{{- else -}}
{{- $d -}}
{{- end -}}
{{- end -}}

{{/*
subv.roleAssignment: one ASO RoleAssignment as the module's role-assignment
submodule makes it. Its name is the module's uuidv5 of scope, principal and
role definition ID when all three are known at render (a definition given
by ID, a principal given by ID, use_random_uuid false); otherwise ASO's own
stable UUID (a definition by name resolves in Azure; a random UUID differs
on every apply anyway).
Arguments (a dict): root, name, id, scope ({owner, id}), r (the entry),
role (subv.roleDefinition), principal (an ID, or "" with cm, the
ConfigMap holding it).
*/}}
{{- define "subv.roleAssignment" -}}
{{- $r := .r -}}
{{- $isID := hasPrefix "/subscriptions/" .role }}
---
apiVersion: authorization.azure.com/v20220401
kind: RoleAssignment
metadata:
  {{- include "aso.metadata" (dict "root" .root "name" .name "id" .id "abandon" (include "aso.abandon" .root)) | nindent 2 }}
spec:
  {{- if and $isID .principal (ne $r.use_random_uuid true) }}
  azureName: {{ include "subv.uuidv5" (printf "%s%s%s" .scope.id .principal .role) | quote }}
  {{- end }}
  owner:
    {{- toYaml .scope.owner | nindent 4 }}
  {{- if .principal }}
  principalId: {{ .principal | quote }}
  {{- else }}
  principalIdFromConfig:
    name: {{ .cm }}
    key: principalId
  {{- end }}
  {{- with $r.principal_type }}
  principalType: {{ . | quote }}
  {{- end }}
  roleDefinitionReference:
    {{- if $isID }}
    armId: {{ .role | quote }}
    {{- else }}
    wellKnownName: {{ .role | quote }}
    {{- end }}
  {{- with $r.condition }}
  condition: {{ . | quote }}
  {{- end }}
  {{- with $r.condition_version }}
  conditionVersion: {{ . | quote }}
  {{- end }}
{{- end -}}

{{/*
subv.withDefaults: an object's given fields over the module's optional()
defaults, as JSON: a field given (even false) wins, a missing or null one
takes the default (Sprig's merge would treat false as empty).
Argument: list given defaults.
*/}}
{{- define "subv.withDefaults" -}}
{{- $given := index . 0 -}}{{- $out := deepCopy (index . 1) -}}
{{- range $k, $val := $given -}}
{{- if not (kindIs "invalid" $val) -}}{{- $_ := set $out $k $val -}}{{- end -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}
