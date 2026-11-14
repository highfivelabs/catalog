# cloud-function-v2

A Cloud Run function (Cloud Functions 2nd gen) built from a bundle in Cloud
Storage, with its optional source bucket, service accounts, VPC Access
connector and IAM, as Config Connector and config-connector-extensions
objects. A port of Cloud Foundation Fabric's
[`modules/cloud-function-v2`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/cloud-function-v2)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-cloud-function-v2` (`package.yaml`). Checked against Config Connector
v1.160.0 and config-connector-extensions at `0ee17dd4`.

## Example

```yaml
project_id: my-project
region: europe-west1
name: test-cf-http
bucket_name: my-bucket
bundle_config: {path: "gs://my-bucket/bundles/function.zip"}
```

renders the `CloudFunctions2Function` `test-cf-http`, its
`IAMServiceAccount` and the account's two project roles
(`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.function`, `names.bucket`, `names.serviceAccount`, `names.triggerServiceAccount`, `names.vpcConnector` | not fabric variables: those names in full, used as given (no `namePrefix`, no `prefix`) and checked (63, 63, 30, 30 and 25 characters; a leading letter but for the bucket) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every derived name starts with `<namePrefix>-`. `bucket_name` without `bucket_config` names a bucket the chart does not make and is never changed. Empty changes nothing |
| `labels` | Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label (fabric's `labels`, on the function and the bucket, are these; the function takes them in `spec.labels`) |
| `tags` | cloud labels on every object (Google Cloud labels) |
| `deletion_policy` | not a fabric variable: `DELETE` (default) or `ABANDON`; `PREVENT` is refused (`docs/design.md`, "Deletion") |
| `project_id`, `region`, `name`, `prefix`, `description`, `kms_key` | the function's project, location, name (`<prefix>-<name>`), description and `kmsKeyName` |
| `bundle_config` | `path`, a Cloud Storage object URI `gs://<bucket>/<object>.zip`, is the function's `storageSource`: the object, in the bucket fabric's `local.bucket` names (below). A local zip or folder, and `folder_options`, are **refused** (below) |
| `bucket_name`, `bucket_config` | the source bucket. With `bucket_config`, a `StorageBucket` `<prefix>-<bucket_name>` (uniform access, in `bucket_config.location` or the region; `lifecycle_delete_age_days` adds a Delete rule for archived versions and turns versioning on; `force_destroy` is Config Connector's `force-destroy` annotation). Without, `bucket_name` as given |
| `build_environment_variables`, `build_service_account`, `build_worker_pool`, `docker_repository_id` | `buildConfig`'s `environmentVariables`, `serviceAccount`, `workerPool`, `dockerRepository` |
| `function_config` | `runtime`, `entry_point` (build); `cpu`, `memory_mb` (as `<n>M`), `instance_count` (max), `min_instance_count`, `max_instance_request_concurrency`, `timeout_seconds`, `binary_authorization_policy` (service); `automatic_update_policy` and `on_deploy_update_policy` as the empty policies (both true is refused with fabric's message) |
| `environment_variables`, `ingress_settings`, `secrets` | `serviceConfig`'s `environmentVariables`, `ingressSettings`, `secretEnvironmentVariables` (first version, else `latest`) and `secretVolumes` (`version:path`) |
| `direct_vpc_egress` | `directVpcEgress` and one `directVpcNetworkInterface` |
| `vpc_connector`, `vpc_connector_create` | `vpcConnector` (the created connector's ID, else `vpc_connector.name`) and `vpcConnectorEgressSettings`; `vpc_connector_create` a `VPCAccessConnector` named its `name` or `name` |
| `service_account_config` | with `create` (the default), an `IAMServiceAccount` (`name` or `name`; `display_name`, else the account's name) and one `IAMPolicyMember` on the project per `roles` entry; else `email`, if any, runs the function |
| `trigger_config` | `eventTrigger`: `event_type`, `pubsub_topic`, `region` (else the function's), `event_filters`, `retry_policy`, and `service_account_email` or, with `service_account_create`, an `IAMServiceAccount` `tf-cf-trigger-<name>` |
| `iam` | one `IAMBinding` (config-connector-extensions, `iam.gcp.hfl.dev/v1beta1`) per role on the function, but `roles/run.invoker`, which is an `IAMBinding` on the function's Cloud Run service with the listed members and the created trigger account. With a created trigger account and no `roles/run.invoker`, the account gets that role additively (`IAMPolicyMember`) |
| `context` | **refused**: Bundt's `${...}` expressions and `valueFrom` replace fabric's `$context` lookups |

## Outputs

| Output | From |
| --- | --- |
| `bucket_name` | the bucket of the function's source (fabric's `local.bucket`) |
| `function_name` | the function's name |
| `id` | `projects/<project>/locations/<region>/functions/<name>` |
| `invoke_command` | for an HTTP function (no `trigger_config`), fabric's `curl` command with the function's URL; null until the function reports it |
| `uri` | the function's URL, `status.observedState.url`; null until reported |
| `service_account_email`, `service_account_iam_email` | the created account's email from its status, else `service_account_config.email`; the second prefixed `serviceAccount:` |
| `trigger_service_account_email`, `trigger_service_account_iam_email` | the created trigger account's email from its status, else `trigger_config.service_account_email`; the second prefixed `serviceAccount:` |
| `vpc_connector` | `projects/<project>/locations/<region>/connectors/<name>` of the created connector, else null |

These are fabric's declared outputs, selected (`docs/design.md`,
"Outputs"); `bucket`, `function`, `service_account` and
`trigger_service_account` (whole Terraform objects) are not outputs.

## Differences from the module

- **The bundle must already be in Cloud Storage.** fabric zips a local
  folder (`archive_file`) or uploads a local zip
  (`google_storage_bucket_object`) from the machine running Terraform. A
  chart has no files to read, and config-connector-extensions'
  `StorageBucketObject` (`v1alpha1`) takes text content, not an archive, so
  a path that does not start with `gs://` and `folder_options` are refused
  by name. Upload the bundle (a CI step, `gcloud storage cp`) and give its
  URI; the function's source is that object in the bucket fabric's
  `local.bucket` names, as fabric's is.
- `uri` is the function's URL (`https://<region>-<project>.cloudfunctions.net/<name>`):
  config-connector-extensions' `CloudFunctions2Function` reports
  `observedState.url`, not `serviceConfig.uri` (the `run.app` URI fabric's
  `uri` reads). Both reach the function; `invoke_command` uses the URL.
- `roles/run.invoker` is exact (`IAMBinding`), as fabric's
  `google_cloud_run_service_iam_binding` is, rather than an
  `IAMPartialPolicy`.
- The service accounts' emails in the function's spec are computed from
  their IDs (`<id>@<project>.iam.gserviceaccount.com`), so the function
  does not wait on the accounts' status.
- fabric's `replace_triggered_by` on the IAM bindings (recreate them when the
  function is replaced) has no equivalent: the bindings name the function
  by name and Config Connector re-applies them.

## From Terraform

A `module "x" { source = ".../modules/cloud-function-v2" ... }` block's
arguments become the values unchanged, except refused fields: a local
`bundle_config.path` must become the `gs://` URI of the uploaded bundle
(fabric's own upload names it `bundle-<md5>.zip`, or the zip's basename, in
the bucket). To adopt an existing function, bucket and accounts, keep their
names: Config Connector acquires the resources of those names
(`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/cloud-function-v2`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloud-function-v2)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=cloud-function-v2`: render cases `basic`, `pubsub-trigger`,
`iam`, `bucket` and `service-account` (fabric's README examples, with the
bundle in Cloud Storage), `trigger-invoker`, `direct-egress`, `full` (every
field the chart carries), `names` and `mock`, each validated against Config
Connector v1.160.0's CRD schemas and config-connector-extensions'
(`CloudFunctions2Function`, `IAMBinding`), and the refusals in
`tests/*.fail.yaml`.

Applied to the fake cloud on 2026-11-12 on an offload VM (`task test-mock
MOCK_CHARTS=cloud-function-v2`, run `off-catalog-1113030127-28473`, at
config-connector-extensions `0ee17dd4`): `tests/mock.values.yaml`, a
function with a Pub/Sub trigger, the bucket the chart makes for its
source, its service account with one project role, and a trigger account
the chart makes with `roles/run.invoker` on the function's Cloud Run
service: all 6 objects Ready, the outputs evaluated, all deleted. mockgcp
does not report the function's URL, so `uri` and `invoke_command` were null
there. `iam` is not in the fake-cloud case: it is render-tested only
(`tests/golden/iam.yaml`), as are the VPC Access connector and direct VPC
egress.

Live (`hack/live-apply.sh` `LIVE_CHARTS=cloud-function-v2`, `tests/live.yaml`, a
one-file Python bundle `tests/live.pre.sh` puts in a bucket of the run):
failed, on config-connector-extensions' side. In both runs (2026-11-14,
`cat-11140025-cb6a` as cce-live-tests and `cat-11140120-96a6` as
catalog-live-tests, config-connector-extensions `c2f0c7d2`) `CloudFunctions2Function`'s create returned
"Error 400: Invalid resource name '' for pattern
'projects/{project=*}/locations/{location=*}/functions/{function=*}'":
the extension's generated create sends no function name. The
function's service account was Ready as catalog-live-tests;
cce-live-tests may not create accounts (`iam.serviceAccounts.create`
denied). Nothing was left after either run.

config-connector-extensions `aec29642` sends the name. The rerun
(2026-11-14, `cat-11140810-5876`, offload VM
`off-catalog-1114080558-20156`, as catalog-live-tests, with the compute
default service account now holding `roles/cloudbuild.builds.builder`)
**passed**: the function and its service account Ready, deleted and gone
from Google Cloud, and the outputs (the function's `uri` among them)
evaluated. Nothing was left.

## Changes

- **0.1.0** (2026-11-12): the port: the function from a Cloud Storage
  bundle, its source bucket, service accounts, VPC Access connector, and
  IAM on the function and its Cloud Run service.
