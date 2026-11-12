# alloydb

An AlloyDB for PostgreSQL cluster with its primary instance, read pools,
an optional cross-region secondary cluster with its instance and read
pools, IAM users and tag bindings, as Config Connector objects. A port of
Cloud Foundation Fabric's
[`modules/alloydb`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/alloydb)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-alloydb` (`package.yaml`). Checked against Config Connector v1.160.0.

## Example

```yaml
project_id: myproject
cluster_name: db
instance_name: db
location: europe-west8
network_config:
  psa_config:
    network: projects/myproject/global/networks/my-network
```

renders the `AlloyDBCluster` `db` and its regional primary
`AlloyDBInstance` `db`, on the network's private services access range
(`tests/golden/basic.yaml`). The network needs its private services access
connection first (the `net-vpc` chart's `psa_configs`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.cluster`, `names.instance`, `names.secondaryCluster`, `names.secondaryInstance` | not fabric variables: the clusters' and instances' IDs in full, used as given (no `namePrefix`, no `prefix`) and checked (63 characters, a leading letter) (`docs/design.md`, "Names, labels and tags"). Read pools are named by their keys, as in fabric |
| `namePrefix` | not a fabric variable: an optional convenience. When set, every derived ID (the clusters, the instances, the read pools) starts with `<namePrefix>-`, in front of the module's own `prefix`; never a name set under `names`; empty changes nothing |
| `labels` | Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label (Config Connector copies it to the clusters' and instances' labels), so it must be a valid one, and goes on the automated backups, as fabric's `labels` do |
| `tags` | cloud labels on every object (Google Cloud labels), and on the automated backups |
| `project_id` (required) | the clusters' `projectRef` |
| `cluster_name`, `instance_name`, `prefix` | the primary cluster's and instance's IDs, `<prefix>-<name>` (`<name>` with `prefix` null); `prefix` cannot be `""`, as in fabric |
| `location`, `database_version`, `cluster_display_name` | the primary cluster's `location`, `databaseVersion` and `displayName` (its ID when null) |
| `deletion_policy` | fabric's `DEFAULT` or `FORCE` is the primary cluster's `deletionPolicy` (the secondary's is always `FORCE`, as fabric's). The catalog's `ABANDON` keeps the clusters, instances and users when the component is deleted; `DELETE` is the same as null; `PREVENT` is refused (`docs/design.md`, "Deletion") |
| `network_config.psa_config` | the clusters' `networkConfig.networkRef` and `allocatedIpRange`; `enable_public_ip`, `enable_outbound_public_ip` and `authorized_external_networks` the primary and secondary instances' `networkConfig` (fabric's check that authorized networks need a public IP). `psc_config` is refused (below) |
| `automated_backup_configuration` | `automatedBackupPolicy` on each cluster when `enabled`, with fabric's defaults (a 1800s window, every day at 23:00, 7 backups kept); the primary's `location` only when set, the secondary's its region; the KMS key of each side |
| `continuous_backup_configuration` | `continuousBackupConfig` on each cluster (on, 14 days, by default), with the KMS key of each side |
| `encryption_config` | `encryptionConfig.kmsKeyNameRef` of the primary (`primary_kms_key_name`) and secondary (`secondary_kms_key_name`) cluster and of their backups |
| `maintenance_config` | `maintenanceUpdatePolicy` on each cluster when `enabled` (Sunday, 23:00, by default) |
| `display_name`, `availability_type`, `gce_zone` | the primary instance's `displayName` (its ID when null), `availabilityType` and, for a `ZONAL` instance only, `gceZone` |
| `machine_config` | the primary instance's `machineConfig` (2 vCPUs by default); the secondary's when `cross_region_replication.secondary_machine_config` does not set it |
| `flags`, `connection_pool_flags`, `annotations` | `databaseFlags`, `connectionPoolConfig` (on, with these flags) and `annotations` of the instances, as fabric sets them (`flags` on the secondary only once it is promoted or after a switchover) |
| `query_insights_config`, `observability_config` | `queryInsightsConfig` (by default) or, when `observability_config.enabled`, `observabilityConfig` instead, on the primary; the secondary takes `queryInsightsConfig`, as in fabric |
| `read_pool` | one `READ_POOL` `AlloyDBInstance` per entry in the primary cluster, `hfl.dev/id` `read-pool:<key>`, named `<prefix>-<key>`: its `node_count`, `flags`, `machine_config`, public IP, insights or observability |
| `cross_region_replication` | with `enabled`, the secondary `AlloyDBCluster` (`SECONDARY`, following the primary, or `PRIMARY` with `promote_secondary`) in `region`, its `AlloyDBInstance` and one read pool per `read_pool` entry (`secondary-read-pool:<key>`); with `switchover_mode`, the primary becomes the `SECONDARY` of the secondary (fabric's checks: a region, not both modes) |
| `users` | one `AlloyDBUser` per `ALLOYDB_IAM_USER` or `ALLOYDB_IAM_GROUP` user, `hfl.dev/id` `user:<key>`, with its `roles` (`alloydbsuperuser` by default) |
| `tag_bindings`, `project_number` | one `TagsLocationTagBinding` per tag on each cluster, its parent `//alloydb.googleapis.com/projects/<project_number>/locations/<l>/clusters/<id>`, as fabric writes it. fabric reads the number with a data source when `project_number` is null; a chart cannot, so `tag_bindings` needs `project_number` |
| `deletion_protection`, `skip_await_major_version_upgrade` | accepted and ignored, whatever their values (below, "Differences from the module") |
| `subscription_type` | `STANDARD` (the default, and the cloud's) only (below) |

Refused when set:

| Variable | Why |
| --- | --- |
| `initial_user`, `users` of type `ALLOYDB_BUILT_IN` (the default type), `users[].password` | a password given in values would be in the rendered manifest, and Terraform's `random_password` has no Config Connector equivalent. `AlloyDBCluster` and `AlloyDBUser` take a password from a Kubernetes Secret (`valueFrom.secretKeyRef`), which the chart does not take yet: how a component gets a database password is an open question (as `cloudsql-instance`'s root password) |
| `client_connection_config`, `read_pool[].client_connection_config`, `cross_region_replication.read_pool[].client_connection_config` | `AlloyDBInstance` has no `clientConnectionConfig` (`require_connectors`, `ssl_mode`) |
| `network_config.psc_config` | `AlloyDBCluster` has no `pscConfig` and `AlloyDBInstance` no `pscInstanceConfig`, so Private Service Connect cannot be set up |
| `subscription_type: TRIAL` | `AlloyDBCluster` has no subscription type field |

## Outputs

| Output | From |
| --- | --- |
| `cluster_id`, `secondary_cluster_id` | `projects/<project>/locations/<region>/clusters/<id>`, as Terraform's `id` |
| `cluster_name`, `secondary_cluster_name` | the cluster's `status.name` |
| `id`, `ids`, `secondary_id` | `<cluster id>/instances/<id>`, as Terraform's `id` |
| `name`, `names` | the instance's `status.name` |
| `ip`, `ips`, `secondary_ip` | `status.ipAddress`, or null |
| `public_ip`, `secondary_public_ip` | `status.publicIpAddress`, or null |
| `outbound_public_ips`, `secondary_outbound_public_ips` | `status.outboundPublicIpAddresses` |
| `read_pool_ids`, `read_pool_ips`, `secondary_read_pool_ids`, `secondary_read_pool_ips` | each read pool's ID and `status.ipAddress`, by key |

The maps `ids`, `ips` and `names` are keyed `primary` and `secondary`, as
fabric keys them; the secondary's values are null without cross-region
replication. Not outputs: `instance`, `instances`, `read_pools`,
`secondary_instance` and `secondary_read_pools` (whole Terraform objects),
`user_passwords` (the chart makes no passwords), and `psc_dns_name`,
`psc_dns_names`, `service_attachment` and `service_attachments`, which need
Private Service Connect (refused) and which `AlloyDBInstance` does not
report (`docs/design.md`, "Outputs").

## Differences from the module

- **`deletion_protection`** and **`skip_await_major_version_upgrade`** are
  accepted and do nothing: both are the Terraform provider's own behaviour
  (refusing to destroy, waiting on an upgrade), and `AlloyDBCluster` has no
  field for either. Use `deletion_policy: ABANDON` to keep the clusters.
- **Annotations** go on the instances only: `AlloyDBCluster` has no
  annotations field (fabric sets them on the clusters too).
- **Display names** default to the resource's ID as rendered, with the
  `namePrefix`, where fabric's default has none (without a `namePrefix`
  they are fabric's). fabric ignores changes to the clusters' display
  names (`ignore_changes`); the chart sets them like any other field.
- **`cross_region_replication.secondary_instance_display_name`** is not
  read, here as in fabric: fabric names the secondary instance's display
  name after `secondary_instance_name` (an upstream bug, kept so an adopted
  instance does not change).
- **Promoting the secondary**: fabric reads the secondary cluster's live
  type and keeps its instance `SECONDARY` for the apply that promotes it; a
  chart renders from inputs, so the instance's `instanceType` follows the
  cluster's (`PRIMARY`) at once.
- **`automated_backup_configuration.retention_period`** cannot be used, as
  in fabric: `retention_count` defaults to 7 when unset, and fabric's
  validation refuses both together (an upstream bug, kept).
- **References**: the instances, users and secondary cluster name their
  cluster by its cloud name (`external`), not by its object ("Tests",
  below), so Config Connector creates an instance once its cluster
  exists by retrying, rather than by waiting on the cluster object.
- **Outputs** come from the live objects, so a dependent waits until they
  are ready.

## From Terraform

A `module "x" { source = ".../modules/alloydb" ... }` block's arguments
become the values unchanged (`examples/alloydb/`). To adopt an existing
cluster, keep its names: Config Connector acquires the cluster and
instances of those IDs (`docs/design.md`, "From Terraform"). Built-in users
stay managed outside the component until passwords are settled.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/alloydb`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/alloydb)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=alloydb`: render cases `basic`, `full` (every accepted
input on the primary side: a zonal instance with public IP, backups,
maintenance, KMS, flags, pooling, observability, two read pools, IAM users,
a tag binding, ABANDON), `cross-region` (a secondary with a read pool and
its own KMS key), `promote`, `switchover`, `names` and `mock`, each
validated against Config Connector v1.160.0's CRD schemas, and the
refusals in `tests/*.fail.yaml`. `tests/name-prefix.yaml` exempts users
and tag bindings.

Applied to the fake cloud on 2026-11-12 (`task test-mock
MOCK_CHARTS=alloydb`, `tests/mock.values.yaml`: a zonal cluster and
instance with one read pool): every object Ready, the outputs evaluated
against the live objects, every object deleted at once and gone. The first
run found that deleting the component left both instances' objects behind
("reference AlloyDBCluster ... is not found"): Config Connector resolves an
`AlloyDBInstance`'s `clusterRef` before deleting it, and the cluster object
had gone first (mockgcp, like `deletionPolicy: FORCE` in Google Cloud,
deletes a cluster with its instances). So the instances, the users and the
secondary cluster name their cluster by its cloud name
(`clusterRef.external`), which needs no object to resolve; the second run
passed.

Not applied live: no live-test service account has AlloyDB roles, and an
AlloyDB cluster bills while it exists.

## Changes

- **0.1.0** (2026-11-12): the port.
