# dataplex

A Dataplex lake, its zones, the zones' assets (Cloud Storage buckets and
BigQuery datasets), and IAM on the lake and on each zone, as Config
Connector objects. A port of Cloud Foundation Fabric's
[`modules/dataplex`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/dataplex)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-dataplex` (`package.yaml`). Checked against config-connector-extensions'
`DataplexLake`, `DataplexZone`, `DataplexAsset`
(`dataplex.gcp.hfl.dev/v1beta1`) and `IAMBinding` (`iam.gcp.hfl.dev/v1beta1`),
at `11baa460`.

## Example

```yaml
name: terraform-lake
prefix: test
project_id: myproject
region: europe-west2
iam:
  roles/dataplex.viewer: ["group:analysts@example.com"]
zones:
  landing:
    type: RAW
    discovery: true
    assets:
      gcs_1:
        resource_name: gcs_bucket
        cron_schedule: "15 15 * * *"
        discovery_spec_enabled: true
        resource_spec_type: STORAGE_BUCKET
  curated:
    type: CURATED
    discovery: false
    iam:
      roles/dataplex.dataReader: ["group:analysts@example.com"]
    assets: {}
```

renders the `DataplexLake` `test-terraform-lake`, the zones `landing` and
`curated`, the asset `gcs_1` on `projects/myproject/buckets/gcs_bucket`,
and an `IAMBinding` on the lake and one on `curated`
(`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults. The
chart carries all seven.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.lake` sets the lake's name in full |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the lake's derived name starts with `<namePrefix>-` (outside fabric's `prefix`). Zones and assets keep their names: they live in the lake |
| `labels` | not a fabric variable: Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label |
| `tags` | not a fabric variable: cloud labels on every resource |
| `project_id` | every object's project annotation and `projectRef`, and an asset's resource project when it gives none |
| `region` | every object's `location` |
| `name`, `prefix` | the lake's name, `<prefix>-<name>` (fabric's) |
| `iam` | one `IAMBinding` per role on the lake (config-connector-extensions, `v1beta1`): exact, as fabric's `google_dataplex_lake_iam_binding` |
| `location_type` | every zone's `resourceSpec.locationType` |
| `zones` | one `DataplexZone` per key, named by the key: `type`, `discovery` (default true) as `discoverySpec.enabled`, `iam` as one `IAMBinding` per role on the zone. Each zone's `assets` is one `DataplexAsset` per key, named by the key: discovery (default on) with its `cron_schedule` (default `15 15 * * *`) only when on, as fabric does, and `resourceSpec` `projects/<resource_project>/buckets/<resource_name>` or `.../datasets/...` by `resource_spec_type` (default `STORAGE_BUCKET`; another type is refused, as fabric's validation refuses it) |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the lake, zones and assets (not the IAM bindings) |

Nothing is refused. Name lengths: with a `namePrefix`, or set under
`names`, a lake name over 63 characters stops the render. 63 is an
assumption: the API documents no limit for a lake ID, and 63 is the length
the catalog uses for names that have none documented.

## Outputs

| Output | From |
| --- | --- |
| `lake` | the lake's name, from the inputs |
| `id` | `projects/<project>/locations/<region>/lakes/<lake>`, the lake's Terraform ID, from the inputs |
| `assets` | fabric's `local.zone_assets`, from the inputs: one entry per asset (zones, then assets, in key order, as Terraform orders them) with `zone_name`, `asset_name`, `resource_name`, `resource_project`, `cron_schedule` (null with discovery off), `discovery_spec_enabled` and `resource_spec_type` |
| `zones` | the zones that have an asset, in key order (fabric's `distinct` of the assets' zones) |

## From Terraform

A `module "x" { source = ".../modules/dataplex" ... }` block's arguments
become the values unchanged (`examples/dataplex/`). Names are fabric's, so
the lake, zones and assets adopt what Terraform made (`docs/design.md`,
"From Terraform"). IAM is `IAMBinding`, exact per role as fabric's is:
members added out of band to a role the chart manages are removed.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/dataplex`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/dataplex)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=dataplex`: render cases `basic` (fabric's README
example), `defaults` (a lake alone), `full` (every variable: a prefix, a
multi-region location type, assets of both types, in another project,
discovery off), `names` and `mock`, each validated against
config-connector-extensions' CRDs (`crds/config-connector-extensions`), and
the refusals in `tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`): a lake, a RAW
zone, a bucket asset, a role on the lake and one on the zone. On
2026-11-13 (offload VM `off-catalog-1113061109-28826`, config-connector-extensions `35833eb8`, whose
fake cloud serves `getIamPolicy` on a lake and a zone) all five objects
became Ready, the outputs evaluated and all five were deleted.

Not applied live: the Dataplex API is enabled in the live-test project,
but neither live-test service account has a Dataplex role.

## Changes

- **0.1.0** (2026-11-12): the port: the lake, zones, assets and IAM on the
  lake and the zones.
