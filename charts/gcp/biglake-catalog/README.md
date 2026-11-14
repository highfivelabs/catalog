# biglake-catalog

A BigLake Metastore catalog, its Hive databases and their tables, as
Config Connector objects. A port of Cloud Foundation Fabric's
[`modules/biglake-catalog`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/biglake-catalog)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-biglake-catalog` (`package.yaml`). Checked against Config Connector
v1.160.0 (`BigLakeTable`) and config-connector-extensions' `BigLakeCatalog`
and `BigLakeDatabase` (`biglake.gcp.hfl.dev/v1beta1`, at `11baa460`).

## Example

```yaml
project_id: my-project
name: my_catalog
location: US
databases:
  my_database:
    type: HIVE
    hive_options:
      location_uri: gs://my-bucket/my-database-folder
      parameters: {owner: John Doe}
    tables:
      my_table:
        type: HIVE
        hive_options:
          table_type: MANAGED_TABLE
          location_uri: gs://my-bucket/my-table-folder
          input_format: org.apache.hadoop.mapred.SequenceFileInputFormat
          output_format: org.apache.hadoop.hive.ql.io.HiveSequenceFileOutputFormat
          parameters: {provider: iceberg}
```

renders the `BigLakeCatalog` `my_catalog`, the `BigLakeDatabase`
`my_database` in it and the `BigLakeTable` `my_table` in the database
(`tests/golden/basic.yaml` has fabric's full example, with Spark's
parameters).

## Values

The module's variables, with the same names, types and defaults. The
chart carries all four.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.catalog` sets the catalog's name in full |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the catalog's name (unless set under `names`) starts with `<namePrefix>-`. Databases and tables keep their names: they live in the catalog |
| `labels`, `tags` | not fabric variables: Kubernetes labels on every object; BigLake resources take no Google Cloud labels |
| `project_id` | every object's project annotation, and the catalog's and databases' `projectRef` |
| `name` | the catalog's name |
| `location` | the catalog's and the databases' `location` |
| `databases` | one `BigLakeDatabase` per key (config-connector-extensions, `v1beta1`), named by the key, in the catalog: `type`, `hive_options.location_uri` and `parameters`. Each database's `tables` is one `BigLakeTable` per key (Config Connector, `v1beta1`), named by the key, in its database (`parentDatabaseRef.external`): `type`, and `hive_options`' table type, parameters and storage descriptor (location, input and output formats) |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the catalog, databases and tables |

Nothing is refused. Name lengths: with a `namePrefix`, or set under
`names`, a catalog name over 63 characters stops the render. 63 is an
assumption: the API documents no limit for a catalog ID, and 63 is the
length the catalog uses for names that have none documented.

## Outputs

| Output | From |
| --- | --- |
| `catalog_id` | `projects/<project>/locations/<location>/catalogs/<name>`, the catalog's Terraform ID, from the inputs |
| `database_ids` | `{<database>: <catalog_id>/databases/<database>}`, from the inputs |
| `table_ids` | `{<database>-<table>: <database ID>/tables/<table>}`, keyed as fabric keys its tables, from the rendered tables |
| `catalog`, `databases`, `tables` | the same IDs. fabric's outputs are whole objects; a Package outputs the field a consumer takes (`docs/design.md`, "Outputs") |

## From Terraform

A `module "x" { source = ".../modules/biglake-catalog" ... }` block's
arguments become the values unchanged (`examples/biglake-catalog/`). Names
are fabric's, so the catalog, databases and tables adopt what Terraform
made (`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/biglake-catalog`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/biglake-catalog)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=biglake-catalog`: render cases `basic` (fabric's README
example), `defaults` (a catalog alone), `full` (two databases, tables with
and without parameters), `names` and `mock`, each validated against Config
Connector v1.160.0's CRD schemas and config-connector-extensions'
`BigLakeCatalog` and `BigLakeDatabase` CRDs, and the refusals in
`tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`): a catalog, a
database and a table. On 2026-11-12 (offload VM
`off-catalog-1113001844-20314`, config-connector-extensions `11baa460`) all
three became Ready, the outputs evaluated and all three were deleted.

Live (`hack/live-apply.sh` `LIVE_CHARTS=biglake-catalog`, `tests/live.yaml`):
blocked by a role. As cce-live-tests (2026-11-13, `cat-11132355-c86b`)
and as catalog-live-tests (2026-11-14, `cat-11140120-96a6`), Google Cloud
denied `biglake.catalogs.get`, `biglake.databases.get` and
`biglake.tables.get`: neither account holds a BigLake role
(`roles/biglake.admin`). Nothing was made or left.

## Changes

- **0.1.0** (2026-11-12): the port: the catalog, its databases and their
  tables.
