# endpoints

A Cloud Endpoints service, from an OpenAPI document or a gRPC service
configuration, and IAM on it. A port of Cloud Foundation Fabric's
[`modules/endpoints`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/endpoints)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-endpoints` (`package.yaml`). Config Connector has no kind for a
Cloud Endpoints service; the chart uses config-connector-extensions'
`EndpointsService` (`servicemanagement.gcp.hfl.dev/v1alpha1`) and
`IAMBinding` (`iam.gcp.hfl.dev/v1beta1`), at `d54a2075`.

**The chart needs `allow_alpha: true`.** `EndpointsService` is
`v1alpha1`, so every render without it stops (`docs/design.md`, "Alpha
kinds").

## Example

```yaml
allow_alpha: true
project_id: my-project
service_name: YOUR-API.endpoints.YOUR-PROJECT-ID.cloud.goog
openapi_config: {yaml_path: configs/endpoints/openapi.yaml}
iam:
  roles/servicemanagement.serviceController:
    - serviceAccount:123456890-compute@developer.gserviceaccount.com
files_data:
  openapi_config: |
    swagger: "2.0"
    info:
      title: "Endpoints Example"
      version: "1.0.0"
    host: "echo-api.endpoints.YOUR-PROJECT-ID.cloud.goog"
```

renders the `EndpointsService` `YOUR-API.endpoints.YOUR-PROJECT-ID.cloud.goog`
with that document, which config-connector-extensions' controller submits
and rolls out, and one `IAMBinding` on it (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults. The
chart carries all five; three in part.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.service` sets the service's name in full, in place of `service_name` |
| `namePrefix` | not a fabric variable: checked, and put into no name: the service's name is a DNS name given in full |
| `labels`, `tags` | not fabric variables: Kubernetes labels on every object (a Cloud Endpoints service has no cloud labels) |
| `allow_alpha` | not a fabric variable: required, `true` |
| `project_id` | the service's `projectRef` (the producer project) and every object's project annotation. Required: fabric's `null` takes the Terraform provider's project, and a chart has none |
| `service_name` | the service's name (`resourceID`) |
| `openapi_config` | the service's `openapiConfig`: the document from `files_data.openapi_config`. `yaml_path` is accepted and ignored: a chart cannot read the caller's files |
| `grpc_config` | the service's `grpcConfig` and `protocOutputBase64`: the files' contents from `files_data.grpc_config` and `files_data.protoc_output_base64`. `yaml_path` and `protoc_output_path` are accepted and ignored |
| `iam` | one `IAMBinding` per role on the service: exact, as fabric's `google_endpoints_service_iam_binding` |
| `files_data` | not a fabric variable: `openapi_config` (the OpenAPI document), `grpc_config` (the gRPC service configuration) and `protoc_output_base64` (the protoc output, base64-encoded, as fabric's `base64encode(file(...))` sends it) |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the service |

One of `openapi_config` and `grpc_config` is required, and both together
stop the render (the API takes one configuration; fabric would send both).
A path whose contents are missing from `files_data` stops it too, naming
the file.

## Outputs

| Output | From |
| --- | --- |
| `service_name` | the service's name |
| `endpoints_service` | the service's name, its ID. fabric's output is the whole object; a Package outputs the field a consumer takes (`docs/design.md`, "Outputs") |
| `endpoints` | the active configuration's endpoints, from the service's `status.observedState.endpoints`; `[]` until it reports them |

## Differences from the module

- **The files are contents, not paths** (above).
- **A deleted service's name.** The API keeps a deleted service, and its
  name, for 30 days. Terraform then fails to create one of the same name;
  config-connector-extensions' controller undeletes it instead and rolls
  the configuration out again.

## From Terraform

A `module "x" { source = ".../modules/endpoints" ... }` block's arguments
become the values unchanged, with `allow_alpha: true` and the files'
contents under `files_data`. The service keeps its name, so it adopts the
service Terraform made (`docs/design.md`, "From Terraform"); its first
reconcile submits the files as a new configuration and rolls it out, and
later ones only when the files change. IAM is `IAMBinding`, exact per role as
fabric's is.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/endpoints`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/endpoints)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=endpoints`: render cases `basic` (fabric's README example
"OpenAPI", the role given as `roles/servicemanagement.serviceController`:
fabric's leaves out `roles/`, which the IAM API refuses), `grpc`, `full`,
`names` and `mock`, each validated against config-connector-extensions'
CRDs (`crds/config-connector-extensions`), and the refusals in
`tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`): a service from an
OpenAPI document and one role on it. On 2026-11-13 (offload VM
`off-catalog-1113091757-26368`, config-connector-extensions `d54a2075`,
whose fake Service Management sits in front of mockgcp) both objects
became Ready, the outputs evaluated and both were deleted.

Not applied live: the live-test service account has no Service Management
role (config-connector-extensions' own live test of the kind skips for
that reason), and live runs wait on the live-test account's key
(KEYLIVE).

## Changes

- **0.1.0** (2026-11-13): the port: the service from an OpenAPI document
  or a gRPC configuration, and IAM on it.
