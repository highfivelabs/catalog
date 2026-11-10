# iam-service-account

A Google service account and its IAM, as Config Connector objects. A port
of Cloud Foundation Fabric's
[`modules/iam-service-account`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/iam-service-account)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-iam-service-account` (`package.yaml`). Checked against Config
Connector v1.160.0.

## Example

The fabric README's first example, as values:

```yaml
project_id: myproject
name: vm-default
iam:
  roles/iam.serviceAccountUser: ["group:organization-admins@example.org"]
iam_project_roles:
  myproject: [roles/logging.logWriter, roles/monitoring.metricWriter]
```

renders an `IAMServiceAccount`, an `IAMPartialPolicy` on it, and an
`IAMPolicyMember` per project role with the account as member
(`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults
(`values.yaml`, `values.schema.json`).

| Variable | Renders |
| --- | --- |
| `names.serviceAccount` | not fabric variables: the cloud name in full, used as given (no `namePrefix`, no `prefix`) and checked against the cloud's limit; a name not set derives from `name` (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience. When set, the derived cloud names this chart gives (the account ID) start with `<namePrefix>-`, in front of the module's own `prefix`; never a name set under `names`; empty changes nothing |
| `labels` | Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label (Config Connector copies it), so it must be a valid one |
| `tags` | cloud labels on every object (Google Cloud labels) |
| `name`, `prefix`, `project_id`, `display_name`, `description` | `IAMServiceAccount` named `<prefix>-<name>` (checked: 6 to 30 characters) in `project_id`, or the namespace's project when null |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (keeps the account); `PREVENT` is refused |
| `iam`, `iam_by_principals` | one `IAMPartialPolicy` on the account |
| `iam_bindings` | one `IAMBinding` each (exact per role; config-connector-extensions, `v1beta1`) |
| `iam_bindings_additive`, `iam_by_principals_additive` | one `IAMPolicyMember` each |
| `iam_{billing,folder,organization,project,sa,storage}_{roles,bindings}` | one `IAMPolicyMember` per role on that resource, `memberFrom.serviceAccountRef` naming this account |
| `project_number` | ignored: Config Connector reads it |

Refused when set:

| Variable | Why |
| --- | --- |
| `service_account_reuse` | a reused account is not a component; reference it by email where it is used |
| `create_ignore_already_exists` | Config Connector acquires an account with the same ID anyway |
| `tag_bindings` | a service account's tag binding names its unique ID, known only after apply, and `TagsTagBinding` has no service account reference (gap 8 in `docs/gcp-inventory.md`) |
| `context` | use Bundt's `${...}` expressions and `valueFrom` |

## Outputs

| Output | From |
| --- | --- |
| `email`, `name` | `status.email` |
| `iam_email` | `status.member` (`serviceAccount:<email>`) |
| `id` | `status.name` (`projects/<p>/serviceAccounts/<email>`) |
| `unique_id` | `status.uniqueId` |

fabric's `service_account` output (the Terraform object) is not ported.

## Differences from the module

- `iam` and `iam_by_principals` keep the members listed
  but no longer remove members added out of band (`IAMPartialPolicy`;
  `docs/design.md`, "IAM").
- Outputs come from the live account, so a dependent waits until it is
  ready.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/iam-service-account`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/iam-service-account)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=iam-service-account`: five render cases, ten refusals.
`tests/mock.values.yaml` is applied to the fake cloud by
`hack/mock-apply.sh`.

## Changes

- **0.4.0** (2026-11-10): `iam_bindings` render one exact `IAMBinding` each (config-connector-extensions, `iam.gcp.hfl.dev/v1beta1`) by default (K5, K12), instead of bindings of the `IAMPartialPolicy`: members added to those roles out of band are now removed, as fabric removes them. Values that set `iam_bindings` render different objects (`docs/design.md`, "Versioning and the OCI layout").
- **0.3.0** (2026-11-10): `names` (`names.serviceAccount`) sets cloud names in full;
  `labels` and `tags` go on every object; `namePrefix` is an optional
  convenience that never touches a name set in full.
- **0.2.0** (2026-11-09): `namePrefix`.
- **0.1.0** (2026-11-09): the pilot port.
