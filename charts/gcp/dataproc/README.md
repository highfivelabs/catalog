# dataproc

A Dataproc cluster, on Compute Engine or on GKE, with its IAM, as Config
Connector objects. A port of Cloud Foundation Fabric's
[`modules/dataproc`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/dataproc)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-dataproc` (`package.yaml`). Checked against Config Connector v1.160.0.

## Example

```yaml
project_id: my-project
name: my-cluster
region: europe-west8
```

renders the `DataprocCluster` `my-cluster` (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.cluster` | not a fabric variable: the cluster name in full, used as given (no `namePrefix`) and checked (51 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the cluster name is `<namePrefix>-<name>`; empty changes nothing |
| `labels` | fabric's labels on the cluster: Kubernetes labels on every object, and an unprefixed key a Google Cloud label on the cluster |
| `tags` | not a fabric variable: Google Cloud labels on the cluster |
| `name`, `region`, `project_id` | the cluster's `resourceID`, `location` and `projectRef`, and the project annotation of every object |
| `dataproc_config.cluster_config` | `spec.config`: buckets as `stagingBucketRef` and `tempBucketRef`; `gce_cluster_config` (network, subnetwork and service account as references; `reservation_affinity.values` as a one-item list; `node_group_affinity` as `nodeGroupRef`); master, worker and preemptible worker groups (`secondaryWorkerConfig`; images as `imageRef`); `software_config` (`override_properties` as `properties`); `security_config.kerberos_config` (each `*_uri` as the field without it, `kms_key_uri` as `kmsKeyRef`, `enable_kerberos` and `tgt_lifetime_hours` as a boolean and a number); `autoscaling_config` as `policyRef`; `initialization_action` as one `initializationActions` entry (`timeout_sec` as a duration, `500` to `500s`); `encryption_config` as `gcePdKmsKeyRef`; metrics, lifecycle, endpoint (`enable_http_port_access` as a boolean) and metastore configs |
| `dataproc_config.virtual_cluster_config` | `spec.virtualClusterConfig`: staging bucket, auxiliary services, and the Kubernetes cluster config (`node_pool_target` as the one `nodePoolTarget` entry, the GKE cluster and node pool as references) |
| `iam`, `iam_by_principals`, `iam_bindings` | one `IAMPartialPolicy` on the cluster (`docs/design.md`, "IAM": the listed members are kept, others are left alone; `IAMBinding` does not take `DataprocCluster`, so `iam_bindings` are bindings of it) |
| `iam_bindings_additive` | one `IAMPolicyMember` each |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the cluster |

Refused, in part (`upstream.yaml`):

- `dataproc_config.graceful_decommission_timeout`: a parameter of
  Dataproc's update call, not of the cluster; `DataprocCluster` has no
  field for it (a gap).

Where fabric v60.0.0 reads a value from the wrong path (`main.tf` reads
`reservation_affinity.value`, `gce_cluster_config.node_group_uri`,
`cluster_config.disk_config` for the preemptible workers and
`cluster_config.kerberos_config`, none of which the variable has, so a
Terraform plan setting them fails), and where it drops
`virtual_cluster_config.staging_bucket`, the chart carries the value the
variable holds.

## Outputs

| Output | Value |
| --- | --- |
| `name` | the cluster name, from the inputs |
| `id` | `projects/<project>/regions/<region>/clusters/<name>`, from the inputs |

## From Terraform

A `module "x" { source = ".../modules/dataproc" ... }` block's arguments
become the values unchanged (`examples/dataproc/`). To adopt an existing
cluster, keep its name and set `deletion_policy: ABANDON` for the first
apply (`docs/design.md`, "From Terraform"). fabric ignores changes to
`service_account_scopes` after creation (the service adds scopes); Config
Connector reports such a change as drift. fabric's IAM bindings are
authoritative per role; here they are an `IAMPartialPolicy`, so members
added by hand stay.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/dataproc`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/dataproc)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=dataproc`: render cases `basic`, `gce`, `gke` and
`names`, each validated against Config Connector v1.160.0's CRD schemas,
and the refusals in `tests/*.fail.yaml`.

Fake cloud: `task test-mock MOCK_CHARTS=dataproc` (2026-11-12, offload
VM; `hack/mock-apply.sh` now installs the `dataproc` CRDs):
`tests/mock.values.yaml`'s cluster (one master, zero workers) and its IAM
policy Ready and deleted, and both outputs evaluated.

Not applied live: neither live-test service account has a Dataproc role.

## Changes

- **0.1.0** (2026-11-12): the port.
