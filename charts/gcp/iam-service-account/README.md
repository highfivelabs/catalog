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
| `name`, `prefix`, `project_id`, `display_name`, `description` | `IAMServiceAccount` named `<prefix>-<name>` (checked: 6 to 30 characters) in `project_id`, or the namespace's project when null |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (keeps the account); `PREVENT` is refused |
| `iam`, `iam_by_principals`, `iam_bindings` | one `IAMPartialPolicy` on the account |
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

- `iam`, `iam_by_principals` and `iam_bindings` keep the members listed
  but no longer remove members added out of band (`IAMPartialPolicy`;
  `docs/design.md`, "IAM").
- Outputs come from the live account, so a dependent waits until it is
  ready.

## Tests

`hack/test.sh iam-service-account`: three render cases, five refusals.
`tests/mock.values.yaml` is applied to the fake cloud by
`hack/mock-apply.sh`.
