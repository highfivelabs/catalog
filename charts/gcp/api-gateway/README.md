# api-gateway

An API Gateway API, its API config from an OpenAPI spec, the gateway that
serves the config in a region, optionally a service account for the
config, and IAM on all three, as Config Connector objects. A port of Cloud
Foundation Fabric's
[`modules/api-gateway`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/api-gateway)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-api-gateway` (`package.yaml`). Checked against Config Connector
v1.160.0 (`APIGatewayAPI`, `IAMServiceAccount`) and config-connector-extensions'
`APIGatewayAPIConfig`, `APIGatewayGateway` (`apigateway.gcp.hfl.dev/v1beta1`)
and `IAMBinding` (`iam.gcp.hfl.dev/v1beta1`), at `11baa460`.

## Example

```yaml
project_id: my-project
api_id: api
region: europe-west1
service_account_create: true
iam:
  roles/apigateway.admin: ["user:mirene@google.com"]
  roles/apigateway.viewer: ["user:mirene@google.com"]
spec: |
  # The OpenAPI spec contents
  # ...
```

renders the `APIGatewayAPI` `api`, the `IAMServiceAccount`
`sa-api-cfg-api`, the `APIGatewayAPIConfig` `api-cfg-api-<hash>` using
that account, the `APIGatewayGateway` `gw-api` in `europe-west1`, and six
`IAMBinding`s, one per role on each of the three (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults. The
chart carries all eight.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.api`, `names.gateway` and `names.serviceAccount` set those cloud names in full |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every derived name starts with `<namePrefix>-`; empty changes nothing |
| `labels` | fabric's `labels`, with the catalog's meaning: Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label (Config Connector copies it to the API, where fabric puts its labels) |
| `tags` | not a fabric variable: cloud labels on every resource |
| `project_id` | every object's project annotation and `projectRef` |
| `api_id` | the API's ID (`resourceID` and `displayName`, as fabric gives both), and the base of the derived names: gateway `gw-<api_id>`, service account `sa-api-cfg-<api_id>` |
| `region` | the gateway's `location` |
| `spec` | the config's one OpenAPI document, `spec.yaml`, base64-encoded as fabric sends it; and the hash in the config's name (below) |
| `service_account_create` | an `IAMServiceAccount` `sa-api-cfg-<api_id>` (fabric's display name), which the config uses as `gatewayServiceAccount` |
| `service_account_email` | the config's `gatewayServiceAccount` when the chart makes no account |
| `iam` | one `IAMBinding` per role on the API, one on the config and one on the gateway (config-connector-extensions, `v1beta1`): exact, as fabric's three `*_iam_binding` resources |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the API, config, gateway and service account (not the IAM bindings) |

Nothing is refused. Name lengths: with a `namePrefix`, a derived API or
gateway name over 63 characters, an API config name over 63, or a service
account ID over 30 stops the render; a name set under `names` is always
checked. The API documents no limit for API, config or gateway IDs; 63 is
an assumption, the length the catalog uses for names that have none
documented.

## Outputs

| Output | From |
| --- | --- |
| `api_id` | the API's name, from the inputs |
| `api` | `projects/<project>/locations/global/apis/<api>`, from the inputs. fabric's output is the whole API object; a Package outputs the field a consumer takes (`docs/design.md`, "Outputs") |
| `api_config_id` | the config's ID, from the rendered config (its name ends with a hash of the spec, which CEL cannot compute) |
| `api_config` | `projects/<project>/locations/global/apis/<api>/configs/<config>`; fabric's is the whole object |
| `gateway_id` | the gateway's name, from the inputs |
| `gateway` | `projects/<project>/locations/<region>/gateways/<gateway>`; fabric's is the whole object |
| `default_hostname` | the gateway's `status.observedState.defaultHostname` |
| `service_account` | `projects/<project>/serviceAccounts/<email>` with `service_account_create`, else null; fabric's is the whole object |
| `service_account_email`, `service_account_iam_email` | the account the config uses, from the inputs, as fabric's local computes it |

## Differences from the module

- **The config's name.** fabric names the config
  `api-cfg-<api>-<md5(spec)>`, so a new spec is a new config, made before
  the old one is destroyed. Helm has no md5, so the chart's hash is the
  first 32 hex characters of `sha256(spec)`: a new spec is still a new
  config (a new object, since a config's ID cannot change), and the
  gateway moves to it; Bundt prunes the old object once the new plan is
  applied. The ID differs from the one Terraform made for the same spec
  (below).
- **The API's managed service is not enabled.** fabric enables the API's
  managed service (`google_project_service`, disabled on destroy). Its name
  (`<api>-<hash>.apigateway.<project>.cloud.goog`) is given by the API when
  it is created, and a chart renders before that, so the chart cannot name
  it. Enable it as a second component (a `Service` from the `api`
  component's managed service) or with the project's services; calls that
  need the service enabled (API keys) fail until it is.

## From Terraform

A `module "x" { source = ".../modules/api-gateway" ... }` block's arguments
become the values unchanged (`examples/api-gateway/`). The API, the
gateway and the service account keep their names, so they adopt the
resources Terraform made (`docs/design.md`, "From Terraform"). The config
does not: its name's hash differs, so the first apply creates a new config
with the same spec and moves the gateway to it; delete the config
Terraform made afterwards. IAM is `IAMBinding`, exact per role as fabric's
is: members added out of band to a role the chart manages are removed.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/api-gateway`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/api-gateway)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=api-gateway`: render cases `basic` (fabric's README
example "Create service account"), `defaults` ("Basic example"), `full`
(every variable, with an existing service account), `names` and `mock`,
each validated against Config Connector v1.160.0's CRD schemas and
config-connector-extensions' CRDs (`crds/config-connector-extensions`), and
the refusals in `tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`): the API, the
config on a service account the chart makes, and the gateway. On
2026-11-12 (offload VM `off-catalog-1113002414-5046`,
config-connector-extensions `11baa460`) all four objects became Ready,
the outputs evaluated (`default_hostname` null: mockgcp's gateway reports
none) and all four were deleted. The case has no `iam`: in an earlier run
(`off-catalog-1113001035-9748`) the `IAMBinding` on the API became Ready,
but mockgcp answered `getIamPolicy` on the config and on the gateway with
404, so the bindings on those two are only render-tested.

Not applied live: the API Gateway API is not enabled in the live-test
project, and neither live-test service account has an API Gateway role.

## Changes

- **0.1.0** (2026-11-12): the port: the API, its config, the gateway, the
  config's service account and IAM on all three.
