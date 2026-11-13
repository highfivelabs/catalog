# net-lb-int

An internal passthrough Network Load Balancer, as Config Connector objects:
a regional backend service, its forwarding rules, an optional health check,
optional unmanaged instance groups and Private Service Connect service
attachments. A port of Cloud Foundation Fabric's
[`modules/net-lb-int`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/net-lb-int)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-net-lb-int` (`package.yaml`). Checked against Config Connector
v1.160.0.

## Example

```yaml
project_id: my-project
region: europe-west1
name: ilb-test
vpc_config:
  network: projects/my-project/global/networks/my-network
  subnetwork: projects/my-project/regions/europe-west1/subnetworks/gce
backends:
  - group: projects/my-project/zones/europe-west1-b/instanceGroups/my-ig
```

renders the `ComputeBackendService`, `ComputeForwardingRule` and
`ComputeHealthCheck` `ilb-test` (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.backendService`, `names.healthCheck` | not fabric variables: the backend service's and the health check's names in full, used as given (no `namePrefix`) and checked (63 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every name the chart derives or is given in an entry starts with `<namePrefix>-`; empty changes nothing |
| `labels` | fabric's `labels`: Kubernetes labels on every object; unprefixed ones reach the forwarding rules as Google Cloud labels |
| `tags` | cloud labels on every resource that takes them (the forwarding rules) |
| `name`, `project_id`, `region` | the names (`<name>`, `<name>-<key>`), the project annotation and the region of every object |
| `vpc_config` | `networkRef` of the backend service and the forwarding rules, `subnetworkRef` of the forwarding rules |
| `backend_service_config` | the `ComputeBackendService`: name, description, protocol, connection draining, session affinity, timeout, connection tracking, failover policy, logging (`enable`, `sample_rate`), subsetting. Refused: `network_pass_through_lb_traffic_policy` and `log_config`'s `optional_mode` and `optional_fields` (no such fields) |
| `backends` | the backend service's `backend` entries (`CONNECTION` balancing); a `group` that is a key of `group_configs` refers to the chart's group, any other is an instance group's id or self link |
| `forwarding_rules_config` | one `ComputeForwardingRule` per key (`INTERNAL`): address (an IP, else an address reference), IP version when no address, protocol, ports or all ports, global access |
| `group_configs` | one unmanaged `ComputeInstanceGroup` per key, with its instances and named ports |
| `health_check`, `health_check_config` | an existing health check, or the `ComputeHealthCheck` the chart makes (global, or regional with `is_regional`), with one of its six check types; fabric's one-type check. Helm merges a values file's `health_check_config` into the default (`tcp` on the serving port) where Terraform replaces it, so a type set beside the untouched default drops the default, and a `tcp` check that sets its own `port` or `port_name` drops the default's `port_specification` (the API refuses a port with `USE_SERVING_PORT`) |
| `service_attachments` | one `ComputeServiceAttachment` per key that is a forwarding rule's, named as the forwarding rule fabric derives, with `description`. Refused: `domain_name` and `reconcile_connections` (no such fields) |
| `service_label` | the forwarding rules' `serviceLabel` |
| `description` | the service attachments' description, as in fabric |
| `context` | refused: Bundt expressions (`${...}`) and `valueFrom` replace fabric's `$context` lookups |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the cloud resources |

fabric's `iap { enabled = false }` is the API's default for an internal
backend service and has no Config Connector field to render.

## Outputs

`backend_service_id`, `backend_service_self_link`,
`forwarding_rule_self_links`, `id` (the forwarding rules' ids),
`group_self_links`, `health_check_id`, `health_check_self_link` (null
with an existing health check) and `service_attachment_ids`. Not outputs:
`forwarding_rule_addresses`, since `ComputeForwardingRule` reports no
allocated address (a field gap), and fabric's whole objects
(`backend_service`, `forwarding_rules`, `groups`, `health_check`;
`docs/design.md`, "Outputs").

## From Terraform

A `module "x" { source = ".../modules/net-lb-int" ... }` block's arguments
become the values unchanged (`examples/net-lb-int/`). To adopt an existing
load balancer, keep its names: Config Connector acquires the resources of
those names (`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/net-lb-int`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-lb-int)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=net-lb-int`: render cases `basic`, `full`, `external-hc`
and `names`, each validated against Config Connector v1.160.0's CRD
schemas, and the refusals in `tests/*.fail.yaml`.

Fake cloud (`task test-mock MOCK_CHARTS=net-lb-int`, 2026-11-12): an empty
group the chart makes, the default health check, a forwarding rule on port
80 and its PSC service attachment, on a network and subnets from
`tests/mock.needs.yaml`: every object Ready, the outputs evaluated, every
object deleted.

Applied live on 2026-11-12 (`task test-live LIVE_CHARTS=net-lb-int`,
offload VM as `catalog-live-tests`): the same objects with an HTTP health
check and no global access, on a network and subnets made for the run:
all Ready, the outputs evaluated, deleted, and gone from Google Cloud.

## Changes

- **0.1.1** (2026-11-12): a `tcp` health check with its own `port` no
  longer keeps the default's `port_specification: USE_SERVING_PORT`, which
  Helm merged in and the API refuses (found by net-lb-ext's live run).
- **0.1.0** (2026-11-12): the port.
