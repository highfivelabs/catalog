# cloud-run-v2

A Cloud Run service, job or worker pool with its service account, IAM,
Eventarc triggers, VPC Access connector and tag bindings. A port of Cloud
Foundation Fabric's
[`modules/cloud-run-v2`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/cloud-run-v2)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-cloud-run-v2` (`package.yaml`). The service (`RunService`), job
(`RunJob`), service account, Eventarc triggers, connector and tag bindings
are Config Connector kinds (`v1beta1`); a worker pool is Config Connector's
`RunWorkerPool` (`v1alpha1`). IAM on a service or job is Config
Connector's `IAMPartialPolicy`; IAM on a worker pool is
config-connector-extensions' `IAMBinding` (`v1beta1`, at `d54a2075`), since
Config Connector's IAM kinds cannot reference a worker pool.

## Example

```yaml
project_id: my-project
region: europe-west1
name: example-hello
containers:
  hello:
    image: us-docker.pkg.dev/cloudrun/container/hello
    env: {VAR1: VALUE1, VAR2: VALUE2}
    env_from_key:
      SECRET1: {secret: credentials, version: "1"}
iam:
  roles/run.invoker: [allUsers]
```

renders the service `example-hello` in `europe-west1` running as the
service account `example-hello`, which gets `roles/logging.logWriter` and
`roles/monitoring.metricWriter` on the project, and `roles/run.invoker` for
`allUsers` on the service (`tests/golden/basic.yaml`; fabric's README
example). `type: JOB` renders a job instead, and `type: WORKERPOOL` (with
`allow_alpha: true`) a worker pool.

## Values

The module's variables, with the same names, types and defaults. The
chart carries 20 of the 21; one is refused, and eight are accepted in part.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.service`, `names.job` or `names.workerPool` (the one of the type), `names.serviceAccount` and `names.vpcConnector` set those names in full |
| `namePrefix` | not a fabric variable: `<namePrefix>-` in front of the resource's, service account's, connector's and Eventarc triggers' names |
| `labels` | fabric's resource labels, with the catalog's meaning: labels on every object; an unprefixed one is a cloud label of every resource (a worker pool's in `spec.labels`) |
| `tags` | not a fabric variable: cloud labels on every resource |
| `allow_alpha` | not a fabric variable: required for `type: WORKERPOOL` |
| `deletion_policy` | not a fabric variable: `DELETE` (default) or `ABANDON`; `PREVENT` is refused |
| `project_id`, `region`, `name` | the resource's `projectRef`, `location` and `resourceID` (at most 49 characters: Cloud Run's Admin API v2 takes IDs of fewer than 50) |
| `type` | `SERVICE` (default) a `RunService`, `JOB` a `RunJob`, `WORKERPOOL` a `RunWorkerPool`, which is `v1alpha1`: **needs `allow_alpha: true`** |
| `containers` | the template's containers, by name: `image`, `dependsOn`, `command`, `args`, `env` (plain values, then `env_from_key` as Secret Manager references by name and version), `resources` (`limits`; `cpuIdle` and `startupCpuBoost` for a service), `ports`, `volumeMounts` (`cloudsql` last, as fabric orders them), `livenessProbe` (a service) and `startupProbe` (a service or job) with `httpGet`, `tcpSocket` and `grpc`. As fabric, a job drops `liveness_probe`, `cpu_idle` and `startup_cpu_boost`, and a worker pool `ports` and the probes. **`startup_probe.grpc` is refused for a job** (a gap: `RunJob` has none) |
| `binary_authorization` | `binaryAuthorization` (`breakglassJustification`, `useDefault`). **`policy` is refused** (a gap: no kind has it) |
| `deletion_protection` | accepted and not rendered (below) |
| `encryption_key` | the template's `encryptionKeyRef.external` |
| `iam` | a service's or job's roles in one `IAMPartialPolicy`; a worker pool's one `IAMBinding` per role, exact per role |
| `job_config` | a job's `taskCount`, `maxRetries` and `timeout` |
| `launch_stage` | `launchStage` |
| `managed_revision` | `true` (default) renders the resource as fabric's managed variant. **`false` is refused** (below) |
| `revision` | `name` as the revision `<name>-<revision.name>` (a service or worker pool), `labels` as the template's labels (a service), `node_selector` (a worker pool), `vpc_access` as the template's `vpcAccess`: a connector (a service or job; fabric gives a worker pool none) or direct VPC egress with `networkInterfaces`. `timeout` is accepted and unused, as in fabric. **Refused** (gaps): `gpu_zonal_redundancy_disabled` (no kind has it), `node_selector` for a service or job, `labels` for a job or worker pool (`RunJob` and `RunWorkerPool` have no template labels). The deprecated fields stop the render with fabric's messages |
| `service_config` | a service's `customAudiences`, `ingress`, `traffic`, the template's `executionEnvironment` (GEN1, or GEN2 with `gen2_execution_environment`), `maxInstanceRequestConcurrency`, `scaling` and `timeout`; `eventarc_triggers` as one `EventarcTrigger` each (`audit-log-<key>`, `pubsub-<key>`, `storage-<key>`) delivering to the service, with `service_account_email`. **Refused** (gaps: `RunService` lacks the fields): `default_uri_disabled`, `iap_config`, `invoker_iam_disabled`, `multi_region_settings`, `workload_identity_config` |
| `service_account_config` | with `create` (default) an `IAMServiceAccount` named `name` (else the resource's name) and one `IAMPolicyMember` on the project per role; otherwise `email`, or none (the Compute Engine default account) |
| `tag_bindings` | one `TagsLocationTagBinding` per entry on `//run.googleapis.com/<id>`, in the region; a worker pool's stop the render, as fabric's (not yet supported for worker pools) |
| `volumes` | the template's volumes, by name, the Cloud SQL ones last: `secret` (by name, with `defaultMode`, and one item with `path`, `version` and `mode`), `empty_dir_size` (a memory `emptyDir`), `cloud_sql_instances`, and `nfs` for a job or worker pool. **Refused** (gaps): `gcs` (below), `nfs` for a service (`RunService` has none) |
| `vpc_connector_create` | a `VPCAccessConnector` named `name` (else the resource's name), used by a service or job by its full name |
| `workerpool_config` | a worker pool's `scaling.manualInstanceCount`. **`scaling.mode`, `max_instance_count` and `min_instance_count` are refused** (a gap: `RunWorkerPool`'s scaling has only `manualInstanceCount`) |
| `context` | **refused when set** (by design): Bundt expressions (`${...}`) and `valueFrom` replace fabric's `$context` lookups |

Secret values are never taken: `env_from_key` and secret volumes name
Secret Manager secrets and versions. A bare secret name is in the
resource's project: a service passes it as given; a job or worker pool
takes `projects/<project>/secrets/<secret>`, which the chart writes. A
job's or worker pool's Cloud SQL instance (`<project>:<region>:<instance>`,
as fabric's README passes it) becomes
`projects/<project>/locations/<region>/instances/<instance>`, the form
`RunJob` and `RunWorkerPool` take. A Pub/Sub trigger's bare topic name
becomes `projects/<project>/topics/<topic>`.

## Outputs

| Output | From |
| --- | --- |
| `id` | `projects/<project>/locations/<region>/<services\|jobs\|workerPools>/<name>` |
| `resource_name` | the resource's name |
| `service_name` | the service's name; null for a job or worker pool |
| `service_uri` | the service's `status.uri` (null until Cloud Run reports it); `""` for a job or worker pool, as fabric's |
| `invoke_command` | fabric's: a `curl` to the service's URI (null until it is known), `gcloud run jobs execute` for a job, `""` for a worker pool |
| `service_account_email`, `service_account_iam_email` | the created account's `status.email`, else `service_account_config.email` |
| `vpc_connector` | the created connector's ID, else null |

Fabric's whole-object outputs (`job`, `resource`, `service`,
`service_account`) are left out (`docs/design.md`, "Outputs").

## Differences from the module

- **`managed_revision: false` is refused.** Fabric's unmanaged variants
  tell Terraform to ignore changes to the template's containers, revision
  and labels, so revisions can be deployed outside Terraform (`gcloud run
  deploy`, a pipeline). Config Connector has no `ignore_changes`: it
  reconciles the whole template, and would put back every revision
  deployed outside Bundt (`cnrm.cloud.google.com/reconcile-interval-in-seconds:
  "0"` stops only the periodic reconcile; the next change to any input
  would still send the old containers). Deploy revisions through the
  component's inputs instead.
- **`deletion_protection`** is accepted and does nothing: it is the
  Terraform provider's own guard against destroy, and the kinds have none.
  `deletion_policy: ABANDON` keeps the resource when its object is deleted.
- **Cloud Storage volumes (`gcs`) are refused for every type.**
  `RunService` has no `gcs` volume. `RunJob` and `RunWorkerPool` have one,
  but Config Connector v1.160.0 sends `bucketRef.external`, which it
  accepts only as `projects/<p>/buckets/<b>` or `gs://<b>`, to Cloud Run as
  the bucket's name, which Cloud Run takes as the bare name
  (`pkg/controller/direct/run/resolverefs.go` and `mapper.generated.go`).
- **IAP is refused.** `iap_config` turns on IAP (`iap_enabled`) and grants
  `roles/iap.httpsResourceAccessor`. config-connector-extensions'
  `IAMBinding` and `IAMMember` take the IAP resource
  (`IAPWebCloudRunService`), but `RunService` has no `iapEnabled`, so the
  grants would not turn IAP on.
- **Eventarc triggers need `type: SERVICE`.** Fabric makes them for any
  type, pointing at a Cloud Run service of the job's or pool's name, which
  Eventarc would refuse; the chart stops instead.
- **A connector and direct VPC egress together** stop the render: fabric
  would write two `vpc_access` blocks, which Terraform refuses.
- **References by name.** The resource names its service account,
  connector, key, secrets and networks by their full names, and the
  triggers and a worker pool's IAM name the resource by its full name, so
  each can be deleted after the object it names is gone.
- **Eventarc trigger names** are fabric's (`pubsub-<key>`, ...), with the
  namePrefix in front; `names` has no key for them.
- **Fabric's README examples** set attributes the variables do not have
  (`service_config.vpc_access` in "VPC Access Connector",
  `service_config.max_instance_count` in "Direct VPC Egress",
  `gcs.mount_options` in "Mounting GCS buckets"); Terraform drops them
  silently, the chart's schema refuses them. The tests put the connector
  in `revision.vpc_access`, the variable's place for it.

## From Terraform

A `module "x" { source = ".../modules/cloud-run-v2" ... }` block's
arguments become the values unchanged, with `allow_alpha: true` for
`type = "WORKERPOOL"`. The service, job or worker pool, its service
account and connector keep their names, so they adopt what Terraform made
(`docs/design.md`, "From Terraform"). A module with
`managed_revision = false` has to move its deployments into the
component's inputs first.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/cloud-run-v2`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloud-run-v2)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=cloud-run-v2`: render cases `basic`, `secret-volume`,
`cloudsql`, `direct-vpc`, `vpc-connector`, `connector-create`,
`connector-shared-vpc`, `cmek`, `otel-sidecar`, `eventarc-pubsub`,
`eventarc-audit-log`, `eventarc-storage`, `service-account`,
`external-sa`, `job`, `tags`, `job-tags`, `traffic` and `workerpool`
(fabric's README examples; the worker pool without
`gpu_zonal_redundancy_disabled`), `full`, `full-job` and
`full-workerpool` (every field the chart carries, per type), `names` and
`mock`, validated against Config Connector v1.160.0's CRD schemas and
config-connector-extensions' (`IAMBinding`), and the refusals in
`tests/*.fail.yaml` (fabric's README examples for IAP, multi-region,
security, invoker IAM, agent identity, Cloud Storage mounts and GPUs among
them).

Applied to the fake cloud on 2026-11-13 on an offload VM (`task test-mock
MOCK_CHARTS=cloud-run-v2`, run `off-catalog-1113135319-613`, at
config-connector-extensions `d54a2075`): `tests/mock.values.yaml`, a
service with the service account the chart makes, one project role for it
and `roles/run.invoker` on the service: all 4 objects Ready, the outputs
evaluated, all deleted. mockgcp does not report the service's
`status.uri`, so `service_uri` and `invoke_command` were null there. Jobs,
worker pools, Eventarc triggers (the harness loads no Eventarc CRDs), the
VPC Access connector and tag bindings are render-tested only.

Not applied live: live runs are pending KEYLIVE.

## Changes

- **0.1.0** (2026-11-13): the port: a Cloud Run service, job or worker
  pool, its service account, IAM, Eventarc triggers, VPC Access connector
  and tag bindings.
