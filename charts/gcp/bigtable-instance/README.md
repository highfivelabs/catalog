# bigtable-instance

A Cloud Bigtable instance with its clusters, tables, garbage collection
policies and IAM, as Config Connector objects. A port of Cloud Foundation
Fabric's
[`modules/bigtable-instance`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/bigtable-instance)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-bigtable-instance` (`package.yaml`). Checked against Config Connector
v1.160.0.

## Example

```yaml
project_id: my-project
name: instance
clusters:
  my-cluster: {zone: europe-west1-b}
```

renders the `BigtableInstance` `instance` with one cluster
(`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.instance` | not a fabric variable: the instance ID in full, used as given (no `namePrefix`) and checked (6 to 33 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the instance ID is `<namePrefix>-<name>`; empty changes nothing |
| `labels` | fabric's labels on the instance: Kubernetes labels on every object, and an unprefixed key a Google Cloud label on the instance |
| `tags` | not a fabric variable: Google Cloud labels on the instance |
| `name`, `display_name` | the instance ID (`resourceID`) and `displayName` (`name` when unset, as fabric) |
| `project_id` | the project annotation of every object |
| `clusters` | one `cluster` entry each: `clusterId`, `zone`, `storageType`, `numNodes` (only without autoscaling, as fabric), `autoscalingConfig` |
| `default_autoscaling` | `autoscalingConfig` of every cluster that sets none (fabric then drops `num_nodes`) |
| `encryption_key` | `kmsKeyRef` of every cluster |
| `deletion_protection` | `deletionProtection` (true, fabric's default) |
| `iam` | one `IAMPartialPolicy` on the instance (`docs/design.md`, "IAM": the listed members are kept, others are left alone) |
| `tables` | a `BigtableTable` each, with its column families and split keys |
| `default_gc_policy`, `tables.*.column_families.*.gc_policy` | a `BigtableGCPolicy` per column family whose policy (its own, else the default) is set: `gcRules`, `mode`, `deletionPolicy`, `maxAge`, `maxVersion` |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the instance and its tables |

Refused, in part (`upstream.yaml`):

- `clusters`: a cluster without a `zone`. Terraform takes the provider's
  default zone; `BigtableInstance` requires each cluster's zone, and a
  chart has no provider default, so the render stops naming the cluster.

## Outputs

| Output | Value |
| --- | --- |
| `id` | `projects/<project>/instances/<instance ID>`, from the inputs |
| `table_ids` | `{TABLE: projects/<project>/instances/<instance ID>/tables/<TABLE>}`, from the inputs |

fabric's `instance` and `tables` are whole Terraform objects, which a
Package does not output (`docs/design.md`, "Outputs").

## From Terraform

A `module "x" { source = ".../modules/bigtable-instance" ... }` block's
arguments become the values unchanged (`examples/bigtable-instance/`). To
adopt an existing instance, keep its ID and set `deletion_policy: ABANDON`
for the first apply (`docs/design.md`, "From Terraform"). fabric's IAM
bindings are authoritative per role; here they are an `IAMPartialPolicy`,
so members added by hand stay.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/bigtable-instance`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/bigtable-instance)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=bigtable-instance`: render cases `basic`, `full`,
`autoscaling` and `names`, each validated against Config Connector
v1.160.0's CRD schemas, and the refusals in `tests/*.fail.yaml`.

Fake cloud: `task test-mock MOCK_CHARTS=bigtable-instance` (2026-11-12,
offload VM; `hack/mock-apply.sh` now installs the `bigtable` CRDs):
`tests/mock.values.yaml`'s instance, table, garbage collection policy and
IAM policy all Ready and deleted, and both outputs evaluated.

Not applied live: neither live-test service account has a Bigtable role.

## Changes

- **0.1.0** (2026-11-12): the port.
