# net-lb-app-int-cross-region

A cross-region internal Application Load Balancer (an L7 HTTP or HTTPS
ILB): one global forwarding rule in each region's subnet, an HTTP or
HTTPS target proxy, a URL map, global backend services and health
checks, optional unmanaged instance groups, network endpoint groups
(zonal, hybrid with their endpoints, serverless, Private Service Connect)
and PSC service attachments, as Config Connector objects. A port of Cloud
Foundation Fabric's
[`modules/net-lb-app-int-cross-region`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/net-lb-app-int-cross-region)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-net-lb-app-int-cross-region` (`package.yaml`). Checked against
Config Connector v1.160.0 (`ComputeForwardingRule`,
`ComputeTargetHTTPProxy`, `ComputeTargetHTTPSProxy`, `ComputeURLMap`,
`ComputeBackendService`, `ComputeHealthCheck`, `ComputeInstanceGroup`,
`ComputeNetworkEndpointGroup`, `ComputeRegionNetworkEndpointGroup`,
`ComputeServiceAttachment`) and config-connector-extensions'
`ComputeNetworkEndpoint` (`compute.gcp.hfl.dev/v1beta1`; Config
Connector's own is `v1alpha1`) at `11baa460`.

Cross-region internal application load balancers need a proxy-only
subnet with purpose `GLOBAL_MANAGED_PROXY` in each region (net-vpc's
`subnets_proxy_only` with `global: true`); the chart does not make them.

## Example

```yaml
name: ilb-test
project_id: my-project
backend_service_configs:
  default:
    backends:
      - group: projects/my-project/zones/europe-west1-a/instanceGroups/my-ig-1-ew1
  video:
    backends:
      - group: projects/my-project/zones/europe-west1-a/instanceGroups/my-ig-2-ew1
urlmap_config:
  default_service: default
  host_rules:
    - {hosts: ["*"], path_matcher: pathmap}
  path_matchers:
    pathmap:
      default_service: default
      path_rules:
        - {paths: [/video, /video/*], service: video}
vpc_config:
  network: projects/my-project/global/networks/my-vpc
  subnetworks:
    europe-west1: projects/my-project/regions/europe-west1/subnetworks/my-subnet-1
    europe-west4: projects/my-project/regions/europe-west4/subnetworks/my-subnet-2
```

renders the forwarding rules `ilb-test-europe-west1` and `-europe-west4`
(HTTP, port 80), the target HTTP proxy and URL map `ilb-test`, the
backend services `ilb-test-default` and `ilb-test-video`, and the HTTP
health check `ilb-test-default` that both use (`tests/golden/url-map.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.targetProxy` and `names.urlMap` set those cloud names in full |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every name the chart derives or is given in an entry starts with `<namePrefix>-`; empty changes nothing |
| `labels` | fabric's labels: Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label on the forwarding rules (the only resources here with labels) |
| `tags` | not a fabric variable: cloud labels on the forwarding rules |
| `name` | the base of every derived name, and the URL map's and proxy's name |
| `project_id` | every object's project, unless an entry sets its own |
| `vpc_config` | `network`, and one global `ComputeForwardingRule` per `subnetworks` key, named `<name>-<key>`, in that subnet |
| `addresses` | a forwarding rule's address, by subnetwork key: an IP, or an address's ID or self link |
| `protocol` | `HTTP` (a `ComputeTargetHTTPProxy`, the forwarding rules on `ports` or 80) or `HTTPS` (a `ComputeTargetHTTPSProxy`, on 443), and the backend services' protocol unless they set one |
| `ports` | the forwarding rules' port for HTTP, at most one |
| `description` | the forwarding rules' and NEGs' description |
| `http_proxy_config`, `https_proxy_config` | the proxy's name, description and keep-alive timeout; for HTTPS also Certificate Manager certificates, QUIC override, SSL policy and server TLS policy (by ID) |
| `urlmap_config` | the `ComputeURLMap`: description, default service, default redirect, default route action, header action, host rules, path matchers (default service, default redirect, path rules, route rules with their match rules), tests. Every route action field fabric has: CORS, fault injection, request mirroring, retries, timeout, URL rewrite (with path templates in route rules), weighted backend services with header actions. A service is the key of one of the chart's backend services, else an existing one's ID or self link; a test's service is taken as given, as fabric does. `null` (the default) is fabric's default, `{default_service: default}` |
| `backend_service_configs` | one global `ComputeBackendService` (`INTERNAL_MANAGED`) per key, named `<name>-<key>` unless it has a name, in its own project if it sets one: description, cookie TTL, draining timeout, health checks (keys of the chart's or existing IDs; `["default"]` unless set, `[]` for none), locality LB policy, logging, port name, protocol, session affinity, timeout, circuit breakers, consistent hash, IAP, outlier detection and the backends. A backend's `group` is the key of one of the chart's groups or NEGs, or an existing group's ID or self link (an instance group when it holds `/instanceGroups/`, else a NEG); balancing mode (`UTILIZATION` by default), capacity scaler, description, `max_rate` per group, endpoint or instance, max utilization. `failover` is accepted and unused, as in fabric. `log_config.optional_mode` and `optional_fields` are refused (below) |
| `health_check_configs` | one global `ComputeHealthCheck` per key, named `<name>-<key>` unless it has a name, in its own project if it sets one, of one type (gRPC, HTTP, HTTP/2, HTTPS, TCP, SSL). `null` (the default) is fabric's default, `{default: {http: {port_specification: USE_SERVING_PORT}}}`; `{}` makes none |
| `group_configs` | one unmanaged `ComputeInstanceGroup` per key, named `<name>-<key>` unless it has a name, in its own project if it sets one |
| `neg_configs` | per key, one of: `gce`, a zonal `ComputeNetworkEndpointGroup` of type `GCE_VM_IP_PORT` (network: the entry's or `vpc_config.network`; subnetwork: the entry's or the `vpc_config.subnetworks` entry of the zone's region) with one `ComputeNetworkEndpoint` per endpoint; `hybrid`, the same of type `NON_GCP_PRIVATE_IP_PORT`; `cloudrun`, a serverless `ComputeRegionNetworkEndpointGroup` to a Cloud Run service (and tag) or URL mask; `psc`, a `ComputeRegionNetworkEndpointGroup` to a PSC target service, in the chart's project as in fabric. Named `<name>-<key>` |
| `service_attachment` | one `ComputeServiceAttachment` per forwarding rule, in the region of its key, named as the rule: NAT subnets (by key), automatic or manual acceptance, accept and reject lists, description, proxy protocol. `domain_name` and `reconcile_connections` are refused (below) |
| `service_directory_registration` | refused (below) |
| `context` | refused: Bundt expressions (`${...}`) and `valueFrom` replace fabric's `$context` lookups |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps every resource |

Refused, by name:

- `backend_service_configs.<key>.log_config.optional_mode` and
  `optional_fields`: `ComputeBackendService`'s `logConfig` has neither.
- `service_attachment.domain_name` and `reconcile_connections`:
  `ComputeServiceAttachment` has neither field. Any value of
  `reconcile_connections` is refused, `false` too, since the chart could
  not send it.
- `service_directory_registration`: `ComputeForwardingRule`'s
  `serviceDirectoryRegistrations` takes a service only, not a namespace
  or region.

fabric's validations are kept: one health check type per entry, one NEG
type per entry, a Cloud Run NEG's target, at most one port, the
protocol, the locality LB policies, session affinities and balancing
modes, the port specifications. Name lengths: with a `namePrefix`, a
derived name over 63 characters stops the render; a name set under
`names` is always checked.

## Outputs

| Output | From |
| --- | --- |
| `addresses` | the address given for each subnetwork key, else null: `ComputeForwardingRule` reports no allocated address (a field gap) |
| `backend_service_generated_ids` | each backend service's `status.generatedId`, by key (null until reported) |
| `backend_service_ids` | `projects/<project>/global/backendServices/<name>`, by key |
| `backend_service_names` | each backend service's name, by key |
| `group_ids` | `projects/<project>/zones/<zone>/instanceGroups/<name>`, by key |
| `health_check_ids` | `projects/<project>/global/healthChecks/<name>`, by key |
| `ids` | `projects/<project>/global/forwardingRules/<name>`, by subnetwork key |
| `neg_ids` | `projects/<project>/zones/<zone>/networkEndpointGroups/<name>`, by key |
| `psc_neg_ids`, `regional_neg_ids` | `projects/<project>/regions/<region>/networkEndpointGroups/<name>`, by key, of the PSC and the serverless NEGs |
| `url_map_id` | `projects/<project>/global/urlMaps/<name>` |

Not an output: fabric's whole `forwarding_rules` (`docs/design.md`,
"Outputs").

## Differences from the module

- **Map and object defaults.** Helm merges a map or object given in the
  values into the chart's default, where Terraform replaces it, so
  `health_check_configs` and `urlmap_config` default to null, and the
  chart applies fabric's defaults when they are null. A values file that
  sets them gets exactly what it sets, as in Terraform.
- **Regional NEGs as backends** (serverless, PSC) are referenced by their
  ID, since a backend's NEG reference by name is to a zonal group;
  Config Connector retries the backend service until the group exists.
- **Route rules' service** is a URL in `ComputeURLMap` rather than a
  reference, so a backend service key becomes its ID,
  `projects/<project>/global/backendServices/<name>`.
- **CORS max age, keep-alive timeout and header range values** are
  strings in fabric and integers in Config Connector; the chart converts
  them.
- **A header match of type `present`** sends `presentMatch` only when it
  has a value (fabric passes the value, so without one the match has no
  type, as in fabric); the value `"true"` is true.
- **Instance groups and NEGs together.** The API refuses a backend
  service whose backends mix instance groups and network endpoint groups
  (seen live with net-lb-proxy-int-cross-region); fabric does not check
  it, and neither does the chart.
- **Duplicate backends.** fabric keys backends by group, and Terraform
  stops on a duplicate; the chart keeps the first.

## From Terraform

A `module "x" { source = ".../modules/net-lb-app-int-cross-region" ... }`
block's arguments become the values unchanged, apart from `context`
(refused: write the values the lookups stand for). Every resource keeps
its name, so it adopts what Terraform made (`docs/design.md`, "From
Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/net-lb-app-int-cross-region`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-lb-app-int-cross-region)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml)
records the repository, path, release, commit, licence and the date last
synced, and the module is listed in
[`upstream/modules.yaml`](../../../upstream/modules.yaml). To take a newer
release, see [`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=net-lb-app-int-cross-region`: render cases from fabric's
README, `basic` ("Minimal Example"), `https`, `cross-project`,
`health-check` and `health-check-external` ("Health Checks"), `groups`
("Instance Groups"), `zonal-neg`, `hybrid-neg`, `serverless-neg`,
`psc-neg`, `url-map`, `service-attachment` (without the two refused
fields), `mtls` and `complex`; and `full` (every variable the chart
carries, with every URL map block), `names` and `mock`. Each is validated
against Config Connector v1.160.0's CRD schemas and
config-connector-extensions' CRDs; the refusals are in
`tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`, with the network
and two regions' subnets from `tests/mock.needs.yaml`): forwarding rules
in `us-central1` and `us-east1`, the HTTP proxy, a URL map with a host
rule and a path matcher, three backend services (on a hybrid NEG with one
endpoint, on an instance group, on a serverless NEG) and two health
checks. On 2026-11-12 (offload VM `off-catalog-1113030459-25181`,
config-connector-extensions `11baa460`) all 13 objects became Ready, the
outputs evaluated (`addresses` null: none was given) and all 13 were
deleted. The HTTPS proxy, the PSC NEG and the service attachments are
only render-tested.

Live (`task test-live LIVE_CHARTS=net-lb-app-int-cross-region`, as
catalog-live-tests, which has `roles/compute.networkAdmin`): forwarding
rules in `us-central1` and `us-east1` beside `GLOBAL_MANAGED_PROXY`
subnets, the HTTP proxy, a URL map sending `/groups` to a backend service
on an instance group and the rest to one on a zonal NEG (no network
given: the chart's `vpc_config.network`, as fabric), an HTTP and a TCP
health check, with the network and subnets made by the case. On
2026-11-12 (run `cat-11130312-b290`, the same offload VM) all ten objects
of the chart became Ready, the outputs evaluated (with both backend
services' generated IDs), everything was deleted and gone from Google
Cloud, and nothing was left in the project. No endpoint is applied live:
the harness runs Config Connector's controllers, not
config-connector-extensions' (`ComputeNetworkEndpoint` passes on the fake
cloud).

## Changes

- **0.1.0** (2026-11-12): the port.
