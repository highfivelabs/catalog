{{/*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

This chart's own helpers (the shared ones are aso.*, templates/_aso.tpl).
*/}}

{{/*
vm.rgId: a resource group's ARM ID from a module value that is a group's
name (with the chart's subscription_id) or its ID.
  {{ include "vm.rgId" (list $ "resource_group_name" $v.resource_group_name) }}
*/}}
{{- define "vm.rgId" -}}
{{- $root := index . 0 -}}{{- $what := index . 1 -}}{{- $rg := toString (index . 2) -}}
{{- if hasPrefix "/" $rg -}}
{{- $rg -}}
{{- else if $root.Values.subscription_id -}}
{{- printf "/subscriptions/%s/resourceGroups/%s" $root.Values.subscription_id $rg -}}
{{- else -}}
{{- fail (printf "avm-res-compute-virtualmachine: %s is a name: set subscription_id too (ASO's owner is the group's resource ID), or give it as /subscriptions/<id>/resourceGroups/<name>" $what) -}}
{{- end -}}
{{- end -}}

{{/* vm.obj: the Kubernetes name of the VirtualMachine object. */}}
{{- define "vm.obj" -}}
{{- include "aso.name" (list .Release.Name "vm") -}}
{{- end -}}

{{/*
vm.id: the machine's ARM ID.
*/}}
{{- define "vm.id" -}}
{{- printf "%s/providers/Microsoft.Compute/virtualMachines/%s" (include "vm.rgId" (list . "resource_group_name" .Values.resource_group_name)) (include "aso.resourceName" (list . "virtualMachine" "virtual machine" .Values.name 64 "^[a-zA-Z0-9_]([a-zA-Z0-9_.-]{0,62}[a-zA-Z0-9_])?$")) -}}
{{- end -}}

{{/*
vm.nicOrder: the network interface keys, the primary ones first, as the
module orders network_interface_ids (azurerm makes the first one primary),
as JSON.
*/}}
{{- define "vm.nicOrder" -}}
{{- $first := list -}}{{- $rest := list -}}
{{- range $k, $n := (include "vm.nics" . | fromJson) -}}
{{- if eq $n.is_primary true -}}{{- $first = append $first $k -}}{{- else -}}{{- $rest = append $rest $k -}}{{- end -}}
{{- end -}}
{{- toJson (concat $first $rest) -}}
{{- end -}}

{{/*
vm.owntags: an object's tags when the module gives it its own (non-empty
tags win, else the module's tags), as JSON.
  {{ include "vm.owntags" (list $ $n.tags) | fromJson }}
*/}}
{{- define "vm.owntags" -}}
{{- $root := index . 0 -}}{{- $own := index . 1 -}}
{{- if $own -}}
{{- include "aso.tags" (list (dict "Chart" $root.Chart "Values" (dict "tags" $own)) dict) -}}
{{- else -}}
{{- include "aso.tags" (list $root dict) -}}
{{- end -}}
{{- end -}}

{{/*
vm.roleAssignments: role assignments the module makes with azurerm, whose
skip_service_principal_aad_check means principal type ServicePrincipal
when none is given (aso.roleAssignments).
Arguments as aso.roleAssignments.
*/}}
{{- define "vm.roleAssignments" -}}
{{- $ras := dict -}}
{{- range $k, $r := (.v | default dict) -}}
{{- $r2 := deepCopy $r -}}
{{- if and (kindIs "invalid" $r.principal_type) $r.skip_service_principal_aad_check -}}{{- $_ := set $r2 "principal_type" "ServicePrincipal" -}}{{- end -}}
{{- $_ := set $ras $k $r2 -}}
{{- end -}}
{{- include "aso.roleAssignments" (dict "root" .root "base" .base "idPrefix" .idPrefix "owner" .owner "v" $ras) -}}
{{- end -}}

{{/*
vm.nics: network_interfaces, or the module's default when empty, as JSON.
*/}}
{{- define "vm.nics" -}}
{{- if .Values.network_interfaces -}}
{{- toJson .Values.network_interfaces -}}
{{- else -}}
{{- toJson (dict "ipconfig_1" (dict "name" "default-ipv4-ipconfig" "accelerated_networking_enabled" true "ip_forwarding_enabled" false "ip_configurations" (dict "ip_config_1" (dict "name" "ipv4-ipconfig" "private_ip_address_version" "IPv4" "private_ip_address_allocation" "Dynamic" "is_primary_ipconfiguration" true)))) -}}
{{- end -}}
{{- end -}}
