{{- /*
Copyright 2026 High Five Labs
SPDX-License-Identifier: Apache-2.0
*/ -}}
{{/* cloudRunV2.key: the names key of the resource the type renders:
service, job or workerPool. */}}
{{- define "cloudRunV2.key" -}}
{{- $t := .Values.type | default "SERVICE" -}}
{{- if eq $t "JOB" }}job{{ else if eq $t "WORKERPOOL" }}workerPool{{ else }}service{{ end -}}
{{- end -}}

{{/* cloudRunV2.collection: the resource's collection in its full name:
services, jobs or workerPools. */}}
{{- define "cloudRunV2.collection" -}}
{{- $t := .Values.type | default "SERVICE" -}}
{{- if eq $t "JOB" }}jobs{{ else if eq $t "WORKERPOOL" }}workerPools{{ else }}services{{ end -}}
{{- end -}}

{{/* cloudRunV2.name: the resource's name: names.<service|job|workerPool>
in full, else fabric's name with the namePrefix in front (49 characters:
the Cloud Run Admin API v2 takes IDs of fewer than 50; a leading letter). */}}
{{- define "cloudRunV2.name" -}}
{{- include "kcc.resourceName" (list . (include "cloudRunV2.key" .) "Cloud Run" .Values.name 49 "letter") -}}
{{- end -}}

{{/* cloudRunV2.id: the resource's full name, as fabric's id output:
projects/<project>/locations/<region>/<services|jobs|workerPools>/<name>. */}}
{{- define "cloudRunV2.id" -}}
{{- printf "projects/%s/locations/%s/%s/%s" .Values.project_id .Values.region (include "cloudRunV2.collection" .) (include "cloudRunV2.name" .) -}}
{{- end -}}

{{/* cloudRunV2.serviceAccountCreate: "true" when the chart creates the
service account (fabric's local.service_account_create; the identity type
is always a service account here, workload_identity_config being
refused). */}}
{{- define "cloudRunV2.serviceAccountCreate" -}}
{{- $c := .Values.service_account_config | default dict -}}
{{- if ne (toString $c.create) "false" }}true{{ end -}}
{{- end -}}

{{/* cloudRunV2.serviceAccount: the account ID of the service account the
chart creates: names.serviceAccount, else service_account_config.name or
name with the namePrefix in front (30 characters, a leading letter). */}}
{{- define "cloudRunV2.serviceAccount" -}}
{{- $c := .Values.service_account_config | default dict -}}
{{- include "kcc.resourceName" (list . "serviceAccount" "service account" ($c.name | default .Values.name) 30 "letter") -}}
{{- end -}}

{{/* cloudRunV2.serviceAccountEmail: fabric's local.service_account_email:
the created account's email, else service_account_config.email, else ""
(Cloud Run then uses the Compute Engine default service account). */}}
{{- define "cloudRunV2.serviceAccountEmail" -}}
{{- $c := .Values.service_account_config | default dict -}}
{{- if include "cloudRunV2.serviceAccountCreate" . -}}
{{- printf "%s@%s.iam.gserviceaccount.com" (include "cloudRunV2.serviceAccount" .) .Values.project_id -}}
{{- else -}}
{{- $c.email | default "" -}}
{{- end -}}
{{- end -}}

{{/* cloudRunV2.vpcConnector: the connector's name: names.vpcConnector,
else vpc_connector_create.name or name with the namePrefix in front (25
characters, a leading letter). */}}
{{- define "cloudRunV2.vpcConnector" -}}
{{- include "kcc.resourceName" (list . "vpcConnector" "VPC connector" (.Values.vpc_connector_create.name | default .Values.name) 25 "letter") -}}
{{- end -}}

{{/* cloudRunV2.connector: fabric's local.connector: the created
connector's full name, else revision.vpc_access.connector, else "". */}}
{{- define "cloudRunV2.connector" -}}
{{- if .Values.vpc_connector_create -}}
{{- printf "projects/%s/locations/%s/connectors/%s" .Values.project_id .Values.region (include "cloudRunV2.vpcConnector" .) -}}
{{- else -}}
{{- ((.Values.revision | default dict).vpc_access | default dict).connector | default "" -}}
{{- end -}}
{{- end -}}

{{/* cloudRunV2.cloudLabels: the unprefixed labels of the chart's tags and
labels, as JSON: the cloud labels of a kind that takes them in
spec.labels (RunWorkerPool). */}}
{{- define "cloudRunV2.cloudLabels" -}}
{{- $cloud := dict -}}
{{- range $k, $l := (include "kcc.labels" (list . dict) | fromJson) -}}
{{- if not (contains "/" $k) }}{{ $_ := set $cloud $k $l }}{{ end -}}
{{- end -}}
{{- toJson $cloud -}}
{{- end -}}

{{/* cloudRunV2.secret: a Secret Manager secret as the kind's secretRef
takes it. RunService (Terraform-based) takes fabric's value as given, a
secret's name or ID; RunJob and RunWorkerPool take only
projects/<project>/secrets/<secret>, so a bare name is put in the
resource's project, as Cloud Run reads it. */}}
{{- define "cloudRunV2.secret" -}}
{{- $root := index . 0 -}}{{- $s := index . 1 -}}
{{- if or (eq ($root.Values.type | default "SERVICE") "SERVICE") (contains "/" $s) -}}
{{- $s -}}
{{- else -}}
{{- printf "projects/%s/secrets/%s" $root.Values.project_id $s -}}
{{- end -}}
{{- end -}}

{{/* cloudRunV2.sqlInstance: a Cloud SQL instance as the kind takes it.
RunService takes the connection name fabric's README passes
(<project>:<region>:<instance>); RunJob and RunWorkerPool take
projects/<p>/locations/<r>/instances/<i> (or projects/<p>/instances/<i>)
and send its connection name. */}}
{{- define "cloudRunV2.sqlInstance" -}}
{{- $root := index . 0 -}}{{- $i := index . 1 -}}
{{- $parts := splitList ":" $i -}}
{{- if or (eq ($root.Values.type | default "SERVICE") "SERVICE") (hasPrefix "projects/" $i) (ne (len $parts) 3) -}}
{{- $i -}}
{{- else -}}
{{- printf "projects/%s/locations/%s/instances/%s" (index $parts 0) (index $parts 1) (index $parts 2) -}}
{{- end -}}
{{- end -}}

{{/* cloudRunV2.probe: a liveness or startup probe, from fabric's object;
grpc, http_get and tcp_socket as given (the caller refuses what its kind
lacks). */}}
{{- define "cloudRunV2.probe" -}}
{{- if not (kindIs "invalid" .initial_delay_seconds) }}
initialDelaySeconds: {{ int .initial_delay_seconds }}
{{- end }}
{{- if not (kindIs "invalid" .timeout_seconds) }}
timeoutSeconds: {{ int .timeout_seconds }}
{{- end }}
{{- if not (kindIs "invalid" .period_seconds) }}
periodSeconds: {{ int .period_seconds }}
{{- end }}
{{- if not (kindIs "invalid" .failure_threshold) }}
failureThreshold: {{ int .failure_threshold }}
{{- end }}
{{- with .http_get }}
httpGet:
  {{- with .path }}
  path: {{ . | quote }}
  {{- end }}
  {{- if not (kindIs "invalid" .port) }}
  port: {{ int .port }}
  {{- end }}
  {{- with .http_headers }}
  httpHeaders:
    {{- range $k := keys . | sortAlpha }}
    - name: {{ $k | quote }}
      value: {{ index $.http_get.http_headers $k | quote }}
    {{- end }}
  {{- end }}
{{- end }}
{{- with .tcp_socket }}
tcpSocket:
  {{- if not (kindIs "invalid" .port) }}
  port: {{ int .port }}
  {{- end }}
{{- end }}
{{- with .grpc }}
grpc:
  {{- if not (kindIs "invalid" .port) }}
  port: {{ int .port }}
  {{- end }}
  {{- with .service }}
  service: {{ . | quote }}
  {{- end }}
{{- end }}
{{- end -}}

{{/* cloudRunV2.containers: the template's containers, in fabric's order
(by name) and with the fields fabric sets for the type:
  SERVICE     every field
  JOB         no liveness_probe, cpu_idle or startup_cpu_boost (fabric
              leaves them out); startup_probe.grpc is refused (RunJob has
              none)
  WORKERPOOL  no depends_on (fabric refuses it), ports or probes (fabric
              leaves them out) */}}
{{- define "cloudRunV2.containers" -}}
{{- $root := . -}}
{{- $t := .Values.type | default "SERVICE" -}}
{{- $cs := .Values.containers | default dict -}}
{{- range $name := keys $cs | sortAlpha }}
{{- $c := index $cs $name }}
- name: {{ $name | quote }}
  image: {{ $c.image | quote }}
  {{- if and $c.depends_on (ne $t "WORKERPOOL") }}
  dependsOn: {{ toJson $c.depends_on }}
  {{- end }}
  {{- with $c.command }}
  command: {{ toJson . }}
  {{- end }}
  {{- with $c.args }}
  args: {{ toJson . }}
  {{- end }}
  {{- $env := $c.env | default dict }}
  {{- $fromKey := $c.env_from_key | default dict }}
  {{- if or $env $fromKey }}
  env:
    {{- range $k := keys $env | sortAlpha }}
    - name: {{ $k | quote }}
      value: {{ index $env $k | quote }}
    {{- end }}
    {{- range $k := keys $fromKey | sortAlpha }}
    {{- $s := index $fromKey $k }}
    - name: {{ $k | quote }}
      valueSource:
        secretKeyRef:
          secretRef:
            external: {{ include "cloudRunV2.secret" (list $root $s.secret) | quote }}
          versionRef:
            external: {{ $s.version | quote }}
    {{- end }}
  {{- end }}
  {{- with $c.resources }}
  resources:
    {{- with .limits }}
    limits:
      {{- range $k := keys . | sortAlpha }}
      {{ $k | quote }}: {{ index $c.resources.limits $k | quote }}
      {{- end }}
    {{- end }}
    {{- if eq $t "SERVICE" }}
    {{- if not (kindIs "invalid" .cpu_idle) }}
    cpuIdle: {{ .cpu_idle }}
    {{- end }}
    {{- if not (kindIs "invalid" .startup_cpu_boost) }}
    startupCpuBoost: {{ .startup_cpu_boost }}
    {{- end }}
    {{- end }}
  {{- end }}
  {{- if and $c.ports (ne $t "WORKERPOOL") }}
  ports:
    {{- range $k := keys $c.ports | sortAlpha }}
    {{- $p := index $c.ports $k }}
    {{- $port := dict }}
    {{- if not (kindIs "invalid" $p.container_port) }}{{ $_ := set $port "containerPort" (int $p.container_port) }}{{ end }}
    {{- with $p.name }}{{ $_ := set $port "name" . }}{{ end }}
    - {{ toJson $port }}
    {{- end }}
  {{- end }}
  {{- with $c.volume_mounts }}
  {{- /* CloudSQL is the last mount in the list the API returns. */}}
  {{- $mounts := list }}
  {{- range $k := keys . | sortAlpha }}{{ if ne $k "cloudsql" }}{{ $mounts = append $mounts $k }}{{ end }}{{ end }}
  {{- if hasKey . "cloudsql" }}{{ $mounts = append $mounts "cloudsql" }}{{ end }}
  volumeMounts:
    {{- range $k := $mounts }}
    - name: {{ $k | quote }}
      mountPath: {{ index $c.volume_mounts $k | quote }}
    {{- end }}
  {{- end }}
  {{- if and $c.liveness_probe (eq $t "SERVICE") }}
  livenessProbe:
    {{- include "cloudRunV2.probe" $c.liveness_probe | trim | nindent 4 }}
  {{- end }}
  {{- if and $c.startup_probe (ne $t "WORKERPOOL") }}
  {{- if and (eq $t "JOB") $c.startup_probe.grpc }}
  {{- include "kcc.unsupported" (list $root (printf "containers.%s.startup_probe.grpc with type JOB" $name) true "RunJob's startupProbe has no grpc") }}
  {{- end }}
  startupProbe:
    {{- include "cloudRunV2.probe" $c.startup_probe | trim | nindent 4 }}
  {{- end }}
{{- end }}
{{- end -}}

{{/* cloudRunV2.volumes: the template's volumes, in fabric's order (by
name, the Cloud SQL ones last), as the type's kind takes them: RunService
has cloudSqlInstance.instances, RunJob cloudSqlInstance.instanceRefs and
RunWorkerPool cloudSQLInstance.instanceRefs; only RunJob and RunWorkerPool
have nfs. */}}
{{- define "cloudRunV2.volumes" -}}
{{- $root := . -}}
{{- $t := .Values.type | default "SERVICE" -}}
{{- $vs := .Values.volumes | default dict -}}
{{- $order := list -}}
{{- range $k := keys $vs | sortAlpha }}{{ if kindIs "invalid" (index $vs $k).cloud_sql_instances }}{{ $order = append $order $k }}{{ end }}{{ end -}}
{{- range $k := keys $vs | sortAlpha }}{{ if not (kindIs "invalid" (index $vs $k).cloud_sql_instances) }}{{ $order = append $order $k }}{{ end }}{{ end -}}
{{- range $k := $order }}
{{- $v := index $vs $k }}
- name: {{ $k | quote }}
  {{- with $v.secret }}
  secret:
    secretRef:
      external: {{ include "cloudRunV2.secret" (list $root .name) | quote }}
    {{- with .default_mode }}
    defaultMode: {{ atoi (toString .) }}
    {{- end }}
    {{- with .path }}
    items:
      - path: {{ . | quote }}
        {{- with $v.secret.version }}
        versionRef:
          external: {{ . | quote }}
        {{- end }}
        {{- with $v.secret.mode }}
        mode: {{ atoi (toString .) }}
        {{- end }}
    {{- end }}
  {{- end }}
  {{- with $v.empty_dir_size }}
  emptyDir:
    medium: MEMORY
    sizeLimit: {{ . | quote }}
  {{- end }}
  {{- with $v.nfs }}
  nfs:
    server: {{ .server | quote }}
    {{- with .path }}
    path: {{ . | quote }}
    {{- end }}
    {{- if not (kindIs "invalid" .is_read_only) }}
    readOnly: {{ .is_read_only }}
    {{- end }}
  {{- end }}
  {{- with $v.cloud_sql_instances }}
  {{- if eq $t "SERVICE" }}
  cloudSqlInstance:
    instances:
  {{- else if eq $t "JOB" }}
  cloudSqlInstance:
    instanceRefs:
  {{- else }}
  cloudSQLInstance:
    instanceRefs:
  {{- end }}
      {{- range $i := . }}
      - external: {{ include "cloudRunV2.sqlInstance" (list $root $i) | quote }}
      {{- end }}
  {{- end }}
{{- end }}
{{- end -}}

{{/* cloudRunV2.vpcAccess: the template's vpcAccess, as fabric's two
dynamic blocks: a connector (the created one or revision.vpc_access's;
not for a worker pool, which fabric leaves without), or direct VPC egress
through a network and subnet. */}}
{{- define "cloudRunV2.vpcAccess" -}}
{{- $t := .Values.type | default "SERVICE" -}}
{{- $va := (.Values.revision | default dict).vpc_access | default dict -}}
{{- $connector := include "cloudRunV2.connector" . -}}
{{- if eq $t "WORKERPOOL" }}{{ $connector = "" }}{{ end -}}
{{- $direct := or $va.subnet $va.network -}}
{{- if and $connector $direct -}}
{{- fail (printf "%s: revision.vpc_access sets both a connector (%s) and a network or subnet: Cloud Run takes one vpc_access, either a connector or direct VPC egress" .Chart.Name $connector) -}}
{{- end -}}
{{- if $connector }}
vpcAccess:
  connectorRef:
    external: {{ $connector | quote }}
  {{- with $va.egress }}
  egress: {{ . | quote }}
  {{- end }}
{{- else if $direct }}
vpcAccess:
  {{- with $va.egress }}
  egress: {{ . | quote }}
  {{- end }}
  {{- $ni := dict }}
  {{- with $va.network }}{{ $_ := set $ni "networkRef" (dict "external" .) }}{{ end }}
  {{- with $va.subnet }}{{ $_ := set $ni "subnetworkRef" (dict "external" .) }}{{ end }}
  {{- with $va.tags }}{{ $_ := set $ni "tags" . }}{{ end }}
  networkInterfaces:
    - {{ toJson $ni }}
{{- end }}
{{- end -}}

{{/* cloudRunV2.validate: fabric's variable validations, and the
refusals of what Config Connector v1.160.0 cannot express. Included once,
by main.yaml, before anything renders. */}}
{{- define "cloudRunV2.validate" -}}
{{- $v := .Values -}}
{{- $chart := .Chart.Name -}}
{{- $t := $v.type | default "SERVICE" -}}
{{- include "kcc.unsupported" (list $ "context" $v.context "use Bundt expressions (${...}) and valueFrom in the component's inputs instead") -}}
{{- include "kcc.alpha" (list $ "type" (eq $t "WORKERPOOL") "RunWorkerPool") -}}
{{- include "kcc.names" (list $ (list (include "cloudRunV2.key" .) "serviceAccount" "vpcConnector")) -}}
{{- $_ := include "kcc.abandon" . -}}
{{- if eq (toString $v.managed_revision) "false" -}}
{{- fail (printf "%s: managed_revision false is not supported: Config Connector has no ignore_changes, so it would put back the containers, revision name and labels of every revision deployed outside Bundt (gcloud run deploy, a pipeline); deploy revisions through the component's inputs instead (docs/gcp-inventory.md, \"Gaps\")" $chart) -}}
{{- end -}}
{{- with $v.binary_authorization -}}
{{- include "kcc.unsupported" (list $ "binary_authorization.policy" .policy "RunService, RunJob and RunWorkerPool have no binaryAuthorization.policy (Config Connector v1.160.0)") -}}
{{- end -}}
{{- /* containers: fabric's validations. */ -}}
{{- range $name, $c := ($v.containers | default dict) -}}
{{- range $k, $_ := (($c.resources | default dict).limits | default dict) -}}
{{- if not (has $k (list "cpu" "memory" "nvidia.com/gpu")) -}}
{{- fail (printf "%s: Only following resource limits are available: 'cpu', 'memory' and 'nvidia.com/gpu'." $chart) -}}
{{- end -}}
{{- end -}}
{{- if and (eq $t "WORKERPOOL") $c.depends_on -}}
{{- fail (printf "%s: depends_on is not supported when type is WORKERPOOL." $chart) -}}
{{- end -}}
{{- end -}}
{{- /* revision: fabric's validations, then the fields no kind has. */ -}}
{{- $r := $v.revision | default dict -}}
{{- if not (kindIs "invalid" $r.gen2_execution_environment) }}{{ fail (printf "%s: Field gen2_execution_environment has moved to var.service_config." $chart) }}{{ end -}}
{{- if not (kindIs "invalid" $r.job) }}{{ fail (printf "%s: Field job has moved to var.job_config." $chart) }}{{ end -}}
{{- if not (kindIs "invalid" $r.max_concurrency) }}{{ fail (printf "%s: Field max_concurrency has moved to var.service_config." $chart) }}{{ end -}}
{{- if not (kindIs "invalid" $r.max_instance_count) }}{{ fail (printf "%s: Field max_instance_count has moved to var.service_config." $chart) }}{{ end -}}
{{- if not (kindIs "invalid" $r.min_instance_count) }}{{ fail (printf "%s: Field min_instance_count has moved to var.service_config." $chart) }}{{ end -}}
{{- $va := $r.vpc_access | default dict -}}
{{- if and $va.network (not $va.subnet) -}}
{{- fail (printf "%s: When providing vpc_access.network provide also vpc_access.subnet." $chart) -}}
{{- end -}}
{{- if and $va.connector $v.vpc_connector_create -}}
{{- fail (printf "%s: Either provide connector to create in var.vpc_connector_create or provide externally managed connector in var.revision.vpc_access.connector" $chart) -}}
{{- end -}}
{{- include "kcc.unsupported" (list $ "revision.gpu_zonal_redundancy_disabled" $r.gpu_zonal_redundancy_disabled "RunService, RunJob and RunWorkerPool have no gpuZonalRedundancyDisabled (Config Connector v1.160.0)") -}}
{{- if ne $t "WORKERPOOL" -}}
{{- include "kcc.unsupported" (list $ (printf "revision.node_selector with type %s" $t) $r.node_selector "RunService and RunJob have no nodeSelector (Config Connector v1.160.0; RunWorkerPool has one)") -}}
{{- end -}}
{{- if ne $t "SERVICE" -}}
{{- include "kcc.unsupported" (list $ (printf "revision.labels with type %s" $t) $r.labels "RunJob and RunWorkerPool have no template labels (Config Connector v1.160.0)") -}}
{{- end -}}
{{- /* service_config: fabric's validations, then the fields RunService
lacks. */ -}}
{{- $sc := $v.service_config | default dict -}}
{{- $et := $sc.eventarc_triggers | default dict -}}
{{- if and $et.audit_log (not $et.service_account_email) -}}
{{- fail (printf "%s: When setting var.eventarc_triggers.audit_log provide service_account_email." $chart) -}}
{{- end -}}
{{- if and (ne $t "SERVICE") (or $et.audit_log $et.pubsub $et.storage) -}}
{{- fail (printf "%s: service_config.eventarc_triggers need type SERVICE: an Eventarc trigger's destination is a Cloud Run service" $chart) -}}
{{- end -}}
{{- include "kcc.unsupported" (list $ "service_config.default_uri_disabled" $sc.default_uri_disabled "RunService has no defaultUriDisabled (Config Connector v1.160.0)") -}}
{{- include "kcc.unsupported" (list $ "service_config.iap_config" $sc.iap_config "RunService has no iapEnabled (Config Connector v1.160.0); IAM on the IAP resource alone would not turn IAP on") -}}
{{- include "kcc.unsupported" (list $ "service_config.invoker_iam_disabled" $sc.invoker_iam_disabled "RunService has no invokerIamDisabled (Config Connector v1.160.0); grant roles/run.invoker to allUsers in iam instead") -}}
{{- include "kcc.unsupported" (list $ "service_config.multi_region_settings" $sc.multi_region_settings "RunService has no multiRegionSettings (Config Connector v1.160.0)") -}}
{{- include "kcc.unsupported" (list $ "service_config.workload_identity_config" $sc.workload_identity_config "RunService has no workloadIdentityConfig (Config Connector v1.160.0)") -}}
{{- /* volumes: one type each (fabric), then the kinds' gaps. */ -}}
{{- range $k, $vol := ($v.volumes | default dict) -}}
{{- $n := 0 -}}
{{- range $f, $x := $vol }}{{ if not (kindIs "invalid" $x) }}{{ $n = add1 $n }}{{ end }}{{ end -}}
{{- if ne (int $n) 1 -}}
{{- fail (printf "%s: Only one type of volume can be defined at a time." $chart) -}}
{{- end -}}
{{- include "kcc.unsupported" (list $ (printf "volumes.%s.gcs" $k) $vol.gcs "RunService has no gcs volume, and RunJob and RunWorkerPool send bucketRef.external (projects/<p>/buckets/<b> or gs://<b>) to Cloud Run as the bucket's name (Config Connector v1.160.0)") -}}
{{- if eq $t "SERVICE" -}}
{{- include "kcc.unsupported" (list $ (printf "volumes.%s.nfs with type SERVICE" $k) $vol.nfs "RunService has no nfs volume (Config Connector v1.160.0; RunJob and RunWorkerPool have one)") -}}
{{- end -}}
{{- end -}}
{{- /* workerpool_config: RunWorkerPool's scaling has manualInstanceCount
only. */ -}}
{{- $ws := ($v.workerpool_config | default dict).scaling | default dict -}}
{{- include "kcc.unsupported" (list $ "workerpool_config.scaling.mode" $ws.mode "RunWorkerPool's scaling has manualInstanceCount only (Config Connector v1.160.0)") -}}
{{- include "kcc.unsupported" (list $ "workerpool_config.scaling.max_instance_count" $ws.max_instance_count "RunWorkerPool's scaling has manualInstanceCount only (Config Connector v1.160.0)") -}}
{{- include "kcc.unsupported" (list $ "workerpool_config.scaling.min_instance_count" $ws.min_instance_count "RunWorkerPool's scaling has manualInstanceCount only (Config Connector v1.160.0)") -}}
{{- if and (eq $t "WORKERPOOL") $v.tag_bindings -}}
{{- fail (printf "%s: tag_bindings are not supported for type WORKERPOOL (fabric: not yet supported for Worker Pools)" $chart) -}}
{{- end -}}
{{- end -}}
