# net-lb-proxy-int-cross-region

A cross-region internal proxy Network Load Balancer (an L4 TCP proxy
ILB): one global forwarding rule in each region's subnet, a TCP proxy, a
global backend service, a health check, and optional unmanaged instance
groups and network endpoint groups (zonal, hybrid with their endpoints,
or Private Service Connect), as Config Connector objects. A port of Cloud
Foundation Fabric's
[`modules/net-lb-proxy-int-cross-region`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/net-lb-proxy-int-cross-region)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-net-lb-proxy-int-cross-region` (`package.yaml`). Checked against
Config Connector v1.160.0 (`ComputeForwardingRule`,
`ComputeTargetTCPProxy`, `ComputeBackendService`, `ComputeHealthCheck`,
`ComputeInstanceGroup`, `ComputeNetworkEndpointGroup`,
`ComputeRegionNetworkEndpointGroup`) and config-connector-extensions'
`ComputeNetworkEndpoint` (`compute.gcp.hfl.dev/v1beta1`; Config
Connector's own is `v1alpha1`) at `11baa460`.

Cross-region internal proxy load balancers need a proxy-only subnet with
purpose `GLOBAL_MANAGED_PROXY` in each region (net-vpc's
`subnets_proxy_only` with `global: true`); the chart does not make them.

## Example

```yaml
name: ilb-proxy-test
project_id: my-project
vpc_config:
  network: projects/my-project/global/networks/my-vpc
  subnetworks:
    europe-west1: projects/my-project/regions/europe-west1/subnetworks/my-subnet-1
    europe-west4: projects/my-project/regions/europe-west4/subnetworks/my-subnet-2
neg_configs:
  neg-a:
    gce:
      zone: europe-west1-b
      network: projects/my-project/global/networks/my-vpc
      subnetwork: projects/my-project/regions/europe-west1/subnetworks/my-subnet-1
      endpoints:
        vm-a: {instance: my-vm-a, ip_address: 10.0.0.2, port: 80}
backend_service_config:
  backends:
    - {group: neg-a, max_connections: {per_endpoint: 100}}
```

renders the forwarding rules `ilb-proxy-test-europe-west1` and
`-europe-west4`, the target TCP proxy, backend service and TCP health
check `ilb-proxy-test`, the zonal NEG `ilb-proxy-test-neg-a` and its
endpoint (`tests/golden/basic.yaml` has both NEGs of fabric's example).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.backendService`, `names.healthCheck` and `names.targetProxy` set those cloud names in full |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every name the chart derives or is given in an entry starts with `<namePrefix>-`; empty changes nothing |
| `labels` | fabric's labels: Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label on the forwarding rules (the only resources here with labels) |
| `tags` | not a fabric variable: cloud labels on the forwarding rules |
| `name` | the base of every derived name |
| `project_id` | every object's project, unless an entry sets its own |
| `vpc_config` | `network`, and one global `ComputeForwardingRule` per `subnetworks` key, named `<name>-<key>`, in that subnet |
| `addresses` | a forwarding rule's address, by subnetwork key: an IP, or an address's ID or self link |
| `port` | the forwarding rules' `portRange` |
| `description` | the forwarding rules' description |
| `target_proxy_config` | the `ComputeTargetTCPProxy`'s name, description and `proxyHeader` |
| `backend_service_config` | the global `ComputeBackendService` (`INTERNAL_MANAGED`, `TCP`): name, description, cookie TTL, draining timeout, port name, session affinity (`NONE` or `CLIENT_IP`), timeout, logging, and the backends. A backend's `group` is the key of one of the chart's groups or NEGs, or an existing group's ID or self link (an instance group when it holds `/instanceGroups/`, else a NEG); balancing mode, capacity scaler, description, `max_connections` per group, endpoint or instance, max utilization. `log_config.optional_mode` and `optional_fields` are refused (below). `health_checks` and `project_id` are accepted and unused, as in fabric |
| `health_check`, `health_check_config` | an existing health check, or a global `ComputeHealthCheck` of one type (gRPC, HTTP, HTTP/2, HTTPS, TCP, SSL), TCP on the serving port by default; `project_id` is unused, as in fabric |
| `group_configs` | one unmanaged `ComputeInstanceGroup` per key, named `<name>-<key>` unless it has a name, in its own project if it sets one |
| `neg_configs` | per key, one of: `gce`, a zonal `ComputeNetworkEndpointGroup` of type `GCE_VM_IP_PORT` with one `ComputeNetworkEndpoint` per endpoint; `hybrid`, the same of type `NON_GCP_PRIVATE_IP_PORT`; `psc`, a `ComputeRegionNetworkEndpointGroup` to a PSC target service. Named `<name>-<key>`, in the entry's project if it sets one |
| `context` | refused: Bundt expressions (`${...}`) and `valueFrom` replace fabric's `$context` lookups |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps every resource |

Refused, by name: `backend_service_config.log_config.optional_mode` and
`optional_fields` (`ComputeBackendService`'s `logConfig` has neither). fabric's
validations are kept: one health check type, one NEG type per entry, the
session affinity and the balancing modes. Name lengths: with a
`namePrefix`, a derived name over 63 characters stops the render; a name set under
`names` is always checked.

## Outputs

| Output | From |
| --- | --- |
| `addresses` | the address given for each subnetwork key, else null: `ComputeForwardingRule` reports no allocated address (a field gap) |
| `backend_service_id` | `projects/<project>/global/backendServices/<name>` |
| `backend_service_self_link` | the backend service's `status.selfLink` |
| `group_self_links` | each group's `status.selfLink`, by key |
| `health_check_id`, `health_check_self_link` | the auto-created health check's, else null |
| `ids` | `projects/<project>/global/forwardingRules/<name>`, by subnetwork key |
| `neg_ids` | `projects/<project>/zones/<zone>/networkEndpointGroups/<name>`, by key |
| `psc_neg_ids` | `projects/<project>/regions/<region>/networkEndpointGroups/<name>`, by key |
| `target_proxy_id` | `projects/<project>/global/targetTcpProxies/<name>` |

Not outputs: fabric's whole objects (`backend_service`, `forwarding_rules`,
`groups`, `health_check`, `target_proxy`; `docs/design.md`, "Outputs").

## Differences from the module

- **A NEG without a network.** fabric leaves a `gce` or `hybrid` NEG's
  `network` null and the API takes the project's `default` network;
  `ComputeNetworkEndpointGroup` requires one, so the chart names
  `projects/<project>/global/networks/default`, the same network.
- **A PSC NEG as a backend** is referenced by its ID, since a backend's
  NEG reference by name is to a zonal group; Config Connector retries
  the backend service until the group exists.
- **Instance groups and NEGs together.** The API refuses a backend
  service whose backends mix instance groups and network endpoint groups
  (400 on `backends[].group`, seen live); fabric does not check it, and
  neither does the chart, so the plan shows it and the apply fails.
- **Duplicate backends.** fabric keys backends by group, and Terraform
  stops on a duplicate; the chart keeps the first.

## From Terraform

A `module "x" { source = ".../modules/net-lb-proxy-int-cross-region" ... }`
block's arguments become the values unchanged, apart from `context`
(refused: write the values the lookups stand for). Every resource keeps
its name, so it adopts what Terraform made (`docs/design.md`, "From
Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/net-lb-proxy-int-cross-region`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-lb-proxy-int-cross-region)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml)
records the repository, path, release, commit, licence and the date last
synced, and the module is listed in
[`upstream/modules.yaml`](../../../upstream/modules.yaml). To take a newer
release, see [`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=net-lb-proxy-int-cross-region`: render cases `basic`
(fabric's README "Minimal Example"), `health-check` ("Health Checks"),
`zonal-neg` ("Zonal NEG creation"), `hybrid-neg` ("Hybrid NEG
creation"), `full` (every variable), `names` and `mock`, each validated
against Config Connector v1.160.0's CRD schemas and
config-connector-extensions' CRDs, and the refusals in
`tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`, with the network
and two regions' subnets from `tests/mock.needs.yaml`): forwarding rules
in `us-central1` and `us-east1`, a hybrid NEG with one endpoint as the
backend and an instance group beside it. On 2026-11-12 (offload VM
`off-catalog-1113014808-28374`, config-connector-extensions `11baa460`)
all eight objects became Ready, the outputs evaluated (`addresses` null:
none was given) and all eight were deleted. mockgcp also accepts a
backend service with both the group and the NEG as backends, which the
API refuses (the first live run); the case no longer does that. The PSC
NEG is only render-tested.

Live (`task test-live LIVE_CHARTS=net-lb-proxy-int-cross-region`, as
catalog-live-tests, which has `roles/compute.networkAdmin`): forwarding
rules in `us-central1` and `us-east1` beside `GLOBAL_MANAGED_PROXY`
subnets, a zonal NEG as the backend and an instance group, with the
network and subnets made by the case. On 2026-11-12 (run
`cat-11130151-bd86`, offload VM `off-catalog-1113014807-5659`) all seven
objects of the chart became Ready, the outputs evaluated, everything was
deleted and gone from Google Cloud, and nothing was left in the project.
The first run (`cat-11130131-7401`) had both the group and the NEG as
backends: the API answered 400 on `backends[1].group`, and the case was
changed. No endpoint is applied live: the harness runs Config Connector's
controllers, not config-connector-extensions' (`ComputeNetworkEndpoint`
passes on the fake cloud).

Rerun 2026-11-13 (run `cat-11132355-cc50`, offload VM
`off-catalog-1113235106-1058`, as cce-live-tests, config-connector-extensions `c2f0c7d2`): passed again,
every object Ready, deleted and gone.

## Changes

- **0.1.0** (2026-11-12): the port.
