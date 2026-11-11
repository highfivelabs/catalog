# folders-iam

IAM roles on one or more folders, additive (one member at a time) or
authoritative for the roles it names, with conditions, as Config Connector
objects. A port of terraform-google-modules'
[`iam`](https://registry.terraform.io/modules/terraform-google-modules/iam/google)
module at v8.3.0 (`9b9eacfa`), Apache-2.0, Copyright Google LLC:
[`modules/folders_iam`](https://github.com/terraform-google-modules/terraform-google-iam/tree/9b9eacfa2b4f849b5ef183cf5124b1e72aa72363/modules/folders_iam),
with the logic of the
[`modules/helper`](https://github.com/terraform-google-modules/terraform-google-iam/tree/9b9eacfa2b4f849b5ef183cf5124b1e72aa72363/modules/helper)
it calls. Bundt Package `gcp-iam-folders-iam` (`package.yaml`). Checked
against Config Connector v1.160.0.

The chart grants roles on folders it does not create, so the component
runs where Config Connector's account may set the folders' IAM policy
(`docs/design.md`, "Organization, folders and Config Connector's scope").

## Example

The module README's example, as values (`tests/basic.values.yaml`; the
folder is a number, which the module needs):

```yaml
folders: ["folders/1234567890"]
mode: additive
bindings:
  roles/resourcemanager.folderEditor:
    - serviceAccount:my-sa@my-project.iam.gserviceaccount.com
    - group:my-group@my-org.com
  roles/resourcemanager.folderViewer:
    - user:my-user@my-org.com
conditional_bindings:
  - role: roles/editor
    title: expires_after_2019_12_31
    description: Expiring at midnight of 2019-12-31
    expression: request.time < timestamp("2020-01-01T00:00:00Z")
    members: [user:my-user@my-org.com]
```

renders four `IAMPolicyMember`s, one per role (and condition) and member
(`tests/golden/basic.yaml`). The same with `mode: authoritative` renders one
`IAMPartialPolicy` per folder (`tests/authoritative.values.yaml`).

## Values: module inputs to Config Connector

Every module input is a value of the same name (`values.yaml`,
`values.schema.json`).

| Module input | Config Connector |
| --- | --- |
| `folders` | each folder's `resourceRef` (`kind: Folder`, `external: folders/<number>`). A folder is `folders/<number>` or `<number>`, and the module writes `folders/` + the value with `folders/` taken out, so both name one folder; a folder given twice is one. Anything else (a display name, as the module's README shows) is refused by the schema: the API needs the number |
| `mode: additive` (default) | the module's `google_folder_iam_member`s: one `IAMPolicyMember` (`iam.cnrm.cloud.google.com/v1beta1`) per folder, role and member, `hfl.dev/id` `folder:<number>:iam-additive-<role>--<member>` |
| `mode: authoritative` | the module's `google_folder_iam_binding`s (one per folder and role): one `IAMPartialPolicy` per folder, `hfl.dev/id` `folder:<number>:iam`, with a binding per role |
| `bindings` | `{ROLE: [MEMBER]}`, on every folder |
| `conditional_bindings` | `[{role, title, description, expression, members}]`, on every folder, each with its `condition` (`title`, `expression`, `description` when not empty). Additive ids are `folder:<number>:iam-additive-<role>--<title>--<member>` |

`mode` takes `additive` or `authoritative`, as the module's description
says. The module itself takes any string and makes nothing for another
one; the chart refuses it instead. The module has no inputs that exist
only for Terraform's plan-time counting.

### Not module inputs

| Value | Renders |
| --- | --- |
| `names` | takes no key: IAM bindings have no cloud name |
| `namePrefix` | changes nothing, for the same reason (`tests/name-prefix.yaml`) |
| `labels`, `tags` | Kubernetes labels on every object (an unprefixed key is checked as a Google Cloud label) |
| `deletion_policy` | `DELETE` (default) or `ABANDON`. The chart makes no resource of its own, only grants, which are removed with the component either way, as in every chart (`docs/design.md`, "Deletion"). `PREVENT` is refused |

## Outputs

| Output | From |
| --- | --- |
| `folders` | inputs: the folders as given, distinct, when any binding has a member, as the module outputs them |
| `roles` | inputs: the roles with a member, `bindings`' in key order, then `conditional_bindings`', distinct |
| `members` | inputs: every member, in the same order, distinct |

## Differences from the module

- **Authoritative mode keeps other members.** The module's
  `google_folder_iam_binding` is authoritative for its role: on apply,
  Terraform removes any member of that role on the folder that it does not
  list. `IAMPartialPolicy` keeps the listed members but does not remove
  others: a member added to one of these roles by hand, or by another tool,
  stays (`docs/design.md`, "IAM"). Deleting the component removes only the
  listed members. For the same reason a role (or conditional binding) with
  no members, which the module would empty, is refused in authoritative
  mode. This changes once `IAMRoleBinding` ships in
  config-connector-extensions (decision 5).
- **Two `conditional_bindings` with one role and title** are refused: the
  module keys them by role and title, so Terraform fails on them too.
- **Resource addresses.** With one folder, the module keys its resources
  by `default` rather than the folder (the helper's "singular" mode, for
  Terraform's plan-time `for_each`). That is a Terraform address only; the
  chart's ids always carry the folder number.

## From Terraform

A `module "x" { source = "terraform-google-modules/iam/google//modules/folders_iam" ... }`
block's arguments become the values unchanged. An `IAMPolicyMember` or
`IAMPartialPolicy` that matches an existing grant changes nothing in the
cloud, so adoption needs no IDs; follow `docs/design.md`, "From Terraform".

## Upstream

Ported from
[`modules/folders_iam`](https://github.com/terraform-google-modules/terraform-google-iam/tree/v8.3.0/modules/folders_iam)
and `modules/helper` at v8.3.0 (`9b9eacfa`, Apache-2.0).
[`upstream.yaml`](upstream.yaml) records the repository, path, release,
commit, licence and the date last synced, and the module is listed in
[`upstream/modules.yaml`](../../../upstream/modules.yaml) as
`gcp/iam-folders-iam`. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=folders-iam`: render cases `basic` (the module README's
example), `authoritative`, `full` (every input, a folder given both ways),
`offramp` (the offramp fixture), `names` and `mock`, each validated against
Config Connector v1.160.0's CRD schemas, and the refusals in
`tests/*.fail.yaml`. `tests/name-prefix.yaml` exempts both IAM kinds and
says the chart names nothing (`nothingNamed`).

`tests/mock.values.yaml` (one additive grant) is for the fake cloud (`task
test-mock`); it has not run yet, and needs the folder to exist in mockgcp.

## Changes

- **0.1.0** (2026-11-10): the port.
