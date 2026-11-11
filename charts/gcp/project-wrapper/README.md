# project-wrapper

A Google Cloud project with an opinionated baseline for running GKE in it:
the catalog's [`project`](../project/README.md) chart (a port of Cloud
Foundation Fabric's `modules/project` at v60.0.0) as a Helm dependency,
plus the APIs a cluster needs and a dedicated node service account named
for its job, holding only the roles nodes need. Bundt Package
`gcp-project-wrapper` (`package.yaml`). Checked against Config Connector
v1.160.0.

It is not a module port, so it has no `upstream.yaml`: `Chart.yaml` marks
it `hfl.dev/kind: wrapper`, and its dependency carries the pin. Creating a
project needs folder or organization roles, as with `project`.

## Example

```yaml
required_labels: [env]
project:
  name: gke-dev
  prefix: hfl
  parent: folders/1234567890
  billing_account: 012345-6789AB-CDEF01
  labels: {env: dev}
node_service_account:
  grant_artifact_registry_reader: true
```

renders the project `hfl-gke-dev`, the APIs `artifactregistry`, `compute`,
`container`, `iam`, `logging` and `monitoring`, the account
`k8s-nodes@hfl-gke-dev.iam.gserviceaccount.com`, and five additive grants
to it on the project.

With a GKE cluster, as a Bundt Template's two components (a sketch; the cluster's
other inputs left out):

```yaml
components:
  project:
    package: gcp-project-wrapper
    inputs: {project: {name: gke-dev, prefix: hfl, parent: folders/1234567890}}
  cluster:
    package: gcp-gke-cluster
    inputs:
      project_id: {valueFrom: {component: project, output: project_id}}
      create_service_account: false
      service_account: {valueFrom: {component: project, output: node_service_account_email}}
```

`gke-cluster` with `create_service_account: false` makes no account and no
IAM (its `tests/node-sa.values.yaml`).

## Values

| Value | Renders |
| --- | --- |
| `project` | the `project` chart's values, as that chart takes them (fabric's variables). Its `labels`, `tags` and `deletion_policy` also apply to every object below. |
| `namePrefix` | must equal `project.namePrefix`: the project chart reads its own, and Helm cannot pass a parent's value down, so the render stops when they differ rather than leave the project ID without the prefix |
| `baseline_services` | a `Service` per API (default `compute`, `container`, `iam`, `logging`, `monitoring`), except an API already in `project.services`, which the project chart renders. Same object names and ids as the project chart's, so moving an API from one list to the other renames nothing. `project.service_config` applies. |
| `required_labels` | each key must be a cloud label on the project (an unprefixed `project.labels` key, or a `project.tags` key); the render stops naming the missing one. Default: none. |
| `node_service_account.name` | the account ID, default `k8s-nodes`: an `IAMServiceAccount` in the project. Taken as given, without the namePrefix, since it lives in the project whose ID carries it. |
| `node_service_account.display_name`, `.description` | its display name and description |
| (always) | an additive `IAMPolicyMember` on the project for each of `roles/logging.logWriter`, `roles/monitoring.metricWriter`, `roles/monitoring.viewer` and `roles/stackdriver.resourceMetadata.writer`: GKE's documented minimum for a node account |
| `node_service_account.grant_artifact_registry_reader` | also `roles/artifactregistry.reader` on the project, and the Artifact Registry API. Default `false`. |
| `node_service_account.extra_roles` | more project roles for the account (`roles/...` or `projects/<id>/roles/...`) |

The grants are additive, so nothing else in the project's IAM changes.
GKE also offers `roles/container.defaultNodeServiceAccount`, one role
holding these permissions, which `gke-cluster` grants to the accounts it
creates; this chart grants the four roles by name, so a reader of the
project's policy sees what nodes can do. Put the single role in
`extra_roles` to have both.

## Outputs

| Output | From |
| --- | --- |
| `project_id` | the ID the chart computed (the node account's `cnrm.cloud.google.com/project-id`), so it has a value with `project.project_reuse` too |
| `project_number` | the project's `status.number` (none with `project_reuse`) |
| `node_service_account_email` | the account's `status.email`: `gke-cluster`'s `service_account` |
| `node_service_account_iam_email` | the account's `status.member` (`serviceAccount:...`) |
| `services` | every enabled API, the project chart's and the baseline's |

## Tests

`task test CHART=project-wrapper` builds the dependency from
`../project` (`Chart.lock`; nothing is fetched) and renders four cases
(`basic`, `full`, `reuse`, `mock`), each validated against Config
Connector v1.160.0's CRD schemas and checked with the namePrefix set on
both the wrapper and the project chart, and five refusals in
`tests/*.fail.yaml`, one of them the project chart's own.
`tests/mock.values.yaml` is applied to the fake cloud by
`hack/mock-apply.sh` (`task test-mock`).

Not run live. Creating a project needs `roles/resourcemanager.projectCreator`
and billing rights on a folder; the `reuse` case on an existing project
needs `roles/iam.serviceAccountAdmin`, `roles/resourcemanager.projectIamAdmin`
and `roles/serviceusage.serviceUsageAdmin` there. The live-test accounts have
neither yet.

## Changes

- **0.1.0** (2026-11-11): the baseline: APIs, the dedicated node account and
  its roles, required labels, and the outputs `gke-cluster` takes.
