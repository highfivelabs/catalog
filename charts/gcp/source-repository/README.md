# source-repository

A Cloud Source Repository with its IAM and Cloud Build triggers, as Config
Connector objects. A port of Cloud Foundation Fabric's
[`modules/source-repository`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/source-repository)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-source-repository` (`package.yaml`). Checked against Config Connector
v1.160.0.

Cloud Source Repositories is closed to new customers: a project that has
not used it before cannot create a repository. The chart is for teams that
already have it and move their Terraform.

## Example

```yaml
project_id: my-project
name: my-repo
iam:
  roles/source.reader: ["user:foo@example.com"]
```

renders a `SourceRepoRepository` `my-repo` and its `IAMPartialPolicy`
(`tests/golden/basic.yaml`; `tests/golden/full.yaml` adds triggers).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.repository` | not a fabric variable: the repository's name in full, used as given (no `namePrefix`) and checked (128 characters) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the repository's name starts with `<namePrefix>-`; empty changes nothing |
| `labels`, `tags` | Kubernetes labels on every object; repositories and triggers take no Google Cloud labels |
| `project_id`, `name` | the repository (`cnrm.cloud.google.com/project-id`, `resourceID`) |
| `iam`, `iam_by_principals` | one `IAMPartialPolicy` on the repository, merged as fabric merges them (`docs/design.md`, "IAM": the listed members are kept, others left alone) |
| `iam_bindings` | bindings of the same `IAMPartialPolicy` (`IAMBinding` does not take a `SourceRepoRepository`) |
| `iam_bindings_additive` | one `IAMPolicyMember` each |
| `triggers` | one global `CloudBuildTrigger` per key building the repository: `filename`, `included_files`, `service_account` (`serviceAccountRef.external`), `substitutions`, and the template's `branch_name` and `tag_name`. Config Connector names a trigger by its Kubernetes name (the kind has no `resourceID`), so the trigger is named `<component>-trigger-<key>` where fabric names it `<key>` |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the repository and its triggers |

Refused, in part:

| Variable | Why |
| --- | --- |
| `iam_bindings[].condition`, `iam_bindings_additive[].condition` | Config Connector's IAM on a `SourceRepoRepository` does not support conditions |
| `triggers[].template.project_id` | `CloudBuildTrigger`'s `triggerTemplate` has no `projectId`: a trigger builds a repository of its own project, so another project is refused (the same project, or null, as fabric's default, is accepted) |

## Outputs

| Output | Value |
| --- | --- |
| `id` | `projects/<project>/repos/<name>`, from the inputs |
| `name` | the repository's name, from the inputs |
| `url` | the repository's `status.url` |

## From Terraform

A `module "x" { source = ".../modules/source-repository" ... }` block's
arguments become the values unchanged (`examples/source-repository/`). To
adopt an existing repository, keep its name: Config Connector acquires the
repository of that name (`docs/design.md`, "From Terraform"). Triggers are
not acquired: Config Connector cannot import a trigger by name, so the
chart's triggers are new ones; delete the Terraform-made triggers after the
first apply.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/source-repository`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/source-repository)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=source-repository`: render cases `basic`, `full`, `names`
and `mock`, each validated against Config Connector v1.160.0's CRD schemas,
and the refusals in `tests/*.fail.yaml`.

Fake cloud, `task test-mock MOCK_CHARTS=source-repository`, 2026-11-12:
the repository, its `IAMPartialPolicy` and `IAMPolicyMember` Ready, the
`url` output evaluated, all deleted. Triggers are render-tested only: the
fake cloud's Cloud Build does not implement `GetBuildTrigger` (a run with a
trigger failed with `501 method GetBuildTrigger not implemented`), so
`tests/mock.values.yaml` has none. Not applied live: the
live-test service accounts have no Source Repositories or Cloud Build role,
and the product is closed to new projects.

## Changes

- **0.1.0** (2026-11-12): the port.
