# data-catalog-tag

Data Catalog tags on BigQuery datasets, tables and columns, as Config
Connector objects. A port of Cloud Foundation Fabric's
[`modules/data-catalog-tag`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/data-catalog-tag)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-data-catalog-tag` (`package.yaml`). Checked against
config-connector-extensions' `DataCatalogTag`
(`datacatalog.gcp.hfl.dev/v1beta1`), at `0ee17dd`; Config Connector
v1.160.0 has it only as `v1alpha1`.

## Example

```yaml
tags:
  landing/countries:
    project_id: project-data-product
    parent: projects/project-data-product/datasets/landing/tables/countries
    column: country
    location: europe-west1
    template: projects/project-datagov/locations/europe-west1/tagTemplates/demo
    fields:
      source:
        string_value: DB-1 Table-A Column-B
```

renders one `DataCatalogTag` on the `country` column of the table's
entry, `projects/project-data-product/locations/europe-west1/entryGroups/@bigquery/entries/<the table's path, base64url>`,
filling in the template's `source` field (`tests/golden/column.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable; takes no key: a tag's ID is the API's, so the chart gives no cloud name |
| `namePrefix` | not a fabric variable; changes nothing here, for the same reason |
| `labels` | not a fabric variable: Kubernetes labels on every object. Tags have no cloud labels |
| `tags` | the module's variable (not cloud labels, as in other charts): one `DataCatalogTag` per key. `parent` (a dataset or table path) names the entry in the `@bigquery` entry group of `project_id` and `location`, base64url-encoded without padding, as fabric names it (`entryRef.external`); `template` is `templateRef.external`; `column` is `column`; each of `fields` is one field, with `bool_value`, `double_value`, `string_value` and `timestamp_value` as the kind's same-named values and `enum_value` as `enumValue.displayName` |
| `factories_config` | accepted and ignored: a chart cannot read files. Each file of the `tags` folder goes under `factories_data.tags.<file name without .yaml>`, exactly its content; a tag of `tags` wins over the file of the same key, as fabric's `merge` does |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the tags |

## Outputs

| Output | From |
| --- | --- |
| `data_catalog_tag_ids` | by the tag's key, the tag's name (Terraform's ID), `.../entries/<entry>/tags/<id>`, from `status.externalRef`: the API assigns the ID at create. Null until reported |

## Differences from the module

- **No Kubernetes reference to the entry or the template.** As fabric's,
  the entry is named from the BigQuery resource and the template by its
  path; a tag whose template does not exist yet is refused and retried.
- **The project annotation** is the tag's `project_id`; the kind takes
  its project from the entry.

## From Terraform

A `module "x" { source = ".../modules/data-catalog-tag" ... }` block's
arguments become the values unchanged, apart from the factory's files
(`factories_data.tags`). A tag has an ID only the API knows, so an
existing tag is not adopted by these values: Terraform's tag must be
removed from its state and left to be replaced, or acquired by setting
the kind's `resourceID` by hand (`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/data-catalog-tag`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/data-catalog-tag)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml)
records the repository, path, release, commit, licence and the date last
synced, and the module is listed in
[`upstream/modules.yaml`](../../../upstream/modules.yaml). To take a newer
release, see [`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=data-catalog-tag`: render cases `basic`, `table`,
`column` and `factory` (fabric's four README examples, the last with the
file as data), `names` and `mock`, each validated against the CRDs in
`crds/config-connector-extensions`, and the refusals in
`tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`): a tag on a
dataset and one on a column of a table, with the tag template
`tests/mock.needs.yaml` makes (Config Connector's `v1alpha1`
`DataCatalogTagTemplate`, a fixture, not part of the chart). On
2026-11-13 (offload VM `off-catalog-1113031012-32244`;
config-connector-extensions `0ee17dd`) both tags became Ready, the output
`data_catalog_tag_ids` evaluated (both tags' names, under the entries
fabric's base64url naming gives) and both were deleted. mockgcp does not
check that the `@bigquery` entry exists, checks no field against the
template, and gives every tag the same ID (`mocktagid`).

Live (`hack/live-apply.sh` `LIVE_CHARTS=data-catalog-tag`, `tests/live.yaml`;
2026-11-13, run `cat-11132355-c86b`, as cce-live-tests, config-connector-extensions `c2f0c7d2`): a tag on
a BigQuery dataset of the run and one on a column of its table, with a
tag template `tests/live.extra.yaml` makes. Failed, on the API's side:
Data Catalog answered "Error 404: Method not found" both to the template
(Config Connector's `DataCatalogTagTemplate`) and to both tags
(config-connector-extensions' `DataCatalogTag`, which did resolve each
BigQuery entry first). Data Catalog's tag methods are retired for this
project (Dataplex Universal Catalog replaces them), so the kind cannot be
proven live here. Nothing was left.

## Changes

- **0.1.0** (2026-11-12): the port: tags from the variable and the
  factory.
