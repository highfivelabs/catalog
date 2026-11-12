# service-directory

A Service Directory namespace with its services, endpoints and IAM, as
Config Connector objects. A port of Cloud Foundation Fabric's
[`modules/service-directory`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/service-directory)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-service-directory` (`package.yaml`). Checked against Config Connector
v1.160.0.

## Example

```yaml
project_id: my-project
location: europe-west1
name: sd-1
services:
  one: {endpoints: [first], metadata: {}}
endpoint_config:
  one/first: {address: 127.0.0.1, port: 80, metadata: {}}
```

renders a `ServiceDirectoryNamespace` `sd-1`, its `ServiceDirectoryService`
`one` and the `ServiceDirectoryEndpoint` `first` (`tests/golden/services.yaml`
for a fuller case).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.namespace` | not a fabric variable: the namespace ID in full, used as given (no `namePrefix`) and checked (63 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the namespace ID starts with `<namePrefix>-`; services and endpoints are named inside it and take none; empty changes nothing |
| `labels` | fabric's namespace labels; here, as in every chart, on every object. Config Connector copies unprefixed labels to the namespace's labels and to the services' and endpoints' metadata, so with unprefixed `labels` the services and endpoints carry them as metadata too, which fabric's do not |
| `tags` | not a fabric variable: cloud labels on every resource (the same way as `labels`) |
| `project_id`, `location`, `name` | the namespace (`projectRef`, `location`, `resourceID`) |
| `iam` | one `IAMPartialPolicy` on the namespace (`docs/design.md`, "IAM": the listed members are kept, others left alone) |
| `services` | one `ServiceDirectoryService` per key, its `metadata` as the object's labels; one `ServiceDirectoryEndpoint` per item of `endpoints` |
| `service_iam` | one `IAMPartialPolicy` per service; a key that is not a service is refused |
| `endpoint_config` | each endpoint's `address` (`addressRef.external`), `port`, `network` (`networkRef.external`, `projects/<number>/locations/global/networks/<name>`) and `metadata` (the object's labels); a key that is not an endpoint of `services` is refused |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the namespace, services and endpoints |

Refused, in part:

| Variable | Why |
| --- | --- |
| `services[].metadata`, `endpoint_config[].metadata` | Config Connector carries a service's and an endpoint's metadata as its `metadata.labels`, so each key and value must be a valid Google Cloud label (lower-case letters, digits, `_` and `-`, at most 63 characters). Other metadata (`Owner: Team A`) is refused, naming the key |

## Outputs

| Output | Value |
| --- | --- |
| `id`, `name` | the namespace's full name, `projects/<project>/locations/<location>/namespaces/<id>`, from the inputs |
| `service_id`, `service_names` | each service's full name, `<namespace>/services/<key>`, from the inputs |

fabric's `endpoints`, `namespace` and `services` are whole Terraform
objects, which a Package does not output (`docs/design.md`, "Outputs").

## From Terraform

A `module "x" { source = ".../modules/service-directory" ... }` block's
arguments become the values unchanged (`examples/service-directory/`). To
adopt an existing namespace, keep its name: Config Connector acquires the
namespace, services and endpoints of those names (`docs/design.md`, "From
Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/service-directory`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/service-directory)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=service-directory`: render cases `basic`, `services`,
`names` and `mock`, each validated against Config Connector v1.160.0's CRD
schemas, and the refusals in `tests/*.fail.yaml`.

Fake cloud: `tests/mock.values.yaml` (a namespace and a service, each with
IAM, and an endpoint), `task test-mock MOCK_CHARTS=service-directory`,
2026-11-12: all five objects Ready, the outputs evaluated, every object
deleted. Not applied live: the live-test service accounts have no Service Directory
role.

## Changes

- **0.1.0** (2026-11-12): the port.
