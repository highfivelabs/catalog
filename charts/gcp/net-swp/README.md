# net-swp

A Secure Web Proxy: its gateway, the gateway security policy it enforces,
the policy's rules, URL lists, optionally a TLS inspection policy and
optionally a Private Service Connect service attachment that publishes the
proxy to other networks. A port of Cloud Foundation Fabric's
[`modules/net-swp`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/net-swp)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-net-swp` (`package.yaml`). Checked against Config Connector v1.160.0
(`ComputeServiceAttachment`) and config-connector-extensions'
`NetworkServicesGateway` (`networkservices.gcp.hfl.dev/v1beta1`),
`NetworkSecurityGatewaySecurityPolicy`,
`NetworkSecurityGatewaySecurityPolicyRule`,
`NetworkSecurityTLSInspectionPolicy` and `NetworkSecurityURLList`
(`networksecurity.gcp.hfl.dev/v1beta1`), at `d54a2075`. Config Connector's
own `NetworkServicesGateway` cannot make a Secure Web Proxy (it has no
`network`, `subnetwork`, `gatewaySecurityPolicy`, `certificateUrls`,
`labels` or `routingMode`), so the chart uses config-connector-extensions'
kind of the same name.

## Example

```yaml
project_id: my-project
region: europe-west4
name: secure-web-proxy
network: projects/my-project/global/networks/my-network
subnetwork: projects/my-project/regions/europe-west4/subnetworks/my-subnetwork
certificates:
  - projects/my-project/locations/europe-west4/certificates/secure-web-proxy-cert
gateway_config:
  addresses: ["10.142.68.3"]
  labels:
    example: value
```

renders the `NetworkSecurityGatewaySecurityPolicy` `secure-web-proxy` and
the `NetworkServicesGateway` `secure-web-proxy` of type
`SECURE_WEB_GATEWAY` on it, listening on 443 at `10.142.68.3`
(`tests/golden/basic.yaml`). As fabric's example says, it lets no request
through until rules allow some.

## Values

The module's variables, with the same names, types and defaults. The
chart carries all fourteen; three in part.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.gateway`, `names.policy`, `names.tlsInspectionPolicy` and `names.serviceAttachment` set those cloud names in full |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the four names above and every URL list's start with `<namePrefix>-`; empty changes nothing |
| `labels` | not a fabric variable: Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label on the gateway |
| `tags` | not a fabric variable: cloud labels on the gateway, the one resource here that has labels |
| `project_id` | every object's project annotation and `projectRef` |
| `region` | every object's `location` |
| `name` | the gateway's, the policy's, the TLS inspection policy's and the service attachment's names, as fabric names all four |
| `description` | the gateway's and the policy's `description`, and the default of the URL lists', rules' and TLS inspection policy's |
| `network`, `subnetwork` | the gateway's `network` and `subnetwork`, as given (fabric passes them through: give the `projects/...` paths) |
| `certificates` | the gateway's `certificateUrls` |
| `gateway_config` | `addresses`, `labels` (with `tags`), `ports` (default `[443]`), `scope` on the gateway; `next_hop_routing_mode` sets `routingMode` to `NEXT_HOP_ROUTING_MODE`, else `EXPLICIT_ROUTING_MODE`, the API's default for the null fabric sends. `delete_router_on_destroy` is accepted and has no effect (below) |
| `tls_inspection_config` | `id` sets the policy's `tlsInspectionPolicy`; `create_config` makes a `NetworkSecurityTLSInspectionPolicy` (`ca_pool`, `description`, `exclude_public_ca_set`) and sets it instead. Both set stops the render with fabric's message; `create_config` without `ca_pool` stops it too, as the API needs one |
| `url_lists` | one `NetworkSecurityURLList` per key, named by it |
| `policy_rules` | one `NetworkSecurityGatewaySecurityPolicyRule` per key under the policy: `priority`, `enabled`, `description`, `tls_inspect`, `allow` as `basicProfile` (`ALLOW` or `DENY`), and the matchers formatted with `matcher_args` as fabric's `format()` (below). A rule without `session_matcher` stops the render: the API needs one, as Terraform's resource does |
| `policy_rules_contexts` | the lookups for `matcher_args`: `secure_tags`, `service_accounts` and `url_lists`, with the chart's own URL lists added under their keys |
| `service_attachment` | a `ComputeServiceAttachment` on the gateway: `nat_subnets`, `automatic_connection`, `consumer_accept_lists`, `consumer_reject_lists`, `enable_proxy_protocol`, described `Service attachment for SWP <name>` as fabric describes it (fabric does not use `service_attachment.description` either). Refused: `domain_name` and `reconcile_connections` (no such fields) |
| `factories_config` | accepted and ignored: a chart cannot read the caller's files. Their contents go under `factories_data` |
| `factories_data` | not a fabric variable: `policy_rules` (file name => a rule as fabric's `schemas/policy-rule.schema.json`, with `enable`) and `url_lists` (file name => `{description, values}`), merged over `policy_rules` and `url_lists` as fabric merges the files |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps every resource |

**Matchers.** fabric formats each matcher with Terraform's
`format(matcher, args...)`, each argument `<context>:<value>` looked up in
that context (`secure_tag`, `service_account`, `url_list`), or the value
itself when the context has no such key. The chart does the same for the
`%s` and `%%` verbs fabric's matchers use; any other verb, or a count of
`%s` that differs from the arguments', stops the render, as Terraform's
`format()` fails the plan.

Name lengths: with a `namePrefix`, a derived name over 63 characters stops
the render; a name set under `names` is always checked. 63 characters
starting with a letter is an assumption for the gateway, the two policies
and the URL lists, whose APIs document their IDs as resource IDs.

## Outputs

| Output | From |
| --- | --- |
| `id` | `projects/<project>/locations/<region>/gateways/<gateway>` |
| `gateway` | the same ID. fabric's output is the whole gateway object; a Package outputs the field a consumer takes (`docs/design.md`, "Outputs") |
| `gateway_security_policy` | the policy's ID, `projects/<project>/locations/<region>/gatewaySecurityPolicies/<policy>`, from the gateway's spec |
| `service_attachment` | `projects/<project>/regions/<region>/serviceAttachments/<name>` with `service_attachment`, else null |

## Differences from the module

- **The Cloud Router is not deleted.** A Secure Web Proxy makes a Cloud
  Router with a Cloud NAT (`swg-autogen-router-<n>`) in its network and
  region, which the API keeps after the last gateway there is deleted.
  Terraform deletes it with `delete_router_on_destroy` (fabric's default,
  `true`); `NetworkServicesGateway` never does. Delete the router before
  deleting the network.
- **Rules follow the policy by name.** fabric recreates the rules when the
  policy is replaced (`replace_triggered_by`). Here a rule's
  `gatewaySecurityPolicy` is immutable, so a new policy name is a new rule
  object, which Bundt replaces.

## From Terraform

A `module "x" { source = ".../modules/net-swp" ... }` block's arguments
become the values unchanged (`examples/net-swp/`); the factory's files
become `factories_data`. Every resource keeps its name, so the components
adopt the resources Terraform made (`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/net-swp`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-swp)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=net-swp`: render cases `basic` (fabric's README example
"Minimal Secure Web Proxy"), `psc` ("PSC service attachments"), `rules`
("Secure Web Proxy with rules"), `tls` ("Secure Web Proxy with TLS
inspection"), `defaults`, `full` (every variable, the factory's data and
an existing TLS inspection policy), `names` and `mock`, each validated
against Config Connector v1.160.0's CRD schemas and
config-connector-extensions' CRDs (`crds/config-connector-extensions`),
and the refusals in `tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`, with the network
and subnets in `tests/mock.needs.yaml`): the policy, a URL list, two rules
(one on the list through its context), the gateway and a service
attachment on it. Not yet run.

Not applied live: the Network Services API is off in the live-test
project (config-connector-extensions' own live test of the kind skips for
that reason), and live runs wait on the live-test account's key
(KEYLIVE).

## Changes

- **0.1.0** (2026-11-13): the port: the gateway, its policy, rules, URL
  lists, TLS inspection policy and service attachment.
