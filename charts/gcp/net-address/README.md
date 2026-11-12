# net-address

Static IP addresses (external, internal, global, Private Service Access,
IPsec over Interconnect, Private Service Connect) with their PSC endpoints
and PSC network attachments, as Config Connector objects. A port of Cloud
Foundation Fabric's
[`modules/net-address`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/net-address)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-net-address` (`package.yaml`). Checked against Config Connector
v1.160.0 and config-connector-extensions at `89806ec7`.

The module was `blocked` in the coverage (`docs/coverage`): Config
Connector has `ComputeNetworkAttachment` only as `v1alpha1`.
config-connector-extensions now provides it as
`compute.gcp.hfl.dev/v1beta1`, so the chart renders network attachments
with no `allow_alpha`, as `IAMBinding` is rendered (`docs/design.md`,
"Alpha kinds"; the CRD is copied in `crds/config-connector-extensions`).

## Example

```yaml
project_id: my-project
external_addresses:
  one: {region: europe-west1}
global_addresses:
  app-1: {}
```

renders the `ComputeAddress`es `one` (regional, external) and `app-1`
(global) (`tests/golden/basic.yaml` has more).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable; this chart takes no names: every address, endpoint and attachment is named in its own entry (its `name`, else its key), as fabric names it |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every address, endpoint and attachment name starts with `<namePrefix>-` (63 characters, a leading letter); empty changes nothing |
| `labels`, `tags` | Kubernetes labels on every object; unprefixed ones, and `tags`, become Google Cloud labels on the addresses and forwarding rules |
| `project_id` | `cnrm.cloud.google.com/project-id` on every object, the attachments' `projectRef` |
| `global_addresses` | a global `ComputeAddress` each (`ipVersion: IPV6` when `ipv6` is set) |
| `external_addresses` | a regional `EXTERNAL` `ComputeAddress` each: IPv6 endpoint type, network tier, subnetwork, its own `labels` |
| `internal_addresses` | a regional `INTERNAL` `ComputeAddress` each in its subnetwork: address, purpose, IPv6, its own `labels` |
| `psa_addresses` | a global `VPC_PEERING` range (`ComputeAddress`) each on its network |
| `ipsec_interconnect_addresses` | a regional `IPSEC_INTERCONNECT` range each on its network |
| `network_attachments` | a `ComputeNetworkAttachment` (config-connector-extensions) each, in its subnet's region: connection preference (`ACCEPT_AUTOMATIC` with `automatic_connection`), accept and reject lists |
| `psc_addresses` | a `ComputeAddress` each (global with `PRIVATE_SERVICE_CONNECT` without a `region`, else regional in its subnet) and, with `service_attachment`, a `ComputeForwardingRule` endpoint on it: the service attachment, or `all-apis` / `vpc-sc` as the Google APIs bundle; PSC global access; a Service Directory namespace. fabric's four validations, with its messages |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the addresses, endpoints and attachments |

**Refused**, with a message naming the gap:

- `context`: Bundt's `${...}` expressions and `valueFrom` replace fabric's
  `$context` lookups (by design).
- `psc_addresses.*.service_attachment.service_directory_registration.region`:
  `ComputeForwardingRule`'s `serviceDirectoryRegistrations` have no region
  (gap). The namespace is carried.

## Outputs

fabric's address outputs are maps of whole address objects keyed by the
address name; here each maps the address name to its IP address, the one
field consumers take (`docs/design.md`, "Outputs").

| Output | Value |
| --- | --- |
| `external_addresses`, `global_addresses`, `internal_addresses`, `psc_addresses` | `{name: IP}`, the allocated address Config Connector reports, else the one the values set |
| `psa_addresses`, `ipsec_interconnect_addresses` | `{name: first address of the range}` |
| `network_attachment_ids` | `{key: projects/<p>/regions/<r>/networkAttachments/<name>}` |
| `psc` | `{key: {address: {address, id, name}, forwarding_rule: {id, name, psc_connection_id}}}`, as fabric's |

## From Terraform

A `module "x" { source = ".../modules/net-address" ... }` block's
arguments become the values unchanged (`examples/net-address/`). To adopt
existing addresses, keep their names: Config Connector acquires the
addresses of those names (`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/net-address`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-address)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=net-address`: render cases `basic`, `full`, `names` and
`mock`, each validated against Config Connector v1.160.0's CRD schemas
(and config-connector-extensions' for the attachments), and the refusals
in `tests/*.fail.yaml`.

The fake-cloud case (`tests/mock.values.yaml`, `task test-mock
MOCK_CHARTS=net-address`) applies a global address, an external address
and a PSA range on a network `tests/mock.needs.yaml` makes. Network
attachments and PSC endpoints are render-tested only: the fake cloud's
pin (`CCE_COMMIT`) predates config-connector-extensions'
`ComputeNetworkAttachment`, and a PSC endpoint needs a producer's service
attachment.

Applied live on 2026-11-12 (`task test-live LIVE_CHARTS=net-address`,
offload VM as `catalog-live-tests`, which has
`roles/compute.networkAdmin`): a global address and a Standard-tier
external address in `us-central1`, both Ready with their IPs as outputs,
deleted, and gone from Google Cloud.

## Changes

- **0.1.0** (2026-11-12): the port.
