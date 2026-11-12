# kms

A Cloud KMS keyring, its crypto keys and import job, with their IAM and
tag bindings, as Config Connector objects. A port of Cloud Foundation
Fabric's
[`modules/kms`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/kms)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-kms` (`package.yaml`). Checked against Config Connector v1.160.0.

## Example

```yaml
project_id: my-project
keyring: {location: europe-west1, name: test}
iam:
  roles/cloudkms.admin: ["user:user1@example.com"]
keys:
  key-a: {}
  key-b: {rotation_period: 604800s}
```

renders the `KMSKeyRing` `test`, the `KMSCryptoKey`s `key-a` and `key-b`
and an `IAMPartialPolicy` on the keyring (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.keyring` | not a fabric variable: the keyring name in full, used as given (no `namePrefix`) and checked (63 characters); unset, the name is `keyring.name` (`docs/design.md`, "Names, labels and tags"). Keys are named by their keys |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the derived keyring name, every key name and the import job ID start with `<namePrefix>-`; empty changes nothing |
| `labels` | Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label on the keys (keyrings take no labels) |
| `tags` | cloud labels on every object (Google Cloud labels) |
| `project_id`, `keyring` | the `KMSKeyRing`'s project annotation, `resourceID` and `location` |
| `keyring_create: false` | no keyring: keys, the import job, IAM and tag bindings go on the existing keyring `projects/<p>/locations/<l>/keyRings/<name>` (named as above) |
| `keys` | one `KMSCryptoKey` each: `purpose` (default `ENCRYPT_DECRYPT`), `rotationPeriod`, `destroyScheduledDuration`, `skipInitialVersionCreation`, `versionTemplate` (protection level default `SOFTWARE`); its `labels` are the object's labels, which Config Connector copies to the key |
| `keys.<k>.iam`, `.iam_bindings`, `.iam_bindings_additive` | on the key: one `IAMPartialPolicy`, one `IAMBinding` each, one `IAMPolicyMember` each |
| `iam`, `iam_bindings`, `iam_bindings_additive` | the same on the keyring |
| `import_job` | one `KMSImportJob` on the keyring |
| `tag_bindings` | one `TagsLocationTagBinding` each, parent `//cloudkms.googleapis.com/projects/<p>/locations/<l>/keyRings/<name>` |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the keys when the component is deleted |

Refused when set:

| Variable | Why |
| --- | --- |
| `context` | use Bundt's `${...}` expressions and `valueFrom` |

## Outputs

| Output | From |
| --- | --- |
| `name`, `location` | the keyring's name and location, from the inputs |
| `id` | `projects/<project>/locations/<location>/keyRings/<name>`, from the inputs |
| `key_ids` | each key's `<id>/cryptoKeys/<name>`, by key, from the render |

These are fabric's declared outputs, selected (`docs/design.md`,
"Outputs"); fabric's `keyring`, `keys` and `import_job` (whole Terraform
objects) are not outputs.

## Differences from the module

- **Deletion.** Cloud KMS never deletes a keyring or an import job, and a
  key only has its versions scheduled for destruction. Deleting the
  component removes the objects; the keyring stays, as it does after
  `terraform destroy`.
- `iam` is an `IAMPartialPolicy`, which keeps the listed members but does
  not remove others; `iam_bindings` are exact, as `IAMBinding`
  (`docs/design.md`, "IAM").

## From Terraform

A `module "x" { source = ".../modules/kms" ... }` block's arguments become
the values unchanged (`examples/kms/`). To adopt an existing keyring and
keys, keep their names: Config Connector acquires the keyring and keys of
those names (`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/kms`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/kms)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=kms`: render cases `basic`, `full` (every field the chart
carries), `existing` (`keyring_create: false`), `names` and `mock`, each
validated against Config Connector v1.160.0's CRD schemas (and
`IAMBinding` against config-connector-extensions'), and the refusals in
`tests/*.fail.yaml`.

Applied to the fake cloud on 2026-11-12 on an offload VM (`task test-mock
MOCK_CHARTS=kms`): `tests/mock.values.yaml`, a keyring, a key with a rotation period, `iam` on the keyring and an additive member on the key: all 4 objects Ready, the outputs
evaluated, all deleted. Not applied live yet: neither live-test account holds a Cloud KMS role in the test project and the Cloud KMS API is not enabled there; and Cloud KMS never deletes a keyring, so a live run leaves one empty keyring per run (keyrings cost nothing).

## Changes

- **0.1.0** (2026-11-12): the port: keyring (or an existing one), keys,
  import job, IAM on both, tag bindings.
