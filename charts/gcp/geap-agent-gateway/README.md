# geap-agent-gateway

An Agent Gateway, which governs the traffic of AI agents, MCP servers and
tools, with the agent connectivity template it reaches a VPC through. A
port of Cloud Foundation Fabric's
[`modules/geap-agent-gateway`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/geap-agent-gateway)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-geap-agent-gateway` (`package.yaml`). Config Connector has no kind
for either resource; the chart uses config-connector-extensions'
`NetworkServicesAgentGateway` and `NetworkServicesAgentConnectivityTemplate`
(`networkservices.gcp.hfl.dev/v1alpha1`), at `d54a2075`.

**The chart needs `allow_alpha: true`.** Both kinds are `v1alpha1`, so
every render without it stops (`docs/design.md`, "Alpha kinds").

**Every render sets `iap_config: null`.** Fabric's default (`{}`) puts
Identity-Aware Proxy in front of the gateway, which no kind can express
(below), so the chart refuses it rather than leave it out unannounced.

## Example

```yaml
allow_alpha: true
iap_config: null
name: my-gateway
project_id: my-project-id
project_number: "1234567890"
region: europe-west1
access_path: AGENT_TO_ANYWHERE
networking_config:
  psc_i_network_attachment_id: projects/my-project-id/regions/europe-west1/networkAttachments/my-na
  access_types: [PRIVATE]
  vpc_egress: ALL_TRAFFIC
  dns_peering_config:
    domains: [corp.internal.]
    target_network: projects/my-project-id/global/networks/my-vpc
```

renders the connectivity template `my-gateway` over that network
attachment, with DNS peering for `corp.internal.`, and the Google-managed
egress gateway `my-gateway` that references it by project number
(`tests/golden/psc.yaml`; fabric's README example "VPC connectivity", its
`$context` lookups resolved).

## Values

The module's variables, with the same names, types and defaults. The
chart carries 11 of the 15; four are refused, and one is accepted in part.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.gateway` and `names.connectivityTemplate` set the two IDs in full |
| `namePrefix` | not a fabric variable: `<namePrefix>-` in front of the gateway's and the template's IDs |
| `labels` | fabric's gateway labels, and the catalog's Kubernetes labels: on every object, and an unprefixed key also on the gateway's and the template's cloud labels |
| `tags` | not a fabric variable: cloud labels on the gateway and the template |
| `allow_alpha` | not a fabric variable: required, `true` |
| `deletion_policy` | not a fabric variable: `DELETE` (default) or `ABANDON`; `PREVENT` is refused |
| `name` | the gateway's ID (`resourceID`), and the template's when `networking_config.name` is not set |
| `project_id`, `region` | both objects' `projectRef` and `location` |
| `description` | the gateway's `description` |
| `access_path` | `ingress` (any case) or `CLIENT_TO_AGENT` is `CLIENT_TO_AGENT`, anything else `AGENT_TO_ANYWHERE`, as fabric's: the Google-managed gateway's `googleManaged.governedAccessPath` and the template's `accessPath`. Required for a Google-managed gateway and with a template |
| `is_google_managed` | `true`: `googleManaged`; `false`: `selfManaged` with `proxy_uri` |
| `proxy_uri` | `selfManaged.resourceUri`; required when `is_google_managed` is `false` |
| `registries` | the gateway's `registries` |
| `networking_config` | `psc_i_network_attachment_id` makes the `NetworkServicesAgentConnectivityTemplate` (named `name`, else the gateway's), with `access_types`, `description`, `labels`, `vpc_egress` and `dns_peering_config` (`domains`, `target_network`) in its `egressNetworkConfig`; `connectivity_template_reuse` puts an existing template's name in the gateway's `agentConnectivityTemplate` |
| `project_number` | the project in the template reference the gateway takes (`projects/<number>/locations/<region>/agentConnectivityTemplates/<id>`: the API takes a number there). **Required with `psc_i_network_attachment_id`**: fabric's `null` reads the `google_project` data source, which a chart cannot; pass it from the project component's outputs |
| `iap_config` | **refused unless `null`** (a gap): fabric makes a `google_network_services_authz_extension` for `iap.googleapis.com` and a `REQUEST_AUTHZ` authorization policy binding it to the gateway. The type's only kind, Config Connector's `NetworkServicesAuthzExtension` (`v1alpha1`), is a load balancer callout: it requires a backend service, an authority and a load balancing scheme, and has no `service` field, so it cannot name IAP |
| `model_armor_config` | **refused when set** (a gap): the same, for Model Armor's `CONTENT_AUTHZ` |
| `access_policies` | **refused when set** (a gap): fabric's IAM v3 access policies and their bindings. Config Connector's `IAMAccessPolicy` (`v1alpha1`) takes an organization only (fabric's is a project's), and config-connector-extensions' `IAMPolicyBinding` targets a principal set only, where an access policy binds to a resource (the project or the gateway); so `policy_reuse` cannot be bound either |
| `context` | **refused when set** (by design): Bundt expressions (`${...}`) and `valueFrom` replace fabric's `$context` lookups |

Fabric's validations stop the render with fabric's messages: an access
path for a Google-managed gateway or a template, a proxy URI for a
self-managed one, at most one of `psc_i_network_attachment_id` and
`connectivity_template_reuse`, and DNS peering only with an attachment and
with at least one domain. `vpc_egress` and `access_types` are enums in the
schema.

## Outputs

| Output | From |
| --- | --- |
| `id` | the gateway's `status.externalRef` (`projects/<p>/locations/<l>/agentGateways/<id>`); null until reported |
| `connectivity_template_id` | the gateway's `agentConnectivityTemplate`: the template the chart makes, by project number, or `connectivity_template_reuse`; null with neither |

Not provided: `agent_gateway` (fabric's whole object; a Package outputs
the fields a consumer takes, `docs/design.md`, "Outputs"), and
`access_policy_ids`, `authz_extension_ids`, `authz_policy_ids` and
`policy_binding_ids`, whose resources are refused.

## Differences from the module

- **No authorization.** IAP, Model Armor and IAM access policies are
  refused (above). config-connector-extensions would need an authorization
  extension that names a service, a project-scoped access policy, and a
  policy binding with a resource target to close them.
- **Labels.** The catalog's `labels` go on every object, so the template
  carries the gateway's labels beside its own `networking_config.labels`;
  fabric's template has only its own.
- **The template reference is a string.** The gateway takes the template
  by name, not by Kubernetes reference, so the gateway can reconcile
  before the template exists and retry until it does.

## From Terraform

A `module "x" { source = ".../modules/geap-agent-gateway" ... }` block's
arguments become the values unchanged, with `allow_alpha: true`,
`iap_config: null` and, with a network attachment, `project_number`. A
module that used fabric's default IAP authorization, Model Armor or access
policies cannot move yet: the chart refuses them at plan time. The gateway
and the template keep their names, so they adopt what Terraform made
(`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/geap-agent-gateway`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/geap-agent-gateway)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=geap-agent-gateway`: render cases `basic` (fabric's
README example "Minimal Gateway deployment"), `psc` ("VPC connectivity"),
`reuse` (attaching an existing template), `proxy` ("Connect to
self-managed proxies"), `full`, `names` and `mock`, each validated against
config-connector-extensions' CRDs (`crds/config-connector-extensions`), and
the refusals in `tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`): a Google-managed
egress gateway and the connectivity template it makes over a network
attachment. config-connector-extensions serves both kinds from its
generated kinds' fake (`pkg/discokind/fake`). On 2026-11-13 (offload VM
`off-catalog-1113112805-17079`, config-connector-extensions `d54a2075`)
both objects became Ready, the outputs evaluated and both were deleted.

Not applied live: live runs are pending KEYLIVE, and the Network Services
API (agent gateways are in preview) is not on in the live-test project
(config-connector-extensions' own live tests of both kinds skip for that
reason).

## Changes

- **0.1.0** (2026-11-13): the port: the gateway, Google- or self-managed,
  and the connectivity template it makes or reuses.
