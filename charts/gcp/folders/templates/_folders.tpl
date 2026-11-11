{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0

Helpers of the folders chart.
*/ -}}

{{- /* folders.id: a folder's hfl.dev/id, from its entry in names. */ -}}
{{- define "folders.id" -}}
{{- printf "folder:%s" . -}}
{{- end -}}

{{- /* folders.object: a folder's Kubernetes name. (list $ <name>) */ -}}
{{- define "folders.object" -}}
{{- include "kcc.name" (list (index . 0).Release.Name (index . 1)) -}}
{{- end -}}

{{- /*
folders.bindings: the module's owners_combined bindings (main.tf, locals
folder_admin_roles_map_data, folder_admin_roles_all_folders and
folder_iam_bindings), as JSON {"<name>-<role>": {name, role, members}},
members as the binding sends them: the entry's members, then
all_folder_admins, distinct.
  - per_folder_admins: each folder's roles (its own, else
    folder_admin_roles), with its members;
  - all_folder_admins: folder_admin_roles on each folder in names that
    per_folder_admins does not name;
  - none at all unless set_roles.
Terraform stops on two bindings with one key, and on a per_folder_admins
folder that is not in names (google_folder.folders[name] does not exist);
so does the chart.
*/ -}}
{{- define "folders.bindings" -}}
{{- $v := .Values -}}
{{- $out := dict -}}
{{- $per := $v.per_folder_admins | default dict -}}
{{- $all := $v.all_folder_admins | default list -}}
{{- $names := $v.names | default list -}}
{{- $roles := $v.folder_admin_roles | default list -}}
{{- $combined := list -}}
{{- range $name := keys $per | sortAlpha -}}
{{- $c := index $per $name -}}
{{- $rs := $roles -}}
{{- if not (kindIs "invalid" $c.roles) }}{{ $rs = $c.roles }}{{ end -}}
{{- range $role := $rs -}}
{{- $combined = append $combined (dict "name" $name "role" $role "members" ($c.members | default list)) -}}
{{- end -}}
{{- end -}}
{{- if $all -}}
{{- range $name := $names -}}
{{- if not (hasKey $per $name) -}}
{{- range $role := $roles -}}
{{- $combined = append $combined (dict "name" $name "role" $role "members" $all) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if and $v.set_roles $combined -}}
{{- range $b := $combined -}}
{{- if not (has $b.name $names) -}}
{{- fail (printf "folders: per_folder_admins names folder %q, which is not in names (the module fails the same way: google_folder.folders[%q] does not exist)" $b.name $b.name) -}}
{{- end -}}
{{- $key := printf "%s-%s" $b.name $b.role -}}
{{- if hasKey $out $key -}}
{{- fail (printf "folders: two admin bindings have the key %q (folder %q, role %q): the module fails on it too (a role listed twice, or a folder twice in names)" $key $b.name $b.role) -}}
{{- end -}}
{{- $members := list -}}
{{- range $m := concat $b.members $all -}}
{{- if not (has $m $members) }}{{ $members = append $members $m }}{{ end -}}
{{- end -}}
{{- $_ := set $out $key (dict "name" $b.name "role" $b.role "members" $members) -}}
{{- end -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}
