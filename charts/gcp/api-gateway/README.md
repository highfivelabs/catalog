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
config on a service account the chart makes, the gateway, and a role on
each of the three (`iam`). On 2026-11-13 (offload VM
`off-catalog-1113062359-5622`, config-connector-extensions `35833eb8`,
whose fake cloud serves `getIamPolicy` on a config and a gateway) all
seven objects became Ready, the outputs evaluated (`default_hostname`
null: mockgcp's gateway reports none) and all seven were deleted. In the
run before it (`off-catalog-1113061109-28826`, with four other charts)
the `IAMBinding` on the API was not deleted: the API went first, and the
binding's delete stopped on "reference APIGatewayAPI ... is not ready".
Deleting every object at once makes this a race in the binding's
controller, not in the chart.

Live (`hack/live-apply.sh` `LIVE_CHARTS=api-gateway`, `tests/live.yaml`; config-connector-extensions `c2f0c7d2`):
the API, its config, the gateway and a role on each. As cce-live-tests
(run `cat-11140025-cb6a`), the chart's service account could not be made
(`iam.serviceAccounts.create` denied); as catalog-live-tests
(`cat-11140120-96a6`) it was made, but the config could not run as it
(`iam.serviceAccounts.actAs` denied). The case now runs the config as
the runner. That run (2026-11-14, `cat-11140228-8dc0`, offload VM
`off-catalog-1114020110-6165`, as cce-live-tests) made every object
Ready, `APIGatewayAPIConfig` and `APIGatewayGateway` among them, and
deleted their objects; but the gateway was still in Google Cloud when the
run checked, and the API itself, which Google Cloud deletes only once its
configs are gone, outlived the run's 10 minutes (the sweep deleted both).

Two reruns at config-connector-extensions `aec29642` (2026-11-14, as
cce-live-tests): `cat-11140810-4fc4` (offload VM
`off-catalog-1114080558-15613`) and, after a fix to `hack/live-apply.sh`
(it had stopped waiting for deletes at once), `cat-11141004-80a0` (offload
VM `off-catalog-1114095936-14168`, a 30-minute limit). Both made every
object Ready, and in both the API outlived the run; the sweep deleted it.
The cause is config-connector-extensions': `APIGatewayGateway` and
`APIGatewayAPIConfig` start their delete and remove their finalizers in
the same second, without waiting for the operation. The config's delete
then failed in Google Cloud ("config is in use in us-central1:
[gw-...]", the gateway still being deleted), the config stayed there
(state `FAILED`), and Config Connector's `APIGatewayAPI` could not be
deleted ("has nested resources"). The fix belongs in
config-connector-extensions: wait for each delete operation, and retry the
config's while a gateway still uses it.

config-connector-extensions `2e1ccc9e` (#127) does both: the gateway's
and the config's deletes wait for their operations, a config's delete is
retried while a gateway still uses it, and configs are read with
`view=FULL`. The rerun (2026-11-14, `cat-11141340-1026`, offload VM
`off-catalog-1114133603-32687`, as catalog-live-tests, a 30-minute
limit) **passed**: the API, its config, the gateway and the three
`IAMBinding`s Ready, deleted and gone from Google Cloud, Config
Connector's `APIGatewayAPI` among them. Nothing was left.

## Changes

- **0.1.0** (2026-11-12): the port: the API, its config, the gateway, the
  config's service account and IAM on all three.
