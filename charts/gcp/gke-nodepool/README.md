# gke-nodepool

A GKE node pool on an existing cluster, and optionally its node service
account, as Config Connector objects. A port of Cloud Foundation Fabric's
[`modules/gke-nodepool`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/gke-nodepool)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-gke-nodepool` (`package.yaml`). Checked against Config Connector
v1.160.0. It pairs with a cluster made by `gke-cluster` (or any other):
`cluster_name` (or `cluster_id`) names it.

## Example

```yaml
project_id: my-project
cluster_name: cluster-0
location: europe-west1-b
name: nodepool-1
```

renders the `ContainerNodePool` `nodepool-1` on `cluster-0`, running as
the Compute Engine default service account with fabric's default scopes
(`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.nodepool`, `names.serviceAccount` | not fabric variables: the node pool name (40 characters) and the created account's ID (30) in full, used as given (no `namePrefix`); unset, the pool is `name` (or the component's name when `name` is null) and the account `tf-gke-<name>`, as fabric names them (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the derived node pool name and account ID start with `<namePrefix>-`; empty changes nothing |
| `labels` | fabric's node resource labels: `nodeConfig.resourceLabels` (the unprefixed keys); as every chart's `labels`, also Kubernetes labels on every object |
| `tags` | a list is fabric's network tags, `nodeConfig.tags`; a map is every chart's `tags`, cloud labels: on the nodes (`resourceLabels`) and on every object |
| `project_id`, `location`, `cluster_name`, `cluster_id` | the project annotation, `location` and `clusterRef`: the cluster's name (`cluster_name`, or the last segment of `cluster_id`), in the node pool's project and location |
| `name`, `gke_version`, `max_pods_per_node`, `node_count`, `node_locations` | `resourceID`, `version`, `maxPodsPerNode`, `initialNodeCount` and `nodeCount`, `nodeLocations` |
| `nodepool_config` | `autoscaling` (per zone, or total with `use_total_nodes`), `management`, `placementPolicy`, `queuedProvisioning`, `upgradeSettings` with blue-green settings |
| `network_config` | `networkConfig`: private nodes, the pod range (made, named or by CIDR), additional node and pod networks, pod CIDR overprovisioning |
| `node_config` | `nodeConfig`: machine, image, boot disk (`boot_disk` or the older `disk_size_gb`, `disk_type`, `boot_disk_kms_key`), local, ephemeral and NVMe SSDs, GCFS (on COS containerd images) and gVNIC (on COS images), GPUs with driver and sharing, kubelet and Linux node settings, gVisor, shielded instance, workload metadata mode, advanced machine features, containerd (private registry CAs, writable cgroups, registry hosts), spot or preemptible; `metadata` with `disable-legacy-endpoints: "true"` added, as fabric adds it |
| `k8s_labels`, `taints` | `nodeConfig.labels` and `nodeConfig.taint`; a Windows image adds fabric's `node.kubernetes.io/os=windows:NO_EXECUTE` taint |
| `reservation_affinity`, `resource_manager_tags`, `sole_tenant_nodegroup` | `nodeConfig.reservationAffinity`, `.resourceManagerTags`, `.nodeGroupRef` |
| `service_account` | `create: true`: an `IAMServiceAccount` (ID from `email`'s local part, else `tf-gke-<name>`) the nodes run as; `email` alone: that account; neither: the Compute Engine default. `oauth_scopes` default to fabric's five |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the node pool and account |

Refused when set:

| Variable | Why |
| --- | --- |
| `node_config.boot_disk.provisioned_iops`, `.provisioned_throughput` | `nodeConfig` has no `bootDisk` |
| `node_config.flex_start` | `nodeConfig` has no `flexStart` |
| `node_config.kubelet_config.insecure_kubelet_readonly_port_enabled`, `.container_log_max_size`, `.container_log_max_files`, `.allowed_unsafe_sysctls` | `kubeletConfig` has no such fields |
| `network_config.total_egress_bandwidth_tier` | `networkConfig` has no `networkPerformanceConfig` |

## Outputs

| Output | From |
| --- | --- |
| `name` | the node pool's name |
| `id` | `<project>/<location>/<cluster>/<name>`, the provider's id, as fabric outputs it |
| `service_account_email` | the created account's email, or `service_account.email`, or null |
| `service_account_iam_email` | `serviceAccount:<email>` (`serviceAccount:` alone for the default account, as fabric) |

These are all of fabric's declared outputs.

## Differences from the module

- `labels` and `tags` are every chart's values too: they label every
  object in Kubernetes, and a map of `tags` adds cloud labels on the nodes.
- `spot` is rendered only when true (and not preemptible); fabric sends
  `false` otherwise, which is the API's default.

## From Terraform

A `module "x" { source = ".../modules/gke-nodepool" ... }` block's
arguments become the values unchanged, except refused fields
(`examples/gke-nodepool/`). To adopt an existing node pool, keep its name:
Config Connector acquires the pool of that name on the cluster
(`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/gke-nodepool`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gke-nodepool)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=gke-nodepool`: render cases `basic`, `full` (every field
the chart carries), `windows`, `names` and `mock`, each validated against
Config Connector v1.160.0's CRD schemas, and the refusals in
`tests/*.fail.yaml`.

Applied to the fake cloud on 2026-11-12 on an offload VM (`task test-mock
MOCK_CHARTS=gke-nodepool`): `tests/mock.values.yaml`, a node pool with a
created service account on the cluster in `tests/mock.needs.yaml`: both
objects Ready, the outputs evaluated, both deleted. Live, `task
test-live-gke` adds a pool of one Spot `e2-small` node to its Standard
cluster with this chart, waits for it, deletes it and checks it is gone.
On 2026-11-12 (offload VM as `cce-live-tests`) the pool was Ready in 53s,
the outputs evaluated, and after its delete Google Cloud no longer had it.
Two earlier runs, with the cluster referenced by its full id, left the pool
in Google Cloud after the object was deleted (Config Connector logged
"underlying resource does not exist; no API call necessary"); the chart
references the cluster by name since.

## Changes

- **0.1.0** (2026-11-12): the port: the node pool and its optional service
  account.
