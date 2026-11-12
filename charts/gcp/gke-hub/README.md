# gke-hub

A GKE fleet: cluster memberships, fleet features and their per-cluster
configuration (Config Sync, Policy Controller, service mesh), as Config
Connector objects. A port of Cloud Foundation Fabric's
[`modules/gke-hub`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/gke-hub)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-gke-hub` (`package.yaml`). Checked against Config Connector v1.160.0.

## Example

```yaml
project_id: my-project
location: europe-west1
clusters:
  cluster-1:
    id: projects/my-project/locations/europe-west1/clusters/cluster-1
    configmanagement: default
features:
  configmanagement: true
configmanagement_templates:
  default:
    config_sync:
      git: {sync_repo: https://github.com/example/configsync, policy_dir: configsync}
```

renders a `GKEHubMembership` `cluster-1`, the `GKEHubFeature`
`configmanagement` and a `GKEHubFeatureMembership` syncing the cluster from
the repository (`tests/golden/basic.yaml`; `tests/golden/full.yaml` has every
feature).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.<cluster key>` | not fabric variables: a cluster's membership ID in full, used as given (no `namePrefix`) and checked (63 characters, a leading letter); a key that is not a cluster is refused (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the membership IDs start with `<namePrefix>-`; features are named by the API; empty changes nothing |
| `labels`, `tags` | Kubernetes labels on every object; these kinds take no Google Cloud labels |
| `project_id` | the project of every object |
| `location` | the memberships' location (`global` when null, as Terraform's default) |
| `clusters` | a `GKEHubMembership` per key, its ID the key, its endpoint the cluster `//container.googleapis.com/<id>`; `workload_identity` sets the authority issuer `https://container.googleapis.com/v1/<id>` |
| `features` | a global `GKEHubFeature` per feature that is set (not false, null or empty); `multiclusteringress` names the config cluster, whose membership it references (a key that is not a cluster is refused) |
| `configmanagement_templates` | a `GKEHubFeatureMembership` per cluster naming a template, when `features.configmanagement` is true: version, Config Sync from git (`gcp_service_account_email` as `gcpServiceAccountRef`, the rest one to one; `secret_type` `none` and `source_format` `hierarchy` unless set, as fabric's defaults) and the hierarchy controller. `policy_controller` must be null, as fabric's check says |
| `policycontroller_templates` | a `GKEHubFeatureMembership` per cluster naming a template, when `features.policycontroller` is true: version and the hub config (audit interval, violation limit, exemptable namespaces, install spec, log denies, mutation, referential rules, monitoring, the template library, and `deployment_configs` per component `admission`, `audit` or `mutation`) |
| `servicemesh_templates` | a `GKEHubFeatureMembership` per cluster naming a template, when `features.servicemesh` is true: `mesh.management` (`MANAGEMENT_AUTOMATIC` unless set) |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the memberships, features and feature memberships |

Refused:

| Variable | Why |
| --- | --- |
| `fleet_default_member_config` | `GKEHubFeature` has no `fleetDefaultMemberConfig`: a feature's defaults for new members cannot be set (gap) |
| `policycontroller_templates[].policy_controller_hub_config.policy_content.bundles` (in part) | `GKEHubFeatureMembership`'s `policyContent` has no `bundles` (gap) |

## Outputs

| Output | Value |
| --- | --- |
| `cluster_ids` | each cluster key's membership ID, `projects/<project>/locations/<location>/memberships/<id>`, from the inputs |

## From Terraform

A `module "x" { source = ".../modules/gke-hub" ... }` block's arguments
become the values unchanged (`examples/gke-hub/`). To adopt existing
memberships and features, keep their names: Config Connector acquires the
memberships and features of those names (`docs/design.md`, "From
Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/gke-hub`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gke-hub)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=gke-hub`: render cases `basic`, `full`, `names` and `mock`,
each validated against Config Connector v1.160.0's CRD schemas, and the
refusals in `tests/*.fail.yaml`.

Fake cloud, `task test-mock MOCK_CHARTS=gke-hub`, 2026-11-12, with a
membership, two features and a service-mesh feature membership: all four
Ready, the `cluster_ids` output evaluated; the membership and the features
deleted, the feature membership never. Deleted together, as Bundt prunes a
component, the membership goes first, and Config Connector then cannot
delete the feature membership ("reference GKEHubMembership ... is not
found"), which keeps its finalizer. Until Config Connector deletes a child
whose parent is gone, remove a cluster's template names (or the cluster)
and apply before deleting the component. `tests/mock.values.yaml` holds
the membership and the features, which pass. Not applied live: a membership needs a running cluster, and the features
need their own APIs (Anthos Config Management, Service Mesh, Multi Cluster
Service Discovery), which the live-test project does not enable; the
live-test service account `task test-live` runs as has no GKE Hub role.

## Changes

- **0.1.0** (2026-11-12): the port.
