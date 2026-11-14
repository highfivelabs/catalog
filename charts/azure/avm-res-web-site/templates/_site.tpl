{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
Ported from terraform-azurerm-avm-res-web-site locals.tf, locals.body.tf,
locals.config.tf, locals.app_settings.tf, modules/site_config_helpers and
modules/slot (v0.24.1), Copyright (c) Microsoft Corporation, MIT.

This chart's own helpers ("site."): the site's and a slot's body, which
the module builds twice (azapi_resource.this and modules/slot) from the
same shapes.
*/ -}}

{{/*
site.prune: a value with every null map entry removed, as JSON wrapped in
{"v": ...} (fromJson takes only objects). The module's azapi resources
send ignore_null_property = true; this is that.
  {{ (include "site.prune" $x | fromJson).v }}
*/}}
{{- define "site.prune" -}}
{{- $x := . -}}
{{- if kindIs "map" $x -}}
{{- $out := dict -}}
{{- range $k, $v := $x -}}
{{- if not (kindIs "invalid" $v) -}}
{{- $_ := set $out $k (include "site.prune" $v | fromJson).v -}}
{{- end -}}
{{- end -}}
{{- dict "v" $out | toJson -}}
{{- else if kindIs "slice" $x -}}
{{- $out := list -}}
{{- range $x -}}
{{- $out = append $out (include "site.prune" . | fromJson).v -}}
{{- end -}}
{{- dict "v" $out | toJson -}}
{{- else -}}
{{- dict "v" $x | toJson -}}
{{- end -}}
{{- end -}}

{{/*
site.withDefaults: a map with Terraform's optional() defaults applied: a
key that is missing or null takes its default; false and 0 stay (Sprig's
merge would overwrite them). As JSON.
  {{ include "site.withDefaults" (list $in $defaults) | fromJson }}
*/}}
{{- define "site.withDefaults" -}}
{{- $in := deepCopy (index . 0 | default dict) -}}
{{- range $k, $d := index . 1 -}}
{{- if kindIs "invalid" (index $in $k) }}{{ $_ := set $in $k $d }}{{ end -}}
{{- end -}}
{{- toJson $in -}}
{{- end -}}

{{/*
site.uuidv5: Terraform's uuidv5("url", name), as avm-utl-interfaces names
a private endpoint from the site's ID.
*/}}
{{- define "site.uuidv5" -}}
{{- $h := sha1sum (printf "%s%s" (b64dec "a6e4EZ2tEdGAtADAT9QwyA==") .) -}}
{{- $variant := dict "0" "8" "1" "9" "2" "a" "3" "b" "4" "8" "5" "9" "6" "a" "7" "b" "8" "8" "9" "9" "a" "a" "b" "b" "c" "8" "d" "9" "e" "a" "f" "b" -}}
{{- printf "%s-%s-5%s-%s%s-%s" (substr 0 8 $h) (substr 8 12 $h) (substr 13 16 $h) (get $variant (substr 16 17 $h)) (substr 17 20 $h) (substr 20 32 $h) -}}
{{- end -}}

{{/*
site.siteName: the site's Azure name (names.site, else the namePrefix and
name).
*/}}
{{- define "site.siteName" -}}
{{- include "aso.resourceName" (list . "site" "App Service" .Values.name 60 "^[a-zA-Z0-9]([a-zA-Z0-9-]{0,58}[a-zA-Z0-9])?$") -}}
{{- end -}}

{{/*
site.armKind: the ARM kind the module derives (locals.tf, arm_kind_map).
*/}}
{{- define "site.armKind" -}}
{{- $v := .Values -}}
{{- $linux := eq $v.os_type "Linux" -}}
{{- $container := not (kindIs "invalid" (($v.site_config | default dict).application_stack | default dict).docker) -}}
{{- $key := ternary (ternary "linux_container" "linux" $container) (ternary "windows_container" "windows" $container) $linux -}}
{{- $map := dict
  "webapp" (dict "linux" "app,linux" "linux_container" "app,linux,container" "windows" "app" "windows_container" "app,container,windows")
  "functionapp" (dict "linux" "functionapp,linux" "linux_container" "functionapp,linux,container" "windows" "functionapp" "windows_container" "functionapp")
  "logicapp" (dict "linux" "functionapp,linux,container,workflowapp" "linux_container" "functionapp,linux,container,workflowapp" "windows" "functionapp,workflowapp" "windows_container" "functionapp,workflowapp") -}}
{{- index (index $map $v.kind | default dict) $key | default "app" -}}
{{- end -}}

{{/*
site.siteConfigDefaults: the optional() defaults of the module's
site_config object (variables.tf), which Helm does not apply to a nested
value.
*/}}
{{- define "site.siteConfigDefaults" -}}
{{- dict "always_on" true "ftps_state" "FtpsOnly" "http2_enabled" false "ip_restriction_default_action" "Allow" "load_balancing_mode" "LeastRequests" "local_mysql_enabled" false "managed_pipeline_mode" "Integrated" "minimum_tls_version" "1.3" "remote_debugging_enabled" false "scm_ip_restriction_default_action" "Allow" "scm_minimum_tls_version" "1.2" "scm_type" "None" "scm_use_main_ip_restriction" false "use_32_bit_worker" false "vnet_route_all_enabled" false "websockets_enabled" false "ip_restriction" list "scm_ip_restriction" list "virtual_application" list | toJson -}}
{{- end -}}

{{/*
site.restrictions: ip_restriction or scm_ip_restriction as ASO's
ipSecurityRestrictions (modules/site_config_helpers), the subnet by ARM ID.
*/}}
{{- define "site.restrictions" -}}
{{- $null := index (dict) "null" -}}
{{- $out := list -}}
{{- range . -}}
{{- $r := . -}}
{{- $tag := ternary "ServiceTag" (ternary "Default" nil (not (empty $r.ip_address))) (not (empty $r.service_tag)) -}}
{{- $headers := dict -}}
{{- with $r.headers -}}
{{- range $k, $h := dict "x-azure-fdid" .x_azure_fdid "x-fd-healthprobe" .x_fd_health_probe "x-forwarded-for" .x_forwarded_for "x-forwarded-host" .x_forwarded_host -}}
{{- if not (kindIs "invalid" $h) }}{{ $_ := set $headers $k $h }}{{ end -}}
{{- end -}}
{{- end -}}
{{- $subnet := $null -}}
{{- with $r.virtual_network_subnet_id }}{{ $subnet = dict "armId" . }}{{ end -}}
{{- $out = append $out (dict
  "action" ($r.action | default "Allow")
  "ipAddress" (ternary $r.service_tag $r.ip_address (not (empty $r.service_tag)))
  "name" $r.name
  "priority" (ternary 65000 $r.priority (kindIs "invalid" $r.priority))
  "tag" $tag
  "vnetSubnetResourceReference" $subnet
  "headers" (ternary nil $headers (kindIs "invalid" $r.headers))) -}}
{{- end -}}
{{- dict "v" $out | toJson -}}
{{- end -}}

{{/*
site.autoHealRules: site_config.auto_heal_rules as ARM's autoHealRules.
*/}}
{{- define "site.autoHealRules" -}}
{{- $null := index (dict) "null" -}}
{{- $a := . -}}
{{- $out := $null -}}
{{- if not (kindIs "invalid" $a) -}}
{{- $actions := $null -}}
{{- with $a.actions -}}
{{- $custom := $null -}}
{{- with .custom_action }}{{ $custom = dict "exe" .exe "parameters" .parameters }}{{ end -}}
{{- $actions = dict "actionType" .action_type "customAction" $custom "minProcessExecutionTime" (ternary "00:00:00" .min_process_execution_time (kindIs "invalid" .min_process_execution_time)) -}}
{{- end -}}
{{- $triggers := $null -}}
{{- with $a.triggers -}}
{{- $t := dict -}}
{{- if not (kindIs "invalid" .private_bytes_in_kb) }}{{ $_ := set $t "privateBytesInKB" .private_bytes_in_kb }}{{ end -}}
{{- with .requests }}{{ $_ := set $t "requests" (dict "count" .count "timeInterval" .time_interval) }}{{ end -}}
{{- with .slow_requests }}{{ $_ := set $t "slowRequests" (dict "count" .count "timeInterval" .time_interval "timeTaken" .time_taken "path" .path) }}{{ end -}}
{{- with .slow_requests_with_path -}}
{{- $l := list -}}
{{- range . }}{{ $l = append $l (dict "count" .count "timeInterval" .time_interval "timeTaken" .time_taken "path" .path) }}{{ end -}}
{{- $_ := set $t "slowRequestsWithPath" $l -}}
{{- end -}}
{{- with .status_codes -}}
{{- $l := list -}}
{{- range . }}{{ $l = append $l (dict "count" .count "timeInterval" .time_interval "status" .status "path" .path "subStatus" .sub_status "win32Status" .win32_status) }}{{ end -}}
{{- $_ := set $t "statusCodes" $l -}}
{{- end -}}
{{- with .status_codes_range -}}
{{- $l := list -}}
{{- range . }}{{ $l = append $l (dict "count" .count "timeInterval" .time_interval "statusCodes" .status_codes "path" .path) }}{{ end -}}
{{- $_ := set $t "statusCodesRange" $l -}}
{{- end -}}
{{- $triggers = $t -}}
{{- end -}}
{{- $out = dict "actions" $actions "triggers" $triggers -}}
{{- end -}}
{{- dict "v" $out | toJson -}}
{{- end -}}

{{/*
site.identity: the managed_identities interface as ARM's identity, the
user-assigned identities by ARM ID (site_config_helpers' identity_block).
*/}}
{{- define "site.identity" -}}
{{- $null := index (dict) "null" -}}
{{- $mi := . | default dict -}}
{{- $uai := uniq ($mi.user_assigned_resource_ids | default list) | sortAlpha -}}
{{- $sa := eq (toString $mi.system_assigned) "true" -}}
{{- $out := $null -}}
{{- if or $sa $uai -}}
{{- $refs := list -}}
{{- range $uai }}{{ $refs = append $refs (dict "reference" (dict "armId" .)) }}{{ end -}}
{{- $out = dict "type" (ternary (ternary "SystemAssigned, UserAssigned" "SystemAssigned" (gt (len $uai) 0)) "UserAssigned" $sa) "userAssignedIdentities" (ternary nil $refs (eq (len $refs) 0)) -}}
{{- end -}}
{{- dict "v" $out | toJson -}}
{{- end -}}

{{/*
site.body: the properties of a site or a slot (azapi_resource.this's body
in the root module and in modules/slot), as ASO's spec fields, nulls left
in for site.prune.
Arguments (a dict):
  root    $
  v       the site's values, or a slot's entry with the module's
          optional() defaults applied
  sc      the site_config, with its defaults applied
  slot    true for a slot (modules/slot sends no reserved, always sends
          clientCertMode, scmType and localMySqlEnabled, and virtual
          applications on every Windows app)
  appSettings  the merged app settings, a map
  serverFarm   the plan's ARM ID
  vnetBackup   the backup and restore traffic flag (the root's
          virtual_network_backup_restore_enabled, a slot's
          vnet_backup_restore_enabled)
*/}}
{{- /*
site.storageMounts: storage_shares_to_mount as siteConfig.azureStorageAccounts
(module config_azurestorageaccounts, which PUTs the same map to
sites/config/azurestorageaccounts), keyed by each mount's name. The access
key is a reference to a Kubernetes Secret, {secretName, key}
(docs/secrets.md), which ASO takes as a SecretReference. A slot's keys are
in slots_storage_shares_to_mount_sensitive_values, by the mount's key, as
in the module; the site's are each mount's access_key.
  include "site.storageMounts" (list $ "storage_shares_to_mount" $mounts $keys) | fromJson).v
*/ -}}
{{- define "site.storageMounts" -}}
{{- $root := index . 0 -}}{{- $path := index . 1 -}}{{- $mounts := index . 2 | default dict -}}{{- $keys := index . 3 -}}
{{- $out := dict -}}
{{- range $k := keys $mounts | sortAlpha -}}
{{- $m := index $mounts $k -}}
{{- range $f := list "account_name" "mount_path" "name" "share_name" -}}
{{- if not (index $m $f) }}{{ fail (printf "%s: %s.%s.%s is required" $root.Chart.Name $path $k $f) }}{{ end -}}
{{- end -}}
{{- $ref := "" -}}
{{- if kindIs "invalid" $keys -}}
{{- if kindIs "invalid" $m.access_key }}{{ fail (printf "%s: %s.%s.access_key is required: a reference to a Kubernetes Secret, {secretName, key} (docs/secrets.md)" $root.Chart.Name $path $k) }}{{ end -}}
{{- $ref = include "aso.secretRef" (list $root (printf "%s.%s.access_key" $path $k) $m.access_key) -}}
{{- else -}}
{{- if not (hasKey $keys $k) }}{{ fail (printf "%s: %s.%s needs its access key in slots_storage_shares_to_mount_sensitive_values.%s, a reference to a Kubernetes Secret, {secretName, key} (docs/secrets.md)" $root.Chart.Name $path $k $k) }}{{ end -}}
{{- $ref = include "aso.secretRef" (list $root (printf "slots_storage_shares_to_mount_sensitive_values.%s" $k) (index $keys $k)) -}}
{{- end -}}
{{- $_ := set $out (toString $m.name) (dict "type" ($m.type | default "AzureFiles") "accountName" $m.account_name "shareName" $m.share_name "mountPath" $m.mount_path "accessKey" (fromJson $ref)) -}}
{{- end -}}
{{- toJson (dict "v" (ternary nil $out (eq (len $out) 0))) -}}
{{- end -}}
{{- define "site.body" -}}
{{- $null := index (dict) "null" -}}
{{- $root := .root -}}{{- $v := .v -}}{{- $sc := .sc -}}{{- $slot := .slot -}}
{{- $rv := $root.Values -}}
{{- $linux := eq $rv.os_type "Linux" -}}
{{- $fn := eq $rv.kind "functionapp" -}}
{{- $web := eq $rv.kind "webapp" -}}
{{- $logic := eq $rv.kind "logicapp" -}}
{{- $fc1 := eq (toString $rv.function_app_uses_fc1) "true" -}}
{{- $stack := $sc.application_stack | default dict -}}
{{- $hasStack := not (kindIs "invalid" $sc.application_stack) -}}
{{- /* site_config_helpers: the language versions. */ -}}
{{- $docker := "" -}}
{{- with $stack.docker -}}
{{- $docker = printf "DOCKER|%s/%s:%s" (trimPrefix "https://" (.docker_registry_url | default "")) (toString .docker_image_name) (.docker_image_tag | default "latest") -}}
{{- end -}}
{{- $javaFx := "" -}}
{{- with $stack.java -}}
{{- $container := upper (.java_container | default "JAVA") -}}
{{- $major := .java_version -}}
{{- $cv := .java_container_version | default $major -}}
{{- if not (kindIs "invalid" $cv) -}}
{{- $cv = toString $cv -}}
{{- $suffix := "" -}}
{{- if and (not (kindIs "invalid" $major)) $cv -}}
{{- $major = toString $major -}}
{{- if eq $major "8" -}}
{{- if eq $container "JAVA" }}{{ $suffix = ternary "" "-jre8" (contains "u" $cv) }}
{{- else if eq $container "TOMCAT" }}{{ $suffix = ternary "-java8" "-jre8" (eq (len (splitList "." $cv)) 3) }}
{{- else }}{{ $suffix = "-java8" }}{{ end -}}
{{- else if and (eq $container "JAVA") (eq (len (splitList "." $cv)) 3) -}}
{{- $suffix = "" -}}
{{- else -}}
{{- $suffix = printf "-java%s" $major -}}
{{- end -}}
{{- end -}}
{{- $javaFx = printf "%s|%s%s" $container $cv $suffix -}}
{{- end -}}
{{- end -}}
{{- $linuxFx := $null -}}
{{- if $linux -}}
{{- $linuxFx = $sc.linux_fx_version -}}
{{- if and (empty $linuxFx) $hasStack -}}
{{- $cands := list $docker -}}
{{- with $stack.python }}{{ $cands = append $cands (printf "PYTHON|%v" .python_version) }}{{ end -}}
{{- with $stack.node }}{{ $cands = append $cands (printf "NODE|%v" .node_version) }}{{ end -}}
{{- with $stack.dotnet }}{{ $cands = append $cands (printf "%s|%v" (ternary "DOTNET-ISOLATED" "DOTNETCORE" (and $fn (eq (toString .use_dotnet_isolated_runtime) "true"))) .dotnet_version) }}{{ end -}}
{{- $cands = append $cands $javaFx -}}
{{- with $stack.powershell }}{{ $cands = append $cands (printf "POWERSHELL|%v" .powershell_version) }}{{ end -}}
{{- with $stack.php }}{{ $cands = append $cands (printf "PHP|%v" .php_version) }}{{ end -}}
{{- $linuxFx = first (compact $cands) -}}
{{- end -}}
{{- if empty $linuxFx }}{{ $linuxFx = $null }}{{ end -}}
{{- end -}}
{{- $windowsFx := $null -}}
{{- if not $linux -}}
{{- $windowsFx = $sc.windows_fx_version | default $docker -}}
{{- if empty $windowsFx }}{{ $windowsFx = $null }}{{ end -}}
{{- end -}}
{{- $win := not $linux -}}
{{- $lang := dict -}}
{{- range $f := list (list "java_container" "java" "java_container") (list "java_container_version" "java" "java_container_version") (list "java_version" "java" "java_version") (list "dotnet_framework_version" "dotnet" "dotnet_version") (list "node_version" "node" "node_version") (list "php_version" "php" "php_version") (list "powershell_version" "powershell" "powershell_version") (list "python_version" "python" "python_version") -}}
{{- $val := index $sc (index $f 0) -}}
{{- if and (empty $val) $win $hasStack -}}
{{- $val = (index $stack (index $f 1) | default dict) | dig (index $f 2) nil -}}
{{- end -}}
{{- $_ := set $lang (index $f 0) (ternary nil $val (empty $val)) -}}
{{- end -}}
{{- /* CURRENT_STACK metadata (Windows only). */ -}}
{{- $metadata := $sc.metadata | default list -}}
{{- $current := "" -}}
{{- if and $win $hasStack -}}
{{- if and $stack.dotnet (eq (toString $stack.dotnet.use_custom_runtime) "true") }}{{ $current = "custom" }}
{{- else if and $stack.dotnet $stack.dotnet.current_stack }}{{ $current = $stack.dotnet.current_stack }}
{{- else if $stack.dotnet }}{{ $current = "dotnet" }}
{{- else if $stack.node }}{{ $current = "node" }}
{{- else if $stack.php }}{{ $current = "php" }}
{{- else if $stack.python }}{{ $current = "python" }}
{{- else if $stack.java }}{{ $current = "java" }}
{{- else if $stack.powershell }}{{ $current = "powershell" }}{{ end -}}
{{- end -}}
{{- $userKeys := list -}}
{{- range $metadata }}{{ $userKeys = append $userKeys .name }}{{ end -}}
{{- if and $current (not (has "CURRENT_STACK" $userKeys)) -}}
{{- $metadata = append $metadata (dict "name" "CURRENT_STACK" "value" $current) -}}
{{- end -}}
{{- $md := list -}}
{{- range $metadata }}{{ $md = append $md (dict "name" .name "value" (toString .value)) }}{{ end -}}
{{- /* virtual applications: Windows web apps (a slot: every Windows app). */ -}}
{{- $vapps := $null -}}
{{- if and $win (or $slot $web) -}}
{{- $in := $sc.virtual_application | default list -}}
{{- if not $in }}{{ $in = list (dict) }}{{ end -}}
{{- $vapps = list -}}
{{- range $in -}}
{{- $dirs := list -}}
{{- range (.virtual_directory | default list) }}{{ $dirs = append $dirs (dict "physicalPath" .physical_path "virtualPath" .virtual_path) }}{{ end -}}
{{- $vapps = append $vapps (dict "physicalPath" (.physical_path | default "site\\wwwroot") "preloadEnabled" (eq (toString .preload_enabled) "true") "virtualPath" (.virtual_path | default "/") "virtualDirectories" $dirs) -}}
{{- end -}}
{{- end -}}
{{- $cors := $null -}}
{{- with $sc.cors }}{{ $cors = dict "allowedOrigins" .allowed_origins "supportCredentials" (eq (toString .support_credentials) "true") }}{{ end -}}
{{- $experiments := $null -}}
{{- with $sc.experiments -}}
{{- $rules := list -}}
{{- range (.ramp_up_rules | default list) }}{{ $rules = append $rules (dict "actionHostName" .action_host_name "changeDecisionCallbackUrl" .change_decision_callback_url "changeIntervalInMinutes" .change_interval_in_minutes "changeStep" .change_step "maxReroutePercentage" .max_reroute_percentage "minReroutePercentage" .min_reroute_percentage "name" .name "reroutePercentage" .reroute_percentage) }}{{ end -}}
{{- $experiments = dict "rampUpRules" $rules -}}
{{- end -}}
{{- $handlers := $null -}}
{{- if not (kindIs "invalid" $sc.handler_mappings) -}}
{{- $handlers = list -}}
{{- range $sc.handler_mappings }}{{ $handlers = append $handlers (dict "arguments" .arguments "extension" .extension "scriptProcessor" .script_processor) }}{{ end -}}
{{- end -}}
{{- $limits := $null -}}
{{- with $sc.limits }}{{ $limits = dict "maxDiskSizeInMb" .max_disk_size_in_mb "maxMemoryInMb" .max_memory_in_mb "maxPercentageCpu" .max_percentage_cpu }}{{ end -}}
{{- $ipr := (include "site.restrictions" ($sc.ip_restriction | default list) | fromJson).v -}}
{{- $scmIpr := (include "site.restrictions" ($sc.scm_ip_restriction | default list) | fromJson).v -}}
{{- $settings := list -}}
{{- range $k := keys .appSettings | sortAlpha }}{{ $settings = append $settings (dict "name" $k "value" (toString (index $.appSettings $k))) }}{{ end -}}
{{- $fnNotFc1 := and $fn (not $fc1) -}}
{{- $siteConfig := dict
  "alwaysOn" (ternary nil $sc.always_on $fc1)
  "apiDefinition" (ternary nil (dict "url" $sc.api_definition_url) (empty $sc.api_definition_url))
  "apiManagementConfig" (ternary nil (dict "reference" (dict "armId" $sc.api_management_api_id)) (empty $sc.api_management_api_id))
  "appCommandLine" $sc.app_command_line
  "appSettings" (ternary nil $settings (eq (len $settings) 0))
  "autoHealEnabled" $sc.auto_heal_enabled
  "autoHealRules" (include "site.autoHealRules" $sc.auto_heal_rules | fromJson).v
  "cors" $cors
  "defaultDocuments" $sc.default_documents
  "detailedErrorLoggingEnabled" $sc.detailed_error_logging_enabled
  "documentRoot" $sc.document_root
  "elasticWebAppScaleLimit" $sc.elastic_web_app_scale_limit
  "experiments" $experiments
  "ftpsState" (ternary nil $sc.ftps_state $fc1)
  "handlerMappings" $handlers
  "healthCheckPath" $sc.health_check_path
  "http20Enabled" $sc.http2_enabled
  "http20ProxyFlag" $sc.http20_proxy_flag
  "httpLoggingEnabled" $sc.http_logging_enabled
  "ipSecurityRestrictions" (ternary nil $ipr (eq (len $ipr) 0))
  "ipSecurityRestrictionsDefaultAction" $sc.ip_restriction_default_action
  "limits" $limits
  "loadBalancing" $sc.load_balancing_mode
  "logsDirectorySizeLimit" $sc.logs_directory_size_limit
  "managedPipelineMode" $sc.managed_pipeline_mode
  "metadata" (ternary nil $md (eq (len $md) 0))
  "minTlsCipherSuite" $sc.min_tls_cipher_suite
  "minTlsVersion" $sc.minimum_tls_version
  "numberOfWorkers" $sc.worker_count
  "preWarmedInstanceCount" (ternary nil $sc.pre_warmed_instance_count $fc1)
  "remoteDebuggingEnabled" $sc.remote_debugging_enabled
  "remoteDebuggingVersion" $sc.remote_debugging_version
  "requestTracingEnabled" $sc.request_tracing_enabled
  "requestTracingExpirationTime" $sc.request_tracing_expiration_time
  "scmIpSecurityRestrictions" (ternary nil $scmIpr (eq (len $scmIpr) 0))
  "scmIpSecurityRestrictionsDefaultAction" $sc.scm_ip_restriction_default_action
  "scmIpSecurityRestrictionsUseMain" $sc.scm_use_main_ip_restriction
  "scmMinTlsVersion" $sc.scm_minimum_tls_version
  "tracingOptions" $sc.tracing_options
  "use32BitWorkerProcess" (ternary nil $sc.use_32_bit_worker $fc1)
  "virtualApplications" $vapps
  "vnetPrivatePortsCount" $sc.vnet_private_ports_count
  "vnetRouteAllEnabled" $sc.vnet_route_all_enabled
  "webSocketsEnabled" $sc.websockets_enabled
  "websiteTimeZone" $sc.website_time_zone
  "linuxFxVersion" (ternary nil $linuxFx $fc1)
  "windowsFxVersion" (ternary nil $windowsFx $fc1)
  "netFrameworkVersion" (ternary nil $lang.dotnet_framework_version $fc1)
  "phpVersion" (ternary nil $lang.php_version $fc1)
  "pythonVersion" (ternary nil $lang.python_version $fc1)
  "nodeVersion" (ternary nil $lang.node_version $fc1)
  "javaVersion" (ternary nil $lang.java_version $fc1)
  "javaContainer" (ternary nil $lang.java_container $fc1)
  "javaContainerVersion" (ternary nil $lang.java_container_version $fc1)
  "powerShellVersion" (ternary nil $lang.powershell_version $fc1)
  "functionsRuntimeScaleMonitoringEnabled" (ternary $sc.runtime_scale_monitoring_enabled nil $fnNotFc1)
  "minimumElasticInstanceCount" $sc.elastic_instance_minimum
  "scmType" (ternary $sc.scm_type nil (or $slot $logic))
  "acrUseManagedIdentityCreds" $sc.container_registry_use_managed_identity
  "acrUserManagedIdentityID" $sc.container_registry_managed_identity_client_id
  "functionAppScaleLimit" (ternary $sc.app_scale_limit nil $fnNotFc1)
  "localMySqlEnabled" (ternary $sc.local_mysql_enabled nil (or $slot $web))
  "autoSwapSlotName" $sc.auto_swap_slot_name
  "azureStorageAccounts" .storage -}}
{{- $dapr := $null -}}
{{- with $v.dapr_config }}{{ $dapr = dict "appId" .app_id "appPort" .app_port "enableApiLogging" .enable_api_logging "enabled" .enabled "httpMaxRequestSize" .http_max_request_size "httpReadBufferSize" .http_read_buffer_size "logLevel" .log_level }}{{ end -}}
{{- $dns := $null -}}
{{- with $v.dns_configuration }}{{ $dns = dict "dnsAltServer" .dns_alt_server "dnsMaxCacheTimeout" .dns_max_cache_timeout "dnsRetryAttemptCount" .dns_retry_attempt_count "dnsRetryAttemptTimeout" .dns_retry_attempt_timeout "dnsServers" .dns_servers }}{{ end -}}
{{- $resCfg := $null -}}
{{- with $v.resource_config }}{{ $resCfg = dict "cpu" .cpu "memory" .memory }}{{ end -}}
{{- $certOn := eq (toString $v.client_certificate_enabled) "true" -}}
{{- $body := dict
  "enabled" $v.enabled
  "httpsOnly" $v.https_only
  "serverFarmReference" (dict "armId" .serverFarm)
  "reserved" (ternary nil $linux $slot)
  "autoGeneratedDomainNameLabelScope" $v.auto_generated_domain_name_label_scope
  "clientAffinityEnabled" $v.client_affinity_enabled
  "clientAffinityPartitioningEnabled" $v.client_affinity_partitioning_enabled
  "clientAffinityProxyEnabled" $v.client_affinity_proxy_enabled
  "clientCertEnabled" $v.client_certificate_enabled
  "clientCertMode" (ternary $v.client_certificate_mode nil (or $slot $certOn))
  "clientCertExclusionPaths" $v.client_certificate_exclusion_paths
  "containerSize" $v.container_size
  "endToEndEncryptionEnabled" $v.end_to_end_encryption_enabled
  "hostNamesDisabled" $v.host_names_disabled
  "hyperV" $v.hyper_v
  "ipMode" $v.ip_mode
  "keyVaultReferenceIdentity" $v.key_vault_reference_identity
  "managedEnvironmentReference" (ternary nil (dict "armId" $v.managed_environment_id) (empty $v.managed_environment_id))
  "publicNetworkAccess" (ternary "Enabled" "Disabled" (eq (toString $v.public_network_access_enabled) "true"))
  "redundancyMode" $v.redundancy_mode
  "scmSiteAlsoStopped" $v.scm_site_also_stopped
  "sshEnabled" $v.ssh_enabled
  "storageAccountRequired" $v.storage_account_required
  "virtualNetworkSubnetReference" (ternary nil (dict "armId" $v.virtual_network_subnet_id) (empty $v.virtual_network_subnet_id))
  "workloadProfileName" $v.workload_profile_name
  "siteConfig" $siteConfig
  "outboundVnetRouting" (dict "allTraffic" $v.vnet_route_all_traffic "applicationTraffic" $v.vnet_application_traffic_enabled "backupRestoreTraffic" .vnetBackup "contentShareTraffic" $v.vnet_content_share_enabled "imagePullTraffic" $v.vnet_image_pull_enabled)
  "daprConfig" $dapr
  "dnsConfiguration" $dns
  "hostingEnvironmentProfile" (ternary nil (dict "reference" (dict "armId" $v.hosting_environment_id)) (empty $v.hosting_environment_id))
  "resourceConfig" $resCfg
  "identity" (include "site.identity" $v.managed_identities | fromJson).v -}}
{{- if not $slot -}}
{{- if $fc1 -}}
{{- $always := list -}}
{{- range $k, $a := ($rv.always_ready | default dict) }}{{ $always = append $always (dict "name" ($a.name | default $k) "instanceCount" (ternary 0 $a.instance_count (kindIs "invalid" $a.instance_count))) }}{{ end -}}
{{- $authType := dict "storageaccountconnectionstring" "StorageAccountConnectionString" "systemassignedidentity" "SystemAssignedIdentity" "userassignedidentity" "UserAssignedIdentity" -}}
{{- $_ := set $body "functionAppConfig" (dict
  "deployment" (dict "storage" (dict
    "type" "blobContainer"
    "value" $rv.storage_container_endpoint
    "authentication" (dict
      "type" (get $authType (lower (toString $rv.storage_authentication_type)))
      "userAssignedIdentityResourceReference" (ternary nil (dict "armId" $rv.storage_user_assigned_identity_id) (empty $rv.storage_user_assigned_identity_id)))))
  "scaleAndConcurrency" (dict
    "alwaysReady" (ternary nil $always (eq (len $always) 0))
    "maximumInstanceCount" $rv.maximum_instance_count
    "instanceMemoryMB" $rv.instance_memory_in_mb)
  "runtime" (dict "name" (lower (toString $rv.fc1_runtime_name)) "version" (toString $rv.fc1_runtime_version))) -}}
{{- end -}}
{{- $_ := set $body "dailyMemoryTimeQuota" (ternary $rv.daily_memory_time_quota nil $fnNotFc1) -}}
{{- end -}}
{{- include "site.prune" $body -}}
{{- end -}}
