# dataplex-aspect-types

Dataplex Catalog aspect types in one location of one project, with IAM on
each, as Config Connector objects. A port of Cloud Foundation Fabric's
[`modules/dataplex-aspect-types`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/dataplex-aspect-types)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-dataplex-aspect-types` (`package.yaml`). Checked against
config-connector-extensions' `DataplexAspectType`
(`dataplex.gcp.hfl.dev/v1beta1`), `IAMBinding` (`iam.gcp.hfl.dev/v1beta1`)
and `IAMMember` (`iam.gcp.hfl.dev/v1alpha1`), at `11baa460`; Config
Connector v1.160.0 has none of them.

## Example

```yaml
project_id: test-project
allow_alpha: true          # iam_bindings_additive: IAMMember is v1alpha1
aspect_types:
  tf-test-template:
    display_name: Test template.
    iam:
      roles/dataplex.aspectTypeOwner: ["group:data-owners@example.com"]
    iam_bindings_additive:
      user:
        role: roles/dataplex.aspectTypeUser
        member: serviceAccount:sa-0@test-project.iam.gserviceaccount.com
    metadata_template: |
      {"name": "tf-test-template", "type": "record", "recordFields": [...]}
```

renders the `DataplexAspectType` `tf-test-template` in `global`, an
`IAMBinding` for the owner role and an `IAMMember` for the user
(`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.<key>` sets the ID of the aspect type of that key in full |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every aspect type ID not set under `names` starts with `<namePrefix>-`; empty changes nothing |
| `labels` | not a fabric variable: Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label on every aspect type |
| `tags` | not a fabric variable: cloud labels on every aspect type |
| `project_id` | every object's project annotation and `projectRef` |
| `location` | the aspect types' `location` (`global` by default) |
| `aspect_types` | one `DataplexAspectType` per key, its ID the key, with `description`, `display_name`, `labels` (with the chart's) and `metadata_template`, JSON text parsed into the kind's `metadataTemplate` |
| `aspect_types.*.iam` | one `IAMBinding` per role, exact as fabric's `authoritative` bindings |
| `aspect_types.*.iam_bindings` | one `IAMBinding` per entry, with its condition; keyed by the entry's key across all aspect types, as fabric merges them |
| `aspect_types.*.iam_bindings_additive` | one `IAMMember` per entry (additive), keyed the same way; `IAMMember` is `v1alpha1`, so it needs `allow_alpha: true` |
| `factories_config` | accepted and ignored: a chart cannot read files. Each file of the `aspect_types` folder goes under `factories_data.aspect_types.<file name without .yaml>`, exactly its content, and wins over the `aspect_types` entry of the same key, as fabric's `merge` does |
| `context` | refused: Bundt expressions (`${...}`) and `valueFrom` replace fabric's `$context` lookups (`$iam_principals:`, `$custom_roles:`, `$locations:`, `$project_ids:`, `condition_vars`) |
| `allow_alpha` | not a fabric variable: accept the `v1alpha1` `IAMMember` |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the aspect types (not the IAM) |

Checks: `metadata_template` must be valid JSON, and an aspect type without
one stops the render (the Dataplex API and the kind require it; fabric's
variable is optional and the API refuses it at apply). With a
`namePrefix`, an ID over 63 characters stops the render; a name set under
`names` is always checked. 63 is an assumption, the length the catalog uses where the API documents none.

## Outputs

Each is a map keyed by the aspect type's key.

| Output | From |
| --- | --- |
| `ids` | `projects/<project>/locations/<location>/aspectTypes/<id>`, from the rendered objects, as fabric's `id` |
| `names` | the object's `status.externalRef`, the resource's name with the project ID; fabric's `name` is the API's, which may carry the project number. Null until reported |
| `timestamps` | `{create, update}` from `status.observedState.createTime` and `updateTime`; null until reported |
| `uids` | `status.observedState.uid`; null until reported |

## Differences from the module

- **Labels reach the cloud through `spec.labels`.** config-connector-
  extensions' Dataplex kinds take cloud labels from `spec.labels`, so the
  chart writes there the aspect type's `labels` and the unprefixed keys of
  the chart's `labels` and `tags`; they are also on `metadata.labels`.
- **`$context` lookups** are refused (above); a factory file that uses
  `$iam_principals:<name>` is written with the principal itself, or a
  Bundt expression.
- **Conditions** are sent as written; fabric's `templatestring` over
  `context.condition_vars` has no equivalent (refused with `context`).

## From Terraform

A `module "x" { source = ".../modules/dataplex-aspect-types" ... }`
block's arguments become the values unchanged, apart from `context`
(refused) and the factory's files (`factories_data`). The aspect types
keep their IDs, so they adopt what Terraform made (`docs/design.md`, "From
Terraform"). IAM is `IAMBinding`, exact per role, and `IAMMember`,
additive, as fabric's.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/dataplex-aspect-types`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/dataplex-aspect-types)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml)
records the repository, path, release, commit, licence and the date last
synced, and the module is listed in
[`upstream/modules.yaml`](../../../upstream/modules.yaml). To take a newer
release, see [`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=dataplex-aspect-types`: render cases `basic` (fabric's
README "Simple example"), `factory` ("Factory example"), `defaults`,
`full` (every variable), `names` and `mock`, each validated against the
CRDs in `crds/config-connector-extensions`, and the refusals in
`tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`): one aspect type in
`us-central1` and a role on it (`iam`). On 2026-11-13 (offload VM `off-catalog-1113061109-28826`,
config-connector-extensions `35833eb8`, whose fake cloud serves
`getIamPolicy` on an aspect type) the aspect type and its `IAMBinding`
became Ready, the outputs evaluated (`ids`, `names`, `timestamps`, `uids`
all set) and both were deleted. The `IAMMember`s (`v1alpha1`) are only
render-tested: alpha features are not in fake-cloud cases.

Live (`hack/live-apply.sh` `LIVE_CHARTS=dataplex-aspect-types`, `tests/live.yaml`;
2026-11-13, run `cat-11132355-c86b`, offload VM
`off-catalog-1113235106-15596`, as cce-live-tests, config-connector-extensions `c2f0c7d2`): one aspect type
and a role on it. Passed: both Ready, deleted and gone from Google
Cloud.

## Changes

- **0.1.0** (2026-11-12): the port: aspect types from the variable and the
  factory, and IAM on each.
