# gke-cluster-autopilot

A GKE Autopilot cluster with fabric's defaults, its upgrade notifications
topic, and Backup for GKE channels and plans, as Config Connector and
config-connector-extensions objects. A port of Cloud Foundation Fabric's
[`modules/gke-cluster-autopilot`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/gke-cluster-autopilot)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-gke-cluster-autopilot` (`package.yaml`). Checked against Config
Connector v1.160.0 and config-connector-extensions at `f3d17dda`.

The module was `blocked` in the coverage (`docs/coverage`): Config
Connector has the four Backup for GKE kinds only as `v1alpha1`.
config-connector-extensions provides `GKEBackupBackupChannel`,
`GKEBackupBackupPlan`, `GKEBackupRestoreChannel` and `GKEBackupRestorePlan`
as `gkebackup.gcp.hfl.dev/v1beta1`, so the chart renders them with no
`allow_alpha` (`docs/design.md`, "Alpha kinds"; the CRDs are copied in
`crds/config-connector-extensions`).

This is fabric's module, not terraform-google-modules' (the `gke-cluster`
chart ports that one, and its Autopilot twin). GKE manages an Autopilot
cluster's nodes: there are no node pools or autoscaling settings.

## Example

```yaml
project_id: my-project
name: cluster-1
location: europe-west1-b
vpc_config:
  network: projects/my-project/global/networks/vpc
  subnetwork: projects/my-project/regions/europe-west1/subnetworks/gke
  secondary_range_names: {pods: pods, services: services}
access_config:
  ip_access: {authorized_ranges: {internal-vms: 10.0.0.0/8}}
  master_ipv4_cidr_block: 192.168.0.0/28
```

renders a private Autopilot `ContainerCluster` `cluster-1` on the REGULAR
release channel, with cost management, managed Prometheus, system and
workload logs and the daily maintenance window at 03:00, fabric's defaults
(`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults (fabric's
`optional()` defaults are applied by the chart, so an unset field renders
what fabric would).

| Variable | Renders |
| --- | --- |
| `names.cluster`, `names.topic` | not fabric variables: the cluster's and the notifications topic's names in full, used as given (no `namePrefix`) and checked (40 characters and a leading letter for the cluster) |
| `namePrefix` | not a fabric variable: an optional convenience in front of every derived name; empty changes nothing |
| `labels` | fabric's `labels`, the cluster's resource labels: Kubernetes labels on every object, unprefixed ones also Google Cloud labels |
| `tags` | not a fabric variable: cloud labels on every resource that takes them |
| `project_id`, `name`, `location`, `description`, `node_locations`, `min_master_version`, `issue_client_certificate` | the cluster's fields of those names |
| `release_channel` | the release channel, `REGULAR` unless set (Autopilot needs one) |
| `vpc_config` | network and subnetwork, secondary ranges (blocks or names), stack type, additional pod ranges, default SNAT, L4 LB firewall reconciliation |
| `access_config` | the DNS and IP endpoints, authorized ranges and Google public CIDRs, private nodes and endpoint, the master range, the private endpoint subnetwork and global access |
| `node_config` | the auto-provisioned nodes' service account and boot disk key (`clusterAutoscaling.autoProvisioningDefaults`), network tags and resource manager tags (`nodePoolAutoConfig`) |
| `enable_addons` | Cloud Run, Config Connector and KALM; HTTP load balancing and HPA are always on, as Autopilot needs them (`istio` is accepted and, as in fabric, renders nothing) |
| `enable_features` | NET_ADMIN, binary authorization, beta APIs, Cilium, cost management, DNS, multi-networking, database encryption, FQDN network policy, Gateway API, Google groups for RBAC, identity service, L4 ILB subsetting, mesh certificates, pod security policy, security posture, resource usage export, service external IPs, TPU, upgrade notifications (with their topic), VPA |
| `logging_config`, `monitoring_config` | system and workload logs always, and the control plane's on request; system metrics always, and the others on request, managed Prometheus, advanced datapath metrics; fabric's validation |
| `maintenance_config` | the daily or recurring window and the exclusions |
| `backup_configs` | the backup agent; backup and restore channels; with the agent, backup plans (schedule, retention, key, namespaces or applications) and restore plans (scopes, conflict policy, restore order, transformation rules, volume data policies). A channel's or plan's `deletion_policy: ABANDON` keeps it |
| `deletion_protection` | accepted, no effect (below) |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the cluster and every backup resource |

**Refused**, with a message naming the gap:

- `context`: by design.
- `fleet_project`: `ContainerCluster` has no fleet.
- When set or true: `enable_addons.agent_sandbox`;
  `enable_features.anonymous_authentication`,
  `dns.additive_vpc_scope_dns_domain`, `managed_opentelemetry`,
  `rbac_binding_config`, `secret_manager_config`, `secret_sync_config`;
  `access_config.dns_access.enable_k8s_certs` and
  `ip_access.private_endpoint_authorized_ranges_enforcement`;
  `node_config.kubelet_readonly_port_enabled`;
  `monitoring_config.advanced_datapath_observability.enable_relay`; a
  channel's `deletion_policy: PREVENT`. `ContainerCluster` (or the backup
  kinds) has no field for any of them.
- `deletion_protection` is accepted and does nothing: it is Terraform's
  own guard, and Config Connector has none. `deletion_policy: ABANDON`
  keeps the cluster.

## Outputs

`name`, `id`, `location`, `endpoint`, `dns_endpoint`, `ca_certificate`,
`master_version`, `self_link`, `notifications` (the topic's ID when the
chart makes it), `workload_identity_pool`, and the `backup_channel_ids`,
`restore_channel_ids`, `backup_plan_ids` and `restore_plan_ids` maps.
Not an output: `cluster`, the whole Terraform object.

## From Terraform

A `module "x" { source = ".../modules/gke-cluster-autopilot" ... }` block's
arguments become the values unchanged (`examples/gke-cluster-autopilot/`).
To adopt an existing cluster, keep its name and location and set
`deletion_policy: ABANDON` for the first apply (`docs/design.md`, "From
Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/gke-cluster-autopilot`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gke-cluster-autopilot)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=gke-cluster-autopilot`: render cases `basic`, `full`,
`names` and `mock`, each validated against Config Connector v1.160.0's and
config-connector-extensions' CRD schemas, and the refusals in
`tests/*.fail.yaml`.

The fake-cloud case (`tests/mock.values.yaml`) applies a regional
Autopilot cluster, with fabric's defaults, on a network and subnet that
`tests/mock.needs.yaml` makes; on 2026-11-12 it was Ready, its outputs
evaluated, and deleted. The Backup for GKE kinds are render-tested
only: the fake cloud's pin (`CCE_COMMIT`) predates them. Not applied live:
a cluster is more than the tiny resources the live tests make
(`task test-live-gke` covers the `gke-cluster` chart's).

## Changes

- **0.1.0** (2026-11-12): the port.
