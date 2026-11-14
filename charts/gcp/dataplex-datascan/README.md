# dataplex-datascan

A Dataplex data scan, a data profile scan or a data quality scan of a
BigQuery table or a Dataplex entity, with IAM on it, as Config Connector
objects. A port of Cloud Foundation Fabric's
[`modules/dataplex-datascan`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/dataplex-datascan)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-dataplex-datascan` (`package.yaml`). Checked against
config-connector-extensions' `DataplexDataScan`
(`dataplex.gcp.hfl.dev/v1beta1`), `IAMBinding` (`iam.gcp.hfl.dev/v1beta1`)
and `IAMMember` (`iam.gcp.hfl.dev/v1alpha1`), at `11baa460`; Config
Connector v1.160.0 has none of them.

## Example

```yaml
name: datascan
prefix: test
project_id: my-project-name
region: us-central1
labels: {billing_id: a}
data:
  resource: //bigquery.googleapis.com/projects/bigquery-public-data/datasets/austin_bikeshare/tables/bikeshare_stations
data_profile_spec:
  sampling_percent: 100
  row_filter: station_id > 1000
incremental_field: modified_date
```

renders the `DataplexDataScan` `test-datascan`, a profile scan run on
demand (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.datascan` sets the scan's ID in full |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the derived ID starts with `<namePrefix>-`; empty changes nothing |
| `labels` | fabric's labels, with the catalog's meaning: Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label on the scan |
| `tags` | not a fabric variable: cloud labels on the scan |
| `name`, `prefix` | the scan's ID and display name, `<prefix>-<name>` |
| `project_id`, `region` | the project and the scan's `location` |
| `description` | `Terraform Managed. <description>`, or `Terraform Managed.`, as fabric writes it |
| `data` | `data.resource` or `data.entity`; exactly one (fabric's validation) |
| `execution_schedule` | `executionSpec.trigger.schedule.cron`; unset, the trigger is `onDemand` |
| `incremental_field` | `executionSpec.field` |
| `data_profile_spec` | `dataProfileSpec` (`samplingPercent`, `rowFilter`) |
| `data_quality_spec` | `dataQualitySpec`: `samplingPercent`, `rowFilter`, `postScanActions.bigqueryExport`, and the rules with every expectation fabric maps (non-null, range, regex, set, uniqueness, statistic range, row condition, table condition, SQL assertion). Range bounds are numbers in fabric and strings in the API; the chart writes them as strings, as the provider does |
| `factories_config` | accepted and ignored: a chart cannot read files. The `data_quality_spec` file goes under `factories_data.data_quality_spec`, exactly its content, in the API's camelCase or fabric's snake_case keys, read as fabric's `factory.tf` reads it |
| `iam`, `iam_by_principals` | merged, one `IAMBinding` per role, exact as fabric's `authoritative_for_role` |
| `iam_bindings` | one `IAMBinding` per entry, with its condition |
| `iam_bindings_additive` | one `IAMMember` per entry (additive); `IAMMember` is `v1alpha1`, so it needs `allow_alpha: true` |
| `allow_alpha` | not a fabric variable: accept the `v1alpha1` `IAMMember` |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the scan (not the IAM) |

Nothing is refused. fabric's three preconditions are template checks with
fabric's messages: one of `data_profile_spec`, `data_quality_spec` and
`factories_config.data_quality_spec`; each rule's dimension one of the
six; each rule exactly one expectation. Two more: `factories_config.data_quality_spec`
without `factories_data.data_quality_spec` stops the render (the chart
cannot read the file), and so does the data without the path. With a
`namePrefix`, an ID over 63 characters stops the render; a name set under
`names` is always checked. 63 is an assumption, the length the catalog
uses where the API documents none.

## Outputs

| Output | From |
| --- | --- |
| `data_scan_id` | `<prefix>-<name>` (or `names.datascan`), from the inputs |
| `id` | `projects/<project>/locations/<region>/dataScans/<id>`, from the inputs |
| `name` | the object's `status.externalRef`, the scan's name with the project ID; fabric's `name` is the API's, which may carry the project number. Null until reported |
| `type` | `status.observedState.type` (`DATA_QUALITY` or `DATA_PROFILE`); null until reported |

## Differences from the module

- **Labels reach the cloud through `spec.labels`.** config-connector-
  extensions' Dataplex kinds take cloud labels from `spec.labels`, so the
  chart writes there the unprefixed keys of `labels` and `tags`; they are
  also on `metadata.labels`.
- **The display name** is the scan's ID as rendered, so with a
  `namePrefix` or `names.datascan` it is that name, where fabric's is
  `<prefix>-<name>`.
- **A factory file's `postScanActions`** may be camelCase
  (`bigqueryExport.resultsTable`); fabric reads only snake_case there.

## From Terraform

A `module "x" { source = ".../modules/dataplex-datascan" ... }` block's
arguments become the values unchanged, apart from the factory's file
(`factories_data`). The scan keeps its ID, so it adopts the scan Terraform
made (`docs/design.md`, "From Terraform"). IAM is `IAMBinding`, exact per
role, and `IAMMember`, additive, as fabric's.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/dataplex-datascan`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/dataplex-datascan)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml)
records the repository, path, release, commit, licence and the date last
synced, and the module is listed in
[`upstream/modules.yaml`](../../../upstream/modules.yaml). To take a newer
release, see [`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=dataplex-datascan`: render cases `basic` (fabric's README
"Data Profiling"), `quality` ("Data Quality", every rule type), `factory`
(the camelCase factory file), `iam` ("IAM", with every IAM variable),
`defaults` (an entity, nothing optional), `names` and `mock`, each
validated against the CRDs in `crds/config-connector-extensions`, and the
refusals in `tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`): a data quality
scan of a BigQuery table and a role on it (`iam`). On 2026-11-13 (offload
VM `off-catalog-1113061109-28826`, config-connector-extensions `35833eb8`, whose fake cloud serves
`getIamPolicy` on a data scan) the scan and its `IAMBinding` became Ready,
the outputs evaluated (`type` null: mockgcp's scan reports none) and both
were deleted. The `IAMMember`s (`v1alpha1`) are only render-tested: alpha
features are not in fake-cloud cases.

Live (`hack/live-apply.sh` `LIVE_CHARTS=dataplex-datascan`, `tests/live.yaml`;
2026-11-13, run `cat-11132355-c86b`, offload VM
`off-catalog-1113235106-15596`, as cce-live-tests, config-connector-extensions `c2f0c7d2`): an on-demand
data quality scan of a BigQuery table of the run, and a role on it.
Passed: the scan and its `IAMBinding` Ready, deleted and gone, with the
dataset and table.

## Changes

- **0.1.0** (2026-11-12): the port: profile and quality scans, the quality
  spec factory, and IAM on the scan.
