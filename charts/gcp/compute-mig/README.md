# compute-mig

A managed instance group, zonal or regional, with one or more versions, an
optional health check and autoscaler, stateful disks and per-instance
configs, as Config Connector objects. A port of Cloud Foundation Fabric's
[`modules/compute-mig`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/compute-mig)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-compute-mig` (`package.yaml`). Checked against Config Connector
v1.160.0 (`ComputeInstanceGroupManager`, `ComputeHealthCheck`) and
config-connector-extensions' `ComputeAutoscaler`, `ComputeRegionAutoscaler`,
`ComputePerInstanceConfig` and `ComputeRegionPerInstanceConfig`
(`compute.gcp.hfl.dev/v1beta1`) at `35833eb`; Config Connector's own are
`v1alpha1`, and its regional autoscaler has no controller.

## Example

```yaml
project_id: my-project
location: europe-west8-b
name: mig-test
target_size: 2
instance_template: projects/my-project/global/instanceTemplates/nginx-template
```

renders the zonal `ComputeInstanceGroupManager` `mig-test`, two instances of
`nginx-template` (`tests/golden/simple.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.group`, `names.healthCheck`, `names.autoscaler` | not fabric variables: the group's (and its instances' base name), the health check's and the autoscaler's names in full, used as given (no `namePrefix`) and checked (63 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the group, health check and autoscaler are `<namePrefix>-<name>` and each `stateful_config` instance `<namePrefix>-<key>`; empty changes nothing |
| `labels` | not a fabric variable: Kubernetes labels on every object; none of the module's resources takes Google Cloud labels |
| `tags` | not a fabric variable: Google Cloud labels on every resource that takes them (none of these) |
| `project_id` | every object's project annotation and `projectRef` |
| `location` | a zone makes a zonal group (`ComputeAutoscaler`, `ComputePerInstanceConfig`), a region a regional one (`ComputeRegionAutoscaler`, `ComputeRegionPerInstanceConfig`), told apart as fabric's `local.is_regional` does; the group's `location` |
| `name` | the group's `resourceID` and `baseInstanceName`, the health check's and the autoscaler's `resourceID` |
| `description` | the group's and the autoscaler's `description` |
| `instance_template`, `default_version_name` | the first of the group's `versions`: `name` and `instanceTemplateRef.external` |
| `versions` | one more of `versions` each, in key order, with `targetSize.fixed` or `percent` |
| `target_size` | `targetSize`; null takes `autoscaler_config.min_replicas`, and is refused without an autoscaler, as is 0 ("The target size", below) |
| `target_pools` | `targetPools[].external` |
| `named_ports` | `namedPorts`, in name order |
| `auto_healing_policies` | `autoHealingPolicies[0]`: `initialDelaySec`, and `healthCheckRef`: `health_check` as `external`, else the chart's health check by name when `health_check_config` is set |
| `health_check_config` | a global `ComputeHealthCheck`: the intervals and thresholds, one of the six check types (fabric's validation: at most one), `logConfig.enable` with `enable_logging`; `description` "Terraform managed." when null, as fabric's default |
| `stateful_disks` | `statefulPolicy.preservedState.disks`: `autoDelete` `ON_PERMANENT_INSTANCE_DELETION` for true, `NEVER` for false |
| `update_policy` | `updatePolicy`: the actions, type, `maxSurge`, `maxUnavailable`, `minReadySec`, `mostDisruptiveAllowedAction`, `replacementMethod`; `regional_redistribution_type` as `instanceRedistributionType` on a regional group only, as fabric's zonal resource has no such field |
| `distribution_policy` | `distributionPolicy` (`targetShape`, `zones[].zone`) on a regional group only, as fabric's |
| `autoscaler_config` | a `ComputeAutoscaler` (zonal, `targetRef` the group by name) or `ComputeRegionAutoscaler` (regional, `target` the group's `projects/<project>/regions/<region>/instanceGroupManagers/<name>`): `minReplicas`, `maxReplicas`, `cooldownPeriod`, `mode`, `cpuUtilization` (`predictiveMethod` `OPTIMIZE_AVAILABILITY` with `optimize_availability`), `loadBalancingUtilization`, `metric`, `scaleInControl` and `scalingSchedules` (a schedule's `description`, a bool in fabric's type, as text) |
| `stateful_config` | a `ComputePerInstanceConfig` or `ComputeRegionPerInstanceConfig` each, the instance named after the key: the two actions, `removeInstanceStateOnDestroy`, `preservedState.metadata` and `disk` (`deleteRule` and `mode` from `delete_on_instance_deletion` and `read_only`, as fabric) |
| `all_instances_config`, `instance_lifecycle_policy`, `instance_flexibility_policy_selections`, `wait_for_instances` | refused when set (below) |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps every resource |

Refused (`upstream.yaml`):

- `all_instances_config`. `ComputeInstanceGroupManager` has no
  `allInstancesConfig` field: set the labels and metadata in the instance
  template.
- `instance_lifecycle_policy`. It has no `instanceLifecyclePolicy` field,
  so the group keeps the API's default repair behaviour.
- `instance_flexibility_policy_selections`. It has no
  `instanceFlexibilityPolicy` field (fabric's "Flexible MIGs" example,
  `tests/flexible.fail.yaml`).
- `wait_for_instances`. Terraform's wait for the group's instances is a
  client-side wait with no Config Connector field. Bundt waits for the group
  to be Ready, which is not a wait for its instances.
- `autoscaler_config.scaling_control.down` beside `scaling_control.in`
  (in part). Compute Engine v1, which the autoscaler kinds call, has one
  scale-in control; `down` (the beta API's `scaleDownControl`) is rendered
  as `scaleInControl` when `in` is not set (A3).

## The target size

Config Connector's `ComputeInstanceGroupManager` requires `targetSize`,
and Compute Engine requires a size when it inserts a group. fabric leaves
`target_size` null when an autoscaler sets the size, and Terraform then
creates the group at 0 and lets the autoscaler grow it. Config Connector
cannot do that: its controller for the kind (the declarative client
library) never sends a size of 0, so a group rendered with `targetSize: 0`
is refused by the API ("Required field 'resource.targetSize' not
specified", the first live run, `cat-11130713-23f6`). So:

- **`target_size` set** (not 0): rendered as given, as Terraform does.
- **`target_size` null with `autoscaler_config`**: `targetSize` is
  `autoscaler_config.min_replicas` (A1), the size the autoscaler gives a
  new group at once; no other number is taken.
- **`target_size` null without an autoscaler, or 0**: refused, naming the
  reason (`tests/no-size.fail.yaml`, `tests/zero-size.fail.yaml`). fabric's
  "Stateful MIGs - Instance Config" example is one such: it needs a
  `target_size` here (`tests/stateful.values.yaml` sets 1).

**Adopting a Terraform group.** Terraform's state records the group's
current `target_size` (the attribute is computed). Set `target_size` to it
for the first apply, so Config Connector does not resize the group; leaving
it null renders `min_replicas`, and Config Connector then resizes an
adopted group that its autoscaler holds above its minimum (A1).

## Outputs

| Output | Value |
| --- | --- |
| `id` | `projects/<project>/zones/<zone>/instanceGroupManagers/<name>`, or `.../regions/<region>/...` for a regional group, the provider's ID, from the group's spec |

fabric's `autoscaler`, `group_manager` and `health_check` are whole
Terraform objects, which a Package does not output (`docs/design.md`,
"Outputs").

## Differences from the module

- **The target size** (above): never 0, and `min_replicas` when null with an autoscaler.
- **The autoscaler writes the API's defaults** (A2): `mode` `ON`,
  `cooldownPeriod` 60, `cpuUtilization.predictiveMethod` `NONE`, and CPU at
  0.6 when no signal is set, where fabric leaves them null.
- **A stateful instance is made, not only configured.**
  config-connector-extensions' per-instance configs create the named
  instance with `createInstances`; Terraform's call
  `updatePerInstanceConfigs`. That grows the group by one, past its
  `targetSize`, and Config Connector's next reconcile of the group resizes
  it back. A regional group needs
  `update_policy.regional_redistribution_type: NONE` for it, as a stateful
  regional group has anyway.
- **The regional autoscaler takes the group's URL**, not a reference, as
  Config Connector's alpha type has it, so it does not wait for the group:
  it retries until the group exists.

## Assumptions

- **A1.** With an autoscaler, `min_replicas` is the right first size and
  Config Connector's later reconciles do not undo the autoscaler while the
  group stays at its minimum; once the autoscaler moves the size, a
  reconcile sets `targetSize` back to `min_replicas` (the library diffs and
  patches a non-zero size), which Compute Engine either refuses for an
  autoscaled group or applies until the autoscaler acts again. Not yet seen
  live: the live case holds the group at min = max = 1 (Tests).
- **A2.** The autoscaler's defaults are the API's (mode `ON`, a 60 s
  cool-down, predictive method `NONE`, CPU 0.6 with no other signal), as
  config-connector-extensions' `ComputeAutoscaler` and
  `ComputeRegionAutoscaler` docs list them; its controllers compare every
  field the API returns, so leaving them out would patch them on every
  reconcile.
- **A3.** fabric's `scaling_control.down` (the beta API's
  `scaleDownControl`) is the v1 API's `scaleInControl`: the zonal
  extension kind sends the one as the other, and the regional one has only
  `scaleInControl`.

## From Terraform

A `module "x" { source = ".../modules/compute-mig" ... }` block's arguments
become the values unchanged. To adopt an existing group, keep its name and
set `deletion_policy: ABANDON` for the first apply (`docs/design.md`, "From
Terraform"), and set `target_size` to the group's current size from the
Terraform state ("The target size").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/compute-mig`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/compute-mig)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=compute-mig`: render cases `simple`, `multiple`,
`health-check`, `autoscaling`, `policy`, `mig-config` and `stateful`
(fabric's README examples; "Flexible MIGs" is `tests/flexible.fail.yaml`),
`regional`, `full`, `names` and `mock`, each validated against Config
Connector v1.160.0's CRD schemas and config-connector-extensions' CRDs, and
the refusals in `tests/*.fail.yaml`.

Fake cloud: `task test-mock MOCK_CHARTS=compute-mig`: `tests/mock.values.yaml`,
a regional group with two versions, the health check, a regional
autoscaler and a stateful instance, on the template in
`tests/mock.needs.yaml`. 2026-11-13, offload VM `off-catalog-1113074635-5497`,
config-connector-extensions at `35833eb`: the group, health check,
autoscaler and per-instance config all Ready and deleted, and `id`
evaluated. (The fake cloud accepts a group with `targetSize: 0`, which
Compute Engine refuses: only the live run found that.)

Live: `hack/live-apply.sh` with `LIVE_CHARTS="compute-mig
compute-mig-stateful"`, as cce-live-tests (compute roles), with
config-connector-extensions' manager beside Config Connector's: a zonal
group of one e2-micro VM held by a `ComputeAutoscaler` (min and max 1, no
`target_size`) with the health check for auto-healing, and a zonal group of
`target_size` 1 with one `ComputePerInstanceConfig`; each group's size is
read after it is made and again after Config Connector reconciles it a
second time, and must be 1 VM (the named one, for the second). The first run
(2026-11-13, `cat-11130713-23f6`, offload VM
`off-catalog-1113070631-31189`), with a null `target_size` rendered as 0,
failed: Compute Engine refused both groups ("Required field
'resource.targetSize' not specified"), so the autoscaler and the
per-instance config never had a group; the network, subnet, template and
health check were made and deleted, and the sweep found nothing left. The
size rule above is the fix; its live rerun has not run yet (the laptop's
automation identity cannot act as cce-live-tests).

## Changes

- **0.1.0** (2026-11-13): the port.
