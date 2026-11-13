# logging-bucket

A Cloud Logging bucket in a project, folder, organization or billing
account, with its log views, IAM on the views, a linked BigQuery dataset
for Log Analytics and tag bindings. A port of Cloud Foundation Fabric's
[`modules/logging-bucket`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/logging-bucket)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-logging-bucket` (`package.yaml`). The bucket, views, link and tag
bindings are Config Connector kinds (`v1beta1`); IAM on a view is
config-connector-extensions' `IAMBinding` (`v1beta1`) and `IAMMember`
(`v1alpha1`), at `d54a2075`, since Config Connector's IAM kinds cannot
reference a log view. config-connector-extensions takes a project's log
view only, so IAM on a folder's, organization's or billing account's view
is refused.

## Example

```yaml
parent: my-project
name: mybucket
log_analytics:
  enable: true
  dataset_link_id: log
```

renders the project bucket `mybucket` with Log Analytics on, and the
`LoggingLink` `log` that links it to a BigQuery dataset
(`tests/golden/analytics.yaml`; fabric's README example).

## Values

The module's variables, with the same names, types and defaults. The
chart carries 10 of the 12; two are refused, and one is accepted in part.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.bucket` sets the bucket's ID in full |
| `namePrefix` | not a fabric variable: `<namePrefix>-` in front of the bucket's ID. Views and the link are named within the bucket |
| `labels`, `tags` | not fabric variables: Kubernetes labels on every object (log buckets, views and links have no cloud labels) |
| `allow_alpha` | not a fabric variable: required for a view's `iam_bindings_additive` |
| `deletion_policy` | not a fabric variable: `DELETE` (default) or `ABANDON`; `PREVENT` is refused |
| `parent_type`, `parent` | the bucket's and each view's `projectRef`, `folderRef`, `organizationRef` or `billingAccountRef`, `external`: a project ID, `folders/<id>`, `organizations/<id>` or a billing account ID, as fabric takes them |
| `name` | the bucket's ID (`resourceID`) |
| `location` | the bucket's `location`, and each view's unless it sets its own |
| `description`, `retention` | `description`, `retentionDays` |
| `locked` | `locked`; a project bucket's only, as fabric's validation says |
| `log_analytics` | `enable` is a project bucket's `enableAnalytics`, as fabric sets it on project buckets only; `dataset_link_id` makes a `LoggingLink` with `description` on a project bucket |
| `views` | one `LoggingLogView` per key, named by the key, with `filter`, `description` and `location`. On a project's bucket, `iam`: one `IAMBinding` per role on the view, exact per role; `iam_bindings`: one `IAMBinding` per entry, with its condition; `iam_bindings_additive`: one `IAMMember` per entry, with `allow_alpha: true`; each names the view by its full name (`<id>/views/<view>`), the only form config-connector-extensions resolves. **IAM on a view of a folder's, organization's or billing account's bucket is refused** (a gap): config-connector-extensions takes a project's log view only |
| `tag_bindings` | one `TagsTagBinding` per entry on `//logging.googleapis.com/<id>` |
| `kms_key_name` | **refused when set** (a gap): `LoggingLogBucket` has no `cmekSettings` |
| `context` | **refused when set** (by design): Bundt expressions (`${...}`) and `valueFrom` replace fabric's `$context` lookups |

## Outputs

| Output | From |
| --- | --- |
| `id` | the bucket's full name, `<parent>/locations/<location>/buckets/<id>` (`projects/`, `folders/`, `organizations/` or `billingAccounts/`), from its spec: the kind reports no name |
| `view_ids` | each view the chart makes, by key, to its full name `<id>/views/<view>`. Fabric's also holds `_AllLogs`, the automatic view every bucket has: its name is `<id>/views/_AllLogs` |

## Differences from the module

- **No CMEK** on the bucket (above).
- **No IAM on a non-project view** (above).
- **References by name.** The link and the IAM objects name the bucket and
  the view by their full names, not by Kubernetes reference, so they can
  reconcile before the bucket exists (they retry until it does) and be
  deleted after it is gone.
- **`view_ids`** leaves out `_AllLogs` (above): a Package output cannot
  merge a computed entry into a map.

## From Terraform

A `module "x" { source = ".../modules/logging-bucket" ... }` block's
arguments become the values unchanged, with `allow_alpha: true` when a
view has `iam_bindings_additive`. The bucket keeps its name, so it adopts
the bucket Terraform made (`docs/design.md`, "From Terraform"); a
project's or folder's `_Default` bucket, which always exists, is adopted
the same way, as fabric's README example does with Terraform.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/logging-bucket`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/logging-bucket)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=logging-bucket`: render cases `basic`, `analytics`,
`folder`, `organization`, `billing-account` and `views` (fabric's README
examples, the last with a conditional binding and an additive member
added), `full`, `names` and `mock`, validated against Config Connector's
and config-connector-extensions' CRDs, and the refusals in
`tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`): a project bucket
with Log Analytics and a linked dataset, and a view with one role on it. On
2026-11-13 (offload VM `off-catalog-1113115537-13561`,
config-connector-extensions `d54a2075`) all four objects became Ready,
the outputs evaluated and all four were deleted. The first run found two
things the chart now does: config-connector-extensions resolves a log view
for IAM only from its full name (a name reference is refused), and a link
that named its bucket by reference could not be deleted once the bucket's
object was gone.

Not applied live: live runs are pending KEYLIVE.

## Changes

- **0.1.0** (2026-11-13): the port: the bucket in any of its four parents,
  views and their IAM, the linked dataset and tag bindings.
