# secret-manager

Secret Manager secrets with their IAM and tag bindings, as Config
Connector objects. A port of Cloud Foundation Fabric's
[`modules/secret-manager`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/secret-manager)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-secret-manager` (`package.yaml`). Checked against Config Connector
v1.160.0.

The chart makes global secrets and their access, not their data: secret
versions are refused (below, "Values"), so a team adds versions with its
own tooling, or keeps them in Terraform, until Bundt settles how secret
data reaches the cloud.

## Example

```yaml
project_id: my-project
secrets:
  test-auto: {}
  test-user:
    global_replica_locations:
      europe-west1: null
      europe-west3: null
```

renders the `SecretManagerSecret`s `test-auto` (automatic replication) and
`test-user` (replicated in two regions) (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.<key>` | not a fabric variable: the secret ID of `secrets.<key>` in full, used as given (no `namePrefix`) and checked against the cloud's limit (255); a secret not named derives its ID from its key (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience. When set, the derived secret IDs start with `<namePrefix>-`; never a name set under `names`; empty changes nothing |
| `labels` | Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label (Config Connector copies it), so it must be a valid one |
| `tags` | cloud labels on every object (Google Cloud labels) |
| `project_id` (required) | the `cnrm.cloud.google.com/project-id` annotation of each secret |
| `project_number` | the project in the tag bindings' parent, as fabric writes it; `project_id` when null |
| `secrets` | one `SecretManagerSecret` per entry (`secretmanager.cnrm.cloud.google.com/v1beta1`), Kubernetes name `<component>-<key>`, `hfl.dev/id` `secret:<key>`, its fields below |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the secrets when the component is deleted. `PREVENT` is refused |

Each entry of `secrets`:

| Field | Renders |
| --- | --- |
| `annotations` | `spec.annotations` |
| `labels` | the secret's own labels, copied to the cloud |
| `kms_key` | `replication.auto.customerManagedEncryption.kmsKeyRef` |
| `global_replica_locations` | `replication.userManaged.replicas`, one per location, with its key when one is given; without it, `replication.auto` |
| `expiration_config` | `expireTime` (`time`) or `ttl`; both is refused, as the module refuses it |
| `version_config.aliases` | `versionAliases` |
| `rotation_config`, `topics` | `rotation` and `topics[].topicRef.external`; rotation without a topic is refused, as the module refuses it |
| `iam` | one `IAMPartialPolicy` on the secret |
| `iam_bindings` | one `IAMBinding` each (exact per role and condition; config-connector-extensions, `iam.gcp.hfl.dev/v1beta1`) |
| `iam_bindings_additive` | one `IAMPolicyMember` each |
| `tag_bindings` | one `TagsTagBinding` each, parent `//secretmanager.googleapis.com/projects/<project>/secrets/<id>` |
| `deletion_protection` | accepted and ignored (below, "Differences from the module") |

Refused when set:

| Variable or field | Why |
| --- | --- |
| `secrets.<key>.location` | a regional secret (`google_secret_manager_regional_secret` and its IAM and versions) has no Config Connector kind |
| `secrets.<key>.versions` | a `SecretManagerSecretVersion` takes its data as a plain value or from a Kubernetes Secret (`secretData.valueFrom.secretKeyRef`); a value from the module call would be written into the rendered objects, and how Bundt supplies secret data is not settled. Refused rather than guessed |
| `secrets.<key>.tags` | `SecretManagerSecret` has no field for resource manager tags at creation; `tag_bindings` binds them after |
| `secrets.<key>.version_config.destroy_ttl` | `SecretManagerSecret` has no version destroy TTL field |
| `context` | use Bundt's `${...}` expressions and `valueFrom` |

## Outputs

| Output | From |
| --- | --- |
| `ids` | each secret's `projects/<project>/secrets/<id>`, by key, from the render |

These are fabric's declared outputs, selected (`docs/design.md`,
"Outputs"). Not outputs: `secrets` and `versions` (whole Terraform
objects), and `version_ids` and `version_versions`, which would always be
empty while versions are refused.

## Differences from the module

- **No versions, no regional secrets** (above).
- **`deletion_protection`** is accepted and does nothing, whatever its
  value: it is Terraform's own guard against destroying the secret, and
  `SecretManagerSecret` has no field for it. The analogues are
  `deletion_policy: ABANDON` and a Bundt (L3) Policy that blocks a plan
  deleting the secret (`docs/design.md`, "Deletion").
- **`iam`** is an `IAMPartialPolicy`, which keeps the listed members but
  does not remove others; `iam_bindings` are exact, as `IAMBinding`
  (`docs/design.md`, "IAM").
- **Rotation.** fabric ignores later changes to `next_rotation_time`
  (`lifecycle.ignore_changes`); Config Connector reconciles the value
  given.

## From Terraform

A `module "x" { source = ".../modules/secret-manager" ... }` block's
arguments become the values unchanged, except refused fields
(`examples/secret-manager/`). To adopt existing secrets, keep their keys:
the key is the secret ID, so Config Connector acquires the secret of that
name (`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/secret-manager`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/secret-manager)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=secret-manager`: render cases `basic` (the module README's
example), `full` (every field the chart carries), `names` and `mock`, each
validated against Config Connector v1.160.0's CRD schemas (and `IAMBinding`
against config-connector-extensions'), and the refusals in
`tests/*.fail.yaml`. `tests/mock.values.yaml` is for the fake cloud
(`task test-mock`); it has not run yet.

## Changes

- **0.1.0** (2026-11-12): the port: global secrets, their IAM and tag
  bindings; regional secrets and versions refused.
