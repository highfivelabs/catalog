# net-lb-ext

An external passthrough Network Load Balancer, as Config Connector objects:
a regional backend service, its forwarding rules, an optional regional
health check and optional unmanaged instance groups. A port of Cloud Foundation Fabric's
[`modules/net-lb-ext`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/net-lb-ext)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-net-lb-ext` (`package.yaml`). Checked against Config Connector
v1.160.0.

## Example

```yaml
project_id: my-project
region: europe-west1
name: nlb-test
backends:
  - group: projects/my-project/zones/europe-west1-b/instanceGroups/my-ig
```

renders the `ComputeBackendService`, `ComputeForwardingRule` and
`ComputeHealthCheck` `nlb-test` (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.backendService`, `names.healthCheck` | not fabric variables: the backend service's and the health check's names in full, used as given (no `namePrefix`) and checked (63 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every name the chart derives or is given in an entry starts with `<namePrefix>-`; empty changes nothing |
| `labels` | fabric's `labels`: Kubernetes labels on every object; unprefixed ones reach the forwarding rules as Google Cloud labels |
| `tags` | cloud labels on every resource that takes them (the forwarding rules) |
| `name`, `project_id`, `region` | the names (`<name>`, `<name>-<key>`), the project annotation and the region of every object |
| `backend_service_config` | the `ComputeBackendService` (`EXTERNAL`): name, description, protocol, connection draining, locality policy, port name, security policy, session affinity, timeout, connection tracking, failover policy, logging (`enable`, `sample_rate`). Refused: `log_config`'s `optional_mode` and `optional_fields` (no such fields) |
| `backends` | the backend service's `backend` entries (`CONNECTION` balancing); a `group` is an instance group's id or self link, as in fabric; a key of `group_configs` also refers to the chart's group (fabric's callers pass its `group_self_links` output, which one component cannot read of itself) |
| `forwarding_rules_config` | one `ComputeForwardingRule` per key (`EXTERNAL`): address (an IP, else an address reference), IP version when no address, protocol, ports or all ports, subnetwork |
| `group_configs` | one unmanaged `ComputeInstanceGroup` per key, with its instances and named ports |
| `health_check`, `health_check_config` | an existing health check, or the regional `ComputeHealthCheck` the chart makes, with one of its six check types; fabric's one-type check. Helm merges a values file's `health_check_config` into the default (`tcp` on the serving port) where Terraform replaces it, so a type set beside the untouched default drops the default |
| `context` | refused: Bundt expressions (`${...}`) and `valueFrom` replace fabric's `$context` lookups |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the cloud resources |

## Outputs

`backend_service_id`, `backend_service_self_link`,
`forwarding_rule_addresses`, `forwarding_rule_self_links`, `id` (the
forwarding rules' ids), `group_self_links`, `health_check_id`,
and `health_check_self_link` (null with an existing health check). Not outputs: fabric's whole objects
(`backend_service`, `forwarding_rules`, `groups`, `health_check`;
`docs/design.md`, "Outputs").

## From Terraform

A `module "x" { source = ".../modules/net-lb-ext" ... }` block's arguments
become the values unchanged (`examples/net-lb-ext/`). To adopt an existing
load balancer, keep its names: Config Connector acquires the resources of
those names (`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/net-lb-ext`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-lb-ext)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=net-lb-ext`: render cases `basic`, `full`, `external-hc`
and `names`, each validated against Config Connector v1.160.0's CRD
schemas, and the refusals in `tests/*.fail.yaml`.

Fake cloud (`task test-mock MOCK_CHARTS=net-lb-ext`, 2026-11-12): an empty
group the chart makes, the default health check and a forwarding rule on
port 80: every object Ready, the outputs evaluated, every object deleted.
mockgcp does not write the forwarding rule's allocated address back, so
`forwarding_rule_addresses` was null there.

## Changes

- **0.1.0** (2026-11-12): the port.
