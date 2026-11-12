# folders

Several folders under one parent, with a common name prefix and the admin
roles the module grants on them, as Config Connector objects. A port of
terraform-google-modules'
[`folders`](https://registry.terraform.io/modules/terraform-google-modules/folders/google)
module at v5.2.0 (`5ed57a3d`), Apache-2.0, Copyright Google LLC: the
[root module](https://github.com/terraform-google-modules/terraform-google-folders/tree/5ed57a3d7383003a33da2b7d780924a7024b11e0).
Bundt Package `gcp-folders` (`package.yaml`). Checked against Config
Connector v1.160.0.

Folders need folder or organization roles, so the component runs only in a
platform namespace whose Config Connector account has them
(`docs/design.md`, "Organization, folders and Config Connector's scope").

## Example

The module README's example, as values, with a placeholder parent folder
(`tests/basic.values.yaml`):

```yaml
parent: folders/10000000001
names: [dev, staging, production]
set_roles: true
per_folder_admins:
  dev: {members: ["group:gcp-developers@domain.com"]}
  staging: {members: ["group:gcp-qa@domain.com"]}
  production: {members: ["group:gcp-ops@domain.com"]}
all_folder_admins: ["group:gcp-security@domain.com"]
```

renders three `Folder`s (display names `dev`, `staging`, `production`) and
one `IAMPartialPolicy` on each, binding the module's four default
`folder_admin_roles` to the folder's admins and the security group
(`tests/golden/basic.yaml`).

## Values: module inputs to Config Connector

Every module input is a value of the same name (`values.yaml`,
`values.schema.json`).

| Module input | Config Connector |
| --- | --- |
| `names` | one `Folder` per name (`resourcemanager.cnrm.cloud.google.com/v1beta1`), Kubernetes name `<component>-<name>`, `hfl.dev/id` `folder:<name>`. A name listed twice is one folder, as in the module's `toset` |
| `prefix` | `displayName` is `<prefix>-<name>`, or `<name>` when `prefix` is empty, as the module builds it |
| `parent` (required) | `folderRef.external` (the number of `folders/<n>`) or `organizationRef.external` (of `organizations/<n>`) |
| `deletion_protection` | accepted and ignored, whatever its value (below, "Differences from the module") |
| `set_roles`, `folder_admin_roles`, `per_folder_admins`, `all_folder_admins` | the module's `owners_combined` bindings, one `IAMPartialPolicy` (`iam.cnrm.cloud.google.com/v1beta1`) per folder that has any, `hfl.dev/id` `folder:<name>:iam`, with one binding per role (below, "Admin roles") |

### Not module inputs

| Value | Renders |
| --- | --- |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of every folder's display name, outside the module's `prefix`. With it set, a display name longer than 30 characters is refused. Empty (the default) changes nothing |
| `labels` | Kubernetes labels on every object (an unprefixed key is checked as a Google Cloud label; folders have none, so it stays in Kubernetes) |
| `tags` | the same, as unprefixed `metadata.labels` |
| `deletion_policy` | `DELETE` (default) or `ABANDON`: the folders stay when the component is deleted. `PREVENT` is refused |
| `resource_ids` | adopts existing folders (below) |

The chart has no `names` map of whole names: the module's own `names`
variable is the folders' list and already names each folder in full (with
`prefix: ""`), so a team's naming convention goes there.

### Admin roles

The module computes its bindings (`main.tf`, `locals`) and the chart
computes the same ones:

- each folder in `per_folder_admins` gets its own `roles` (or
  `folder_admin_roles` when it has none) with its `members`;
- when `all_folder_admins` is set, every other folder in `names` gets
  `folder_admin_roles` with `all_folder_admins`;
- the members of every binding are its own plus `all_folder_admins`,
  distinct (so a folder in `per_folder_admins` has `all_folder_admins` too,
  but only on its own roles);
- nothing at all unless `set_roles` is `true`.

As in Terraform, a `per_folder_admins` folder that is not in `names`, and
two bindings with one key (`<name>-<role>`, a role listed twice), stop the
render. The module makes one `google_folder_iam_binding` per folder and
role; the chart makes one `IAMPartialPolicy` per folder holding a binding
per role, each binding's members exactly the module's.

## Adopting existing resources

A folder's number is assigned by Google when it is created; it is not a
name the chart can compute. To take over folders that exist (from
Terraform, or made by hand), give `resource_ids`, a map from a Folder
object's `hfl.dev/id` to the folder's number:

```yaml
resource_ids:
  "folder:prod": "123456789012"          # or "folders/123456789012"
```

The number becomes that Folder's `spec.resourceID`, and Config Connector
acquires the folder instead of creating one. A key that names no Folder of
the chart is refused. Empty (the default) creates new folders. The offramp
converter fills it from the Terraform state (`google_folder.folders["prod"]`
has `folder_id`). Do not change it once the folder is adopted: `resourceID`
is immutable.

## Outputs

| Output | From |
| --- | --- |
| `id`, `ids`, `ids_list` | each Folder's `status.name` (`folders/<number>`); `id` is the first name's, `ids` by name, `ids_list` in `names` order |
| `name`, `names`, `names_list` | each Folder's `spec.displayName` |
| `per_folder_admins` | inputs: each folder's members joined with `,`, as the module outputs them |

Not outputs: `folder`, `folders` and `folders_map`, whole Terraform
objects (`docs/design.md`, "Outputs"). What consumers take from them is the
folder's ID, which `id`, `ids` and `ids_list` give.

## Differences from the module

- **Authoritative bindings keep other members.** The module's
  `google_folder_iam_binding` is authoritative for its role: on apply,
  Terraform removes any member of that role on the folder that it does not
  list. `IAMPartialPolicy` keeps the listed members but does not remove
  others: a member added to one of these roles by hand, or by another tool,
  stays (`docs/design.md`, "IAM"). Deleting the component removes only the
  listed members. This changes once `IAMRoleBinding` ships in
  config-connector-extensions (decision 5).
- **`deletion_protection`** (default `true`) is accepted and does
  nothing, whatever its value. It is Terraform's own guard against
  destroying or recreating the folder, and `Folder` v1beta1 has no field
  for it. Deleting the component deletes the folders, as Bundt decided
  (`docs/design.md`, "Deletion"); the analogues are `deletion_policy:
  ABANDON`, which keeps them, and a Bundt (L3) Policy that blocks a plan
  deleting them. Google refuses to delete a folder that still holds
  projects or folders.
- **Outputs** come from the live Folders, so a dependent waits until they
  are ready.

## From Terraform

A `module "x" { source = "terraform-google-modules/folders/google" ... }`
block's arguments become the values unchanged. To adopt the folders it made, set
`resource_ids` from the state (above) and follow `docs/design.md`, "From
Terraform". The IAM bindings carry over member for member.

## Upstream

Ported from the root module of
[`terraform-google-folders`](https://github.com/terraform-google-modules/terraform-google-folders/tree/v5.2.0)
at v5.2.0 (`5ed57a3d`, Apache-2.0). [`upstream.yaml`](upstream.yaml)
records the repository, path, release, commit, licence and the date last
synced, and the module is listed in
[`upstream/modules.yaml`](../../../upstream/modules.yaml) as `gcp/folders`.
To take a newer release, see [`UPSTREAM.md`](../../../UPSTREAM.md), "Moving
the pins".

## Tests

`task test CHART=folders`: render cases `basic` (the module README's
example), `full` (every input, an organization parent, adoption, ABANDON),
`offramp` and `offramp-teams` (the offramp fixture's two module calls),
`names` and `mock`, each validated against Config Connector v1.160.0's CRD
schemas, and the refusals in `tests/*.fail.yaml`. `tests/name-prefix.yaml`
says the namePrefix is checked on a Folder's `displayName` (its
`resourceID` is a number), and exempts `IAMPartialPolicy`.

`tests/mock.values.yaml` (two folders under an organization, one role
each) is for the fake cloud (`task test-mock`); it has not run yet, and
depends on mockgcp's folder support and organization.

## Changes

- **0.1.0** (2026-11-10): the port.

### Fake cloud, 2026-11-11

`task test-mock` on an offload VM (run `off-catalog-1111013211-26916`, config-connector-extensions `1de95478`): both folders and both IAMPartialPolicies Ready (UpToDate), outputs evaluated, everything deleted.
