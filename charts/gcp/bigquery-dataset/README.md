# bigquery-dataset

A BigQuery dataset with its access entries, IAM, tables, views,
materialized views, routines and tag bindings. A port of Cloud Foundation
Fabric's
[`modules/bigquery-dataset`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/bigquery-dataset)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-bigquery-dataset` (`package.yaml`). The dataset, tables, routines and
tag bindings are Config Connector kinds (`v1beta1`); a separate access
entry is Config Connector's `BigQueryDatasetAccess` (`v1alpha1`); IAM on the
dataset is config-connector-extensions' `IAMBinding` (`v1beta1`) and
`IAMMember` (`v1alpha1`), at `d54a2075`, since Config Connector's IAM kinds
cannot reference a dataset.

## Example

```yaml
project_id: my-project
id: my_dataset
tables:
  countries:
    friendly_name: Countries
    schema: '[{"name":"country","type":"STRING"},{"name":"population","type":"INT64"}]'
views:
  population:
    query: SELECT SUM(population) AS total FROM my_dataset.countries
    use_legacy_sql: false
```

renders the dataset `my_dataset` in `EU`, the table `countries` and the
view `population` (`tests/golden/tables.yaml`; fabric's README example).

## Values

The module's variables, with the same names, types and defaults. The
chart carries 23 of the 24; one is refused, and six are accepted in part.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.dataset` sets the dataset's ID in full (letters, digits and `_`) |
| `namePrefix` | not a fabric variable: `<namePrefix>_` in front of the dataset's ID, its hyphens as underscores (a dataset ID has no hyphens). Tables, views and routines are named within the dataset |
| `labels` | fabric's dataset labels, with the catalog's meaning: labels on every object; an unprefixed one is a cloud label of the dataset and of each table, view and materialized view |
| `tags` | not a fabric variable: cloud labels on every object |
| `allow_alpha` | not a fabric variable: required for `BigQueryDatasetAccess` (below) and `iam_bindings_additive` |
| `deletion_policy` | not a fabric variable: `DELETE` (default) or `ABANDON`; `PREVENT` is refused |
| `project_id`, `id`, `location` | the dataset's `projectRef`, `resourceID` and `location` |
| `friendly_name`, `description` | `friendlyName`, `description` (fabric's default `Terraform managed.`) |
| `encryption_key` | `defaultEncryptionConfiguration.kmsKeyRef.external` |
| `options` | `defaultCollation`, `defaultTableExpirationMs`, `defaultPartitionExpirationMs`, `isCaseInsensitive`, `maxTimeTravelHours` (fabric's default 168), `storageBillingModel`; `delete_contents_on_destroy` is Config Connector's `delete-contents-on-destroy` annotation |
| `access`, `access_identities` | each rule with its identity: `domain`, `groupByEmail`, `specialGroup` or `userByEmail` with the rule's `role`; a `view` rule's identity `project\|dataset\|table` is an authorized view. With `dataset_access: true`, entries of the dataset's `spec.access`; otherwise (fabric's default) one `BigQueryDatasetAccess` each, which is `v1alpha1`: **needs `allow_alpha: true`** |
| `authorized_views`, `authorized_datasets` | an authorized view or dataset (`targetTypes: [VIEWS]`) each, merged with the `view` rules by `<project>_<dataset>_<table>` as fabric merges them; in `spec.access` or `BigQueryDatasetAccess` as `access` |
| `authorized_routines` | an authorized routine each in `spec.access`, with `dataset_access: true` only. **Refused with `dataset_access: false`** (a gap): `BigQueryDatasetAccess` has no routine |
| `dataset_access` | where the access entries go (above) |
| `iam`, `iam_by_principals` | merged by role; one `IAMBinding` per role on the dataset, exact per role |
| `iam_bindings` | one `IAMBinding` per entry, with its condition |
| `iam_bindings_additive` | one `IAMMember` per entry, with its condition: **needs `allow_alpha: true`** |
| `tables` | one `BigQueryTable` per key, named by the key: `friendlyName`, `description`, `labels` (its object's), `schema`, `requirePartitionFilter`, `options` (`clustering`, `encryptionConfiguration`, `expirationTime`, `maxStaleness`), `partitioning` (`rangePartitioning` with `field`, or `timePartitioning` with its own `field`, as fabric maps them), `externalDataConfiguration` (every field fabric has, `avro_logical_types` as `avroOptions` and `json_options_encoding` as `jsonOptions`), `tableConstraints` (the primary key, and the one foreign key fabric takes). `deletion_protection` is accepted and ignored (below) |
| `views` | one `BigQueryTable` with a `view` (`query`, `useLegacySql`) per key; `schema` is sent as JSON, as fabric's `jsonencode` |
| `materialized_views` | one `BigQueryTable` with a `materializedView` (`query`, `enableRefresh`, `refreshIntervalMs`, `allowNonIncrementalDefinition`) per key, with the table fields above |
| `routines` | one `BigQueryRoutine` per key with `routineType`, `language`, `definitionBody`, `description`, `importedLibraries`, `determinismLevel`, `returnType`, `returnTableType` and `arguments` (named by their keys). **`data_governance_type`, `spark_options` and `remote_function_options` are refused** (a gap): the kind has no such fields |
| `tag_bindings` | one `TagsLocationTagBinding` per entry on `//bigquery.googleapis.com/<id>`, in the dataset's location |
| `context` | **refused when set** (by design): Bundt expressions (`${...}`) and `valueFrom` replace fabric's `$context` lookups |

## Outputs

| Output | From |
| --- | --- |
| `dataset_id` | the dataset's ID |
| `id` | `projects/<project>/datasets/<id>` |
| `self_link` | the dataset's `status.selfLink` |
| `table_ids`, `view_ids`, `materialized_view_ids` | each table, view or materialized view the chart makes, by table ID, to `<id>/tables/<table>` |
| `routine_ids` | each routine, by routine ID, to `<id>/routines/<routine>` |

Fabric's whole-object outputs (`dataset`, `tables`, `views`,
`materialized_views`, `routines`) are left out (`docs/design.md`,
"Outputs").

## Differences from the module

- **`dataset_access: true` with IAM is refused.** The dataset's
  `spec.access` then owns the whole access list, and Config Connector would
  undo every `IAMBinding` and `IAMMember` on each reconcile. Fabric's `iam`
  description says the two are mutually exclusive; Terraform shows a
  permanent diff, the chart stops instead.
- **Authorized views, datasets and routines with `dataset_access: true`**
  render as fabric means them. Fabric's own `dynamic "access"` blocks for
  them read `each.value` where `access.value` is meant, so Terraform fails
  to plan that combination at v60.0.0.
- **`deletion_protection`** on a table, view or materialized view is
  accepted and does nothing: it is the Terraform provider's own guard
  against destroy, and `BigQueryTable` has none. `deletion_policy: ABANDON`
  keeps the dataset and its tables.
- **`labels`** reach every object, tables included, where fabric labels
  the dataset only (each table also takes its own `labels`).
- **References by name.** Tables and routines name the dataset by its ID,
  and the IAM objects by its full name, not by Kubernetes reference, so
  they can be deleted after the dataset's object is gone. A table's
  `datasetRef.external` is the bare ID: Config Connector's `BigQueryTable`
  sends it to the API as the dataset ID, so the
  `projects/<p>/datasets/<d>` form its CRD describes fails with 404.
- **Ordering.** Fabric makes views after tables and routines
  (`depends_on`); here a view that reads a table not yet made fails and is
  retried until the table exists.

## From Terraform

A `module "x" { source = ".../modules/bigquery-dataset" ... }` block's
arguments become the values unchanged, with `allow_alpha: true` when
`access`, `authorized_views` or `authorized_datasets` is set without
`dataset_access`, or `iam_bindings_additive` is set. The dataset, tables and
routines keep their names, so they adopt what Terraform made
(`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/bigquery-dataset`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/bigquery-dataset)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=bigquery-dataset`: render cases `basic`, `access`,
`authorized`, `iam`, `options`, `tables`, `routines` and `tags` (fabric's
README examples), `dataset-access` (every access entry in the dataset's
list), `full`, `names` and `mock`, validated against Config Connector's and
config-connector-extensions' CRDs, and the refusals in `tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`): a dataset with a
table, a view, a routine, an access entry, a role and an additive member.
On 2026-11-13 (offload VM `off-catalog-1113134756-17255`,
config-connector-extensions `d54a2075`) all seven objects became Ready, the
outputs evaluated and all seven were deleted. The first run found that
Config Connector's `BigQueryTable` sends `datasetRef.external` to the API as
the dataset ID, so the `projects/<p>/datasets/<d>` form its CRD describes
fails with 404; the chart now gives the bare ID.

Not applied live: live runs are pending KEYLIVE.

## Changes

- **0.1.0** (2026-11-13): the port: the dataset, its access entries and
  IAM, tables, views, materialized views, routines and tag bindings.
