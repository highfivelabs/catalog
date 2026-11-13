# cloud-build-v2-connection

A Cloud Build (2nd gen) host connection to GitHub, GitLab or Bitbucket, its
linked repositories, a build trigger per repository event, and IAM on the
connection, as Config Connector objects. A port of Cloud Foundation
Fabric's
[`modules/cloud-build-v2-connection`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/cloud-build-v2-connection)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-cloud-build-v2-connection` (`package.yaml`). Checked against Config
Connector v1.160.0's `CloudBuildTrigger` and config-connector-extensions'
`CloudBuildConnection` (`cloudbuild.gcp.hfl.dev/v1beta1`),
`CloudBuildRepository` (`cloudbuild.gcp.hfl.dev/v1alpha1`), `IAMBinding`
(`iam.gcp.hfl.dev/v1beta1`) and `IAMMember` (`iam.gcp.hfl.dev/v1alpha1`),
at `0ee17dd4`. Config Connector's own `CloudBuildConnection` is
`v1alpha1`, and it has no repository kind.

## Example

```yaml
project_id: my-project
name: my-connection
location: europe-west1
allow_alpha: true          # repositories: CloudBuildRepository is v1alpha1
connection_config:
  github:
    authorizer_credential_secret_version: projects/my-project/secrets/authorizer-credential/versions/1
    app_installation_id: "1234567"
repositories:
  my-repository:
    remote_uri: https://github.com/my-user/my-repo.git
    triggers:
      my-trigger:
        push: {branch: main}
        filename: cloudbuild.yaml
iam:
  roles/cloudbuild.connectionViewer: ["group:mygroup@example.com"]
```

renders the `CloudBuildConnection` `my-connection`, the
`CloudBuildRepository` `my-repository` in it, a `CloudBuildTrigger` on
pushes to `main`, and an `IAMBinding` for the viewer role
(`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.connection` sets the connection's ID in full |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the connection's ID (unless set under `names`) and every repository's start with `<namePrefix>-`; empty changes nothing |
| `labels` | not a fabric variable: Kubernetes labels on every object. None of these resources takes Google Cloud labels |
| `tags` | not a fabric variable: cloud labels; none of these resources takes them, so they stay on the objects' `metadata.labels` |
| `project_id` | every object's project annotation, `projectRef`, and the connection and repository names in the triggers and IAM |
| `location` | every object's `location` |
| `name` | the connection's ID |
| `connection_create` | `false` renders no connection: repositories, triggers and IAM go on the connection of that name |
| `disabled`, `annotations` | the connection's `disabled` and `annotations` |
| `connection_config` | the connection's `bitbucketCloudConfig`, `bitbucketDataCenterConfig`, `githubConfig` or `gitlabConfig`; exactly one must be set, as fabric checks (whatever `connection_create` says). `github_enterprise` is refused (below) |
| `repositories` | one `CloudBuildRepository` per key, its ID the key, with `remote_uri` and `annotations`; `CloudBuildRepository` is `v1alpha1`, so it needs `allow_alpha: true` |
| `repositories.*.triggers` | one `CloudBuildTrigger` per trigger, keyed `<repository>-<trigger>` as fabric keys it, on the repository's `push` or `pull_request` events (exactly one, as fabric checks), with `description`, `disabled`, `filename`, `include_build_logs`, `substitutions`, `service_account` (as `serviceAccountRef.external`) and `tags` |
| `iam`, `iam_by_principals` | one `IAMBinding` per role, exact, the two merged as fabric merges them |
| `iam_bindings` | one `IAMBinding` per entry, exact |
| `iam_bindings_additive` | one `IAMMember` per entry (additive); `IAMMember` is `v1alpha1`, so it needs `allow_alpha: true` |
| `context` | refused: Bundt expressions (`${...}`) and `valueFrom` replace fabric's `$context` lookups (`$iam_principals:`, `$custom_roles:`, `$project_ids:`) |
| `allow_alpha` | not a fabric variable: accept the `v1alpha1` `CloudBuildRepository` and `IAMMember` |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the connection, repositories and triggers (not the IAM) |

Refused:

- `connection_config.github_enterprise`: config-connector-extensions'
  `CloudBuildConnection` requires `githubEnterpriseConfig.apiKey` (so does
  the API), and fabric's variable has no field for it.

Checks: `app_installation_id` must be a number (fabric's variable is a
string; the kind takes an integer), and `invert_regex` `true` or `false`
(fabric's is a string; the kind takes a boolean). A Bitbucket Data Center
connection without `webhook_secret_secret_version` stops the render: the
API and the kind require it, fabric's variable makes it optional. With a
`namePrefix`, a connection or repository ID over 63 characters stops the
render; a name set under `names` is always checked. 63 is an assumption,
the length the catalog uses where the API documents none.

## Outputs

| Output | From |
| --- | --- |
| `id` | `projects/<project>/locations/<location>/connections/<name>`, from the inputs as fabric computes it (whether or not the chart creates the connection) |
| `repository_ids` | `projects/<project>/locations/<location>/connections/<connection>/repositories/<id>`, keyed by repository, from the rendered objects |
| `trigger_ids` | `projects/<project>/locations/<location>/triggers/<trigger ID>`, keyed `<repository>-<trigger>`, from each trigger's `status.triggerId`; null until reported |

fabric's `repositories` and `triggers` are whole objects, and are not
outputs (`docs/design.md`, "Outputs").

## Differences from the module

- **Trigger names.** fabric names each trigger `<repository>-<trigger>`;
  Config Connector's `CloudBuildTrigger` has no name field, so the cloud
  gives the trigger its ID only. The key is in the object's name and
  `hfl.dev/id`, and `trigger_ids` is keyed by it.
- **Conditions** on `iam_bindings` and `iam_bindings_additive` are
  accepted and not sent: fabric's resources send none either.
- **`approval_required`** on a trigger, and `bitbucket_cloud.app_installation_id`,
  are accepted and not sent, as fabric does.
- **`$context` lookups** are refused (above).

## From Terraform

A `module "x" { source = ".../modules/cloud-build-v2-connection" ... }`
block's arguments become the values unchanged, apart from `context`
(refused), plus `allow_alpha: true` when it has repositories or additive
IAM. The connection and repositories keep their IDs, so they adopt what
Terraform made (`docs/design.md`, "From Terraform"). A trigger cannot be
adopted by its name (above): Config Connector would make a new one unless
the object is given the existing trigger's ID.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/cloud-build-v2-connection`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloud-build-v2-connection)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml)
records the repository, path, release, commit, licence and the date last
synced, and the module is listed in
[`upstream/modules.yaml`](../../../upstream/modules.yaml). To take a newer
release, see [`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=cloud-build-v2-connection`: render cases `basic`,
`bitbucket-cloud`, `bitbucket-data-center` and `gitlab` (fabric's README
examples, the Bitbucket ones without their misspelt `app_instalation_id`),
`existing` (`connection_create: false`), `full` (every variable), `names`
and `mock`, each validated against Config Connector's CRDs and those in
`crds/config-connector-extensions`, and the refusals in
`tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`): a GitHub
connection in `us-central1` and a role on it (`iam`). On 2026-11-13
(offload VM `off-catalog-1113061109-28826`; config-connector-extensions `35833eb8`, whose fake
cloud serves `getIamPolicy` on a connection) the connection and its
`IAMBinding` became Ready, the outputs evaluated (`id` set; no
repositories or triggers in the case) and both were deleted. mockgcp
reads neither the secret version nor the app installation, so a
credential that does not exist passes there and fails in the real cloud.
The `iam_by_principals`, `iam_bindings` and `iam_bindings_additive`
variables render the same `IAMBinding` kind (or the `v1alpha1`
`IAMMember`) and are only render-tested. Repositories and triggers (on the `v1alpha1`
`CloudBuildRepository`) and the `IAMMember`s (`v1alpha1`) are only
render-tested: alpha features are not in fake-cloud cases.

Not applied live: a real connection needs a GitHub, GitLab or Bitbucket
credential in Secret Manager and an installed app, which the live-test
project does not have; the live harness runs Config Connector's
controllers only, not config-connector-extensions' (which serve
`CloudBuildConnection` and `CloudBuildRepository`); and neither live-test
service account has a Cloud Build role, and this work changes no IAM.

## Changes

- **0.1.0** (2026-11-12): the port: the connection, repositories and
  triggers, and IAM on the connection.
