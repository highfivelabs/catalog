# biglake-catalog

A BigLake Metastore catalog, its Hive databases and their tables, as
Config Connector objects. A port of Cloud Foundation Fabric's
[`modules/biglake-catalog`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/biglake-catalog)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-biglake-catalog` (`package.yaml`). Every object is a
config-connector-extensions kind in `biglake.gcp.hfl.dev/v1beta1`:
`BigLakeCatalog` and `BigLakeDatabase` (CRDs at `11baa460`) and
`BigLakeTable` (CRD at `d7b52501`). Config Connector's own `BigLakeTable`
(`bigquerybiglake.cnrm.cloud.google.com`) reads BigLake's 403 for a
missing table as a denial and never creates one, so the chart does not
use it.

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
| `namePrefix` | not a fabric variable: an optional convenience; when set, the catalog's name (unless set under `names`) starts with `<namePrefix>_`, its hyphens as underscores (a BigLake ID has no hyphens). Databases and tables keep their names: they live in the catalog |
| `labels`, `tags` | not fabric variables: Kubernetes labels on every object; BigLake resources take no Google Cloud labels |
| `project_id` | every object's project annotation, and the catalog's and databases' `projectRef` |
| `name` | the catalog's name. A BigLake ID: letters, digits and underscores only, as are `names.catalog` and every database and table key |
| `location` | the catalog's and the databases' `location` |
| `databases` | one `BigLakeDatabase` per key (config-connector-extensions, `v1beta1`), named by the key, in the catalog: `type`, `hive_options.location_uri` and `parameters`. Each database's `tables` is one `BigLakeTable` per key (config-connector-extensions, `v1beta1`), named by the key, in its catalog and database (`catalog`, `database`): `type`, and `hive_options`' table type, parameters and storage descriptor (location, input and output formats) |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the catalog, databases and tables |

A name or key with anything but letters, digits and underscores is
refused. Name lengths: with a `namePrefix`, or set under `names`, a
catalog name over 63 characters stops the render. 63 is an
assumption: the API documents no limit for a catalog ID, and 63 is the
length the catalog uses for names that have none documented.

## Outputs

| Output | From |
| --- | --- |
| `catalog_id` | `projects/<project>/locations/<location>/catalogs/<name>`, the catalog's Terraform ID, from the rendered catalog |
| `database_ids` | `{<database>: <catalog_id>/databases/<database>}`, from the rendered databases |
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
and without parameters), `names` and `mock`, each validated against
config-connector-extensions' `BigLakeCatalog`, `BigLakeDatabase` and
`BigLakeTable` CRDs, and the refusals in `tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`): a catalog, a
database and a table. On 2026-11-12 (offload VM
`off-catalog-1113001844-20314`, config-connector-extensions `11baa460`) all
three became Ready, the outputs evaluated and all three were deleted.
That run had Config Connector's `BigLakeTable`. Chart 0.2.0, with
config-connector-extensions' `BigLakeTable`, ran on 2026-11-14 (offload VM
`off-catalog-1114175428-26368`, config-connector-extensions `384d07c0`):
the catalog, the database and the table became Ready, the outputs
evaluated and all three were deleted.

Live (`hack/live-apply.sh` `LIVE_CHARTS=biglake-catalog`, `tests/live.yaml`):
blocked by a role. As cce-live-tests (2026-11-13, `cat-11132355-c86b`)
and as catalog-live-tests (2026-11-14, `cat-11140120-96a6`), Google Cloud
denied `biglake.catalogs.get`, `biglake.databases.get` and
`biglake.tables.get`: neither account holds a BigLake role
(`roles/biglake.admin`). Nothing was made or left.

The rerun (2026-11-14, `cat-11140810-4fc4`, offload VM
`off-catalog-1114080558-15613`, as cce-live-tests, now holding
`roles/biglake.admin`; config-connector-extensions `aec29642`) failed the
same way: "Permission 'biglake.catalogs.get' denied ... (or it may not
exist)", and the same for the database and the table, though the role
grants those permissions. BigLake answers a get of a catalog that does
not exist with 403, not 404 (an administrator's get of a made-up catalog
name returns 403 too, while the list returns 200), so config-connector-
extensions' `BigLakeCatalog`, which reads before it creates, takes the
missing catalog for a denial and never creates it. The fix belongs in
config-connector-extensions (read a 403 on get as not found, or look the
catalog up by list). The bucket was made and deleted; nothing was left.

config-connector-extensions `2e1ccc9e` (#127) reads that 403 as not
found for `BigLakeCatalog` only. The rerun (2026-11-14,
`cat-11141340-9f1f`, offload VM `off-catalog-1114133543-14417`, as
catalog-live-tests, a 30-minute limit; the catalog ID
`cat_11141340_9f1f_lake`, letters, digits and underscores only) got
further: the **catalog was Ready, deleted and gone**, as was the bucket.
The database and the table failed the same way the catalog had:
"Permission 'biglake.databases.get' denied" and "Permission
'biglake.tables.get' denied", though catalog-live-tests holds
`roles/biglake.admin` and had just made the catalog. BigLake answers a
get of a missing database or table with 403 too. The fixes belong
upstream: config-connector-extensions' `BigLakeDatabase` needs
`missingIs403` as `BigLakeCatalog` has it, and Config Connector's own
`BigLakeTable` (`bigquerybiglake.cnrm.cloud.google.com`) takes the 403
for a denial the same way. Neither was made, so each delete was a no-op;
the sweep after found nothing left.

config-connector-extensions `d7b52501` (#128) reads that 403 as not
found for `BigLakeDatabase` too, and adds its own `BigLakeTable`, which
chart 0.2.0 renders. The rerun (2026-11-14, `cat-11141549-4cb0`, offload
VM `off-catalog-1114154511-1030`, as catalog-live-tests, a 30-minute
limit) **made everything**: the catalog (`cat_11141549_4cb0_lake`), the
database `live_db`, the table `live_table` and the bucket were Ready
within seconds (the database's and the table's first creates were
refused with 403 just after the catalog was made, and the retries
went through), and the outputs evaluated. **The delete failed.** Every
object is deleted at once; the catalog's delete went through and took
its database and table with it, and BigLake then answered the
database's and the table's deletes and gets with 403. Once an object
has made its resource, config-connector-extensions reads a 403 as a
denial, not as gone (`pkg/discokind`'s `Find` reads it as not found
only before a create, and `Delete` not at all), so both finalizers held
for the whole 30 minutes and the run failed. The fix belongs in
config-connector-extensions: for a `missingIs403` kind, a 403 on the
delete or the get after it should end the delete. The sweep removed
the bucket; a check by hand found no catalog in `us`, `us-central1` or
`eu`, no `cat-` bucket and no VM left.

config-connector-extensions `384d07c0` (#129) takes that 403, while
deleting, for gone once a listing proves it (the database's and the
table's collections answer 403 too after the catalog went, and the
project's catalogs list without the catalog). The rerun (2026-11-14,
`cat-11141804-e54f`, offload VM `off-catalog-1114180022-11976`, as
catalog-live-tests) **passed**: the bucket, the catalog, the database
and the table were Ready, all deleted at once, and all gone from Google
Cloud; the outputs evaluated. A check by hand after found no catalog in
`us`, `us-central1` or `eu` (so no database or table), no `cat-` or
`cce-` bucket and no VM left.

## Changes

- **0.2.0** (2026-11-14): tables are config-connector-extensions'
  `BigLakeTable` (`biglake.gcp.hfl.dev/v1beta1`, at `d7b52501`), not
  Config Connector's, which never creates a table against the real API.
  A `namePrefix` goes on the catalog's name with an underscore and its
  hyphens as underscores; names and keys are refused unless they are
  letters, digits and underscores. Outputs come from the rendered
  objects.
- **0.1.0** (2026-11-12): the port: the catalog, its databases and their
  tables.
