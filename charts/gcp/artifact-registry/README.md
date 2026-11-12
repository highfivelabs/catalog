# artifact-registry

An Artifact Registry repository (standard, remote or virtual) with its IAM
and tag bindings, as Config Connector objects. A port of Cloud Foundation
Fabric's
[`modules/artifact-registry`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/artifact-registry)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-artifact-registry` (`package.yaml`). Checked against Config Connector
v1.160.0.

## Example

```yaml
project_id: my-project
location: europe-west1
name: docker-registry
format: {docker: {standard: {}}}
iam:
  roles/artifactregistry.admin: ["group:cloud-admins@example.org"]
```

renders the `ArtifactRegistryRepository` `docker-registry` and an
`IAMPartialPolicy` on it (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.repository` | not a fabric variable: the repository ID in full, used as given (no `namePrefix`) and checked (63 characters, a leading letter); unset, the ID is `name` (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the derived repository ID starts with `<namePrefix>-`; empty changes nothing |
| `labels` | Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label (fabric's `labels`, on the repository, are these) |
| `tags` | cloud labels on every object (Google Cloud labels) |
| `project_id`, `location`, `name`, `description` | the repository's project annotation, `location`, `resourceID` and `description` |
| `format` | `format` (upper-cased) and `mode` (`STANDARD_REPOSITORY`, `REMOTE_REPOSITORY`, `VIRTUAL_REPOSITORY`), with fabric's three validations. `docker.standard.immutable_tags` is `dockerConfig`; `maven.standard` is `mavenConfig`; a remote's `public_repository` is `remoteRepositoryConfig.<format>Repository.publicRepository` and its `common_repository` is `commonRepository.uri`; a virtual repository's map is `virtualRepositoryConfig.upstreamPolicies` |
| `encryption_key` | `kmsKeyRef.external` |
| `cleanup_policies`, `cleanup_policy_dry_run` | `cleanupPolicies` (by ID, sorted) and `cleanupPolicyDryRun` |
| `iam`, `iam_by_principals` | one `IAMPartialPolicy` on the repository |
| `iam_bindings` | one `IAMBinding` each (exact per role; config-connector-extensions, `v1beta1`) |
| `iam_bindings_additive` | one `IAMPolicyMember` each |
| `tag_bindings` | one `TagsLocationTagBinding` each, parent `//artifactregistry.googleapis.com/projects/<p>/locations/<l>/repositories/<id>` |
| `universe` | read only by the `url` output, as fabric reads it |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the repository |

Refused when set:

| Variable | Why |
| --- | --- |
| `enable_vulnerability_scanning` (true or false) | `ArtifactRegistryRepository` has no `vulnerabilityScanningConfig` field |
| `format.apt.remote`, `format.yum.remote` | `remoteRepositoryConfig` has no apt or yum repository |
| `format.<f>.remote.custom_repository`, `.upstream_credentials`, `.disable_upstream_validation` | `remoteRepositoryConfig` has no custom repository, no upstream credentials and no `disableUpstreamValidation` |
| `context` | use Bundt's `${...}` expressions and `valueFrom` |

## Outputs

| Output | From |
| --- | --- |
| `name` | the repository ID, from the inputs |
| `id` | `projects/<project>/locations/<location>/repositories/<name>`, from the inputs |
| `url` | `<location>-<format>.pkg.dev/<project>/<name>`, or with `universe` `<format>.<package_domain>/<prefix>/<project>/<name>`, as fabric computes it |

These are fabric's declared outputs, selected (`docs/design.md`,
"Outputs"); fabric's `repository` (a whole Terraform object) is not an
output.

## Differences from the module

- `iam` and `iam_by_principals` are an `IAMPartialPolicy`, which keeps the
  listed members but does not remove others; `iam_bindings` are exact, as
  `IAMBinding` (`docs/design.md`, "IAM").
- fabric's `labels` go on the repository; here the chart's `labels` go on
  every object, and Config Connector copies the unprefixed ones to the
  repository.

## From Terraform

A `module "x" { source = ".../modules/artifact-registry" ... }` block's
arguments become the values unchanged, except refused fields
(`examples/artifact-registry/`). To adopt an existing repository, keep its
`name`: Config Connector acquires the repository of that ID
(`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/artifact-registry`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/artifact-registry)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=artifact-registry`: render cases `basic`, `full` (every
field the chart carries), `remote`, `common`, `virtual`, `generic`, `names`
and `mock`, each validated against Config Connector v1.160.0's CRD schemas
(and `IAMBinding` against config-connector-extensions'), and the refusals
in `tests/*.fail.yaml`. `tests/mock.values.yaml` is for the fake cloud
(`task test-mock`).

## Changes

- **0.1.0** (2026-11-12): the port: standard, remote (Docker, Maven, npm,
  Python, Go) and virtual repositories, cleanup policies, IAM and tag
  bindings; vulnerability scanning, apt and yum remotes, custom
  repositories and upstream credentials refused.
