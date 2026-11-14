# geap-agent-gateway

An Agent Gateway, which governs the traffic of AI agents, MCP servers and
tools, with the agent connectivity template it reaches a VPC through. A
port of Cloud Foundation Fabric's
[`modules/geap-agent-gateway`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/geap-agent-gateway)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-geap-agent-gateway` (`package.yaml`). Config Connector has no kind
for either resource; the chart uses config-connector-extensions'
`NetworkServicesAgentGateway` and `NetworkServicesAgentConnectivityTemplate`
(`networkservices.gcp.hfl.dev/v1alpha1`), at `d54a2075`, and for IAP and
Model Armor its `NetworkServicesAuthzExtension` and
`NetworkSecurityAuthzPolicy` (`v1beta1`), at `c2f0c7d2`.

**The chart needs `allow_alpha: true`.** Both kinds are `v1alpha1`, so
every render without it stops (`docs/design.md`, "Alpha kinds").

**IAP is on by default, as in fabric.** `iap_config`'s default (`{}`)
makes an authorization extension for `iap.googleapis.com` and the
`REQUEST_AUTHZ` authorization policy binding it to the gateway; set
`iap_config: null` for a gateway without it.

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
chart carries 13 of the 15; two are refused, and one is accepted in part.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.gateway` and `names.connectivityTemplate` set the two IDs in full, `names.iap` and `names.modelArmor` the ID of each authorization extension and its policy |
| `namePrefix` | not a fabric variable: `<namePrefix>-` in front of every object's ID |
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
| `iap_config` | not `null` (fabric's default `{}`): a config-connector-extensions `NetworkServicesAuthzExtension` (`networkservices.gcp.hfl.dev/v1beta1`) for `iap.googleapis.com`, with `fail_open` (default `false`), `timeout` (default `2s`) and the metadata `iapPolicyVersion` (`policy_version`, default `V2`) and `iamEnforcementMode` (`iam_enforcement_mode`, when set); and a `NetworkSecurityAuthzPolicy` (`networksecurity.gcp.hfl.dev/v1beta1`), `CUSTOM`, `REQUEST_AUTHZ`, whose `target.resources` is the gateway (`projects/<p>/locations/<region>/agentGateways/<id>`, no `loadBalancingScheme`) and whose `customProvider.authzExtension` is that extension. Both are named `name`, else `<name>-iap`. Fabric's checks: `iam_enforcement_mode` `DRY_RUN` or null, `policy_version` `V1` or `V2` |
| `model_armor_config` | the same pair for Model Armor: the extension's `service` is `modelarmor.<region>.rep.googleapis.com` and its metadata `model_armor_settings` the JSON fabric writes of `request_template_id` and `response_template_id` (a short id becomes `projects/<p>/locations/<region>/templates/<id>`, as fabric's); the policy is `CONTENT_AUTHZ`, with `authz_hosts` as an HTTP rule on those hosts (exact). Named `name`, else `<name>-ma` |
| `access_policies` | per entry with `rules`, a config-connector-extensions `IAMAccessPolicy` (`iam.gcp.hfl.dev/v1beta1`) in the project, `global`, named by its key: each rule's `principals` and `excluded_principals` (`user:`, `group:`, `serviceAccount:` and `allUsers` turned into IAM v3 principals, as fabric does), `effect`, `description`, `permissions` (default `iap.googleapis.com/resources.egressViaIAP`), `excluded_permissions`, and the condition fabric builds for `condition_service` from `registry` (the governed registries' locations, else the region), `agent_id`, `endpoint_id`, `mcp_server_id` and `condition`; `display_name` and `annotations`. Per entry with `bind` (default), an `IAMPolicyBinding` (`v1alpha1`), `ACCESS`, named `binding_id` or the key, binding that policy, or `policy_reuse` by its resource name, to `target_resource`: `project`, `gateway` or a `//...` URI, with `binding_condition`. Fabric's checks |
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
| `access_policy_ids` | per access policy the chart makes, keyed as fabric's: `projects/<project>/locations/global/accessPolicies/<id>` |
| `policy_binding_ids` | per binding, keyed as fabric's: `projects/<project>/locations/global/policyBindings/<id>` |
| `connectivity_template_id` | the gateway's `agentConnectivityTemplate`: the template the chart makes, by project number, or `connectivity_template_reuse`; null with neither |
| `authz_extension_ids` | `iap` and `model_armor`: `projects/<project>/locations/<region>/authzExtensions/<id>`, null for one not made |
| `authz_policy_ids` | `iap` and `model_armor`: `projects/<project>/locations/<region>/authzPolicies/<id>`, null for one not made |

Not provided: `agent_gateway` (fabric's whole object; a Package outputs
the fields a consumer takes, `docs/design.md`, "Outputs").

## Differences from the module

- **The authorization policies are not ordered.** Fabric creates the
  Model Armor policy after the IAP one, since the API refuses two
  concurrent policy creates on one gateway. Config Connector has no
  ordering, so with both set the second create can be refused once and is
  retried. Each policy names the gateway and its extension by resource
  name (the kind takes strings), so it also retries until both exist.
- **Model Armor template ids are not looked up in `context`** (refused);
  pass them in full or short.
- **Labels.** The catalog's `labels` go on every object, so the template
  carries the gateway's labels beside its own `networking_config.labels`;
  fabric's template has only its own.
- **The template reference is a string.** The gateway takes the template
  by name, not by Kubernetes reference, so the gateway can reconcile
  before the template exists and retry until it does.

## From Terraform

A `module "x" { source = ".../modules/geap-agent-gateway" ... }` block's
arguments become the values unchanged, with `allow_alpha: true` and, with a
network attachment, `project_number`. The gateway, the template and the
authorization extensions and policies keep their names, so they adopt what
Terraform made (`docs/design.md`, "From Terraform").

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
README example "Minimal Gateway deployment", with the default IAP
authorization), `psc` ("VPC connectivity"), `reuse` (attaching an existing
template), `proxy` ("Connect to self-managed proxies"), `access-policies`
(IAM v3 access policies and their bindings), `iap-dry-run` ("Enforcement
mode"), `model-armor` ("Screening content with Model Armor"), `full`,
`names` and `mock`, each validated against
config-connector-extensions' CRDs (`crds/config-connector-extensions`), and
the refusals in `tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`): a Google-managed
egress gateway and the connectivity template it makes over a network
attachment, an IAM v3 access policy bound to the gateway, and the default
IAP authorization and Model Armor (short template ids, one authz host):
two `NetworkServicesAuthzExtension`s and two `NetworkSecurityAuthzPolicy`s
targeting the gateway. config-connector-extensions serves every kind from
its generated kinds' fake (`pkg/discokind/fake`), which checks no policy
target. On 2026-11-13 (offload VM `off-catalog-1113221513-25255`,
config-connector-extensions `c2f0c7d2`) all 8 objects became Ready, the
outputs evaluated (`authz_extension_ids` and `authz_policy_ids` included)
and all 8 were deleted.

Live (`hack/live-apply.sh` `LIVE_CHARTS=geap-agent-gateway`, `tests/live.yaml`;
2026-11-14, run `cat-11140025-cb6a`, offload VM
`off-catalog-1114002056-10707`, as cce-live-tests, config-connector-extensions `c2f0c7d2`): a
Google-managed egress gateway over a network attachment of the run,
fabric's default IAP authorization, and an IAM v3 access policy bound to
the gateway. The gateway, its connectivity template, the IAP
`NetworkServicesAuthzExtension` and `NetworkSecurityAuthzPolicy` were
Ready and deleted. The access policy failed, on config-connector-
extensions' side: `IAMAccessPolicy` got "429 Quota exceeded for quota
metric 'GetAccessPolicy Requests'" (IAM allows 5 a minute), so its
`IAMPolicyBinding` never had a policy; and the attachment's network and
subnet outlived the run's limit (the sweep deleted them). Model Armor
needs templates of its own API, which the fake-cloud case covers.

## Changes

- **0.3.0** (2026-11-13): `iap_config` (on by default, as fabric's) and
  `model_armor_config`: config-connector-extensions'
  `NetworkServicesAuthzExtension` and `NetworkSecurityAuthzPolicy`
  targeting the gateway, and the `authz_extension_ids` and
  `authz_policy_ids` outputs.
- **0.2.0** (2026-11-13): `access_policies`: config-connector-extensions'
  `IAMAccessPolicy` and `IAMPolicyBinding`, and the `access_policy_ids`
  and `policy_binding_ids` outputs.
- **0.1.0** (2026-11-13): the port: the gateway, Google- or self-managed,
  and the connectivity template it makes or reuses.
