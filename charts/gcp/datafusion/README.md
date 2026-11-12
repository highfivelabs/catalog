# datafusion

A Cloud Data Fusion instance and the firewall rule that admits SSH from its
range, as Config Connector objects. A port of Cloud Foundation Fabric's
[`modules/datafusion`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/datafusion)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-datafusion` (`package.yaml`). Checked against Config Connector
v1.160.0.

## Example

```yaml
project_id: my-project
name: my-datafusion
region: europe-west1
network: projects/my-project/global/networks/my-network
ip_allocation_create: false
ip_allocation: 10.0.0.0/22
network_peering: false
```

renders the private `DataFusionInstance` `my-datafusion` on that range and
the `ComputeFirewall` `my-datafusion-allow-ssh` (`tests/golden/basic.yaml`).
fabric's defaults, `ip_allocation_create: true` and `network_peering: true`,
are refused (below), so a values file sets both to false.

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.instance`, `names.firewall` | not fabric variables: the instance's and the firewall rule's names in full, used as given (no `namePrefix`) and checked (63 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the derived names start with `<namePrefix>-`; empty changes nothing |
| `labels` | Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label on the instance (fabric's `labels`) |
| `tags` | cloud labels on every object (Google Cloud labels) |
| `project_id` | the `cnrm.cloud.google.com/project-id` annotation of every object |
| `name`, `region`, `type`, `description`, `private_instance`, `enable_stackdriver_logging`, `enable_stackdriver_monitoring` | the instance's `resourceID`, `location` and the fields of the same names |
| `network`, `ip_allocation` | the instance's `networkConfig.networkRef` and `ipAllocation` |
| `firewall_create` | the `ComputeFirewall` `<name>-allow-ssh` on `network`: TCP 22 from `ip_allocation` to the tag `<name>-allow-ssh`, as fabric's. It needs `ip_allocation` |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the instance and the rule |

Refused when set:

| Variable | Why |
| --- | --- |
| `ip_allocation_create: true` (the default) | fabric reserves a /22 with a global address and passes `<address>/22` to the instance. The address is known only after apply, and the instance's `ipAllocation` is a string with no reference field (gap 8). Set it to false and give the range in `ip_allocation` (a range reserved for it, as the `net-vpc` chart's `psa_configs` reserve ranges) |
| `network_peering: true` (the default) | the peer network, `<region>-<name>`, is in the instance's tenant project, which the instance reports only once it exists (`status.tenantProjectId`), and `ComputeNetworkPeering`'s `peerNetworkRef` is a string (gap 8). Set it to false and peer with the `net-vpc-peering` chart, given the tenant project |

## Outputs

| Output | From |
| --- | --- |
| `id` | `projects/<project>/locations/<region>/instances/<name>`, as Terraform's `id` |
| `ip_allocation` | the `ip_allocation` input |
| `service_account` | `cloud-datafusion-management-sa@<status.tenantProjectId>.iam.gserviceaccount.com`, the account fabric's `service_account` is |
| `service_endpoint` | `status.serviceEndpoint` |
| `version` | the instance's `spec.version`, which Config Connector fills in from the cloud |

Not an output: `resource`, the whole Terraform object (`docs/design.md`,
"Outputs").

## Differences from the module

- **The peering fabric would make is wrong.** fabric's
  `google_compute_network_peering` names its network
  `projects/<project_id>/global/networks/<network>`, where `network` is
  already `projects/<project>/global/networks/<name>` (the form the
  variable asks for and the instance and address take), so the peering's
  network is malformed; the chart refuses the peering anyway (above).
- **Outputs** come from the live instance, so a dependent waits until it
  is ready.

## From Terraform

A `module "x" { source = ".../modules/datafusion" ... }` block's arguments
become the values unchanged (`examples/datafusion/`), once
`ip_allocation_create` and `network_peering` are false. To adopt an
existing instance, keep its name: Config Connector acquires the instance
and rule of those names (`docs/design.md`, "From Terraform"). A range and
peering fabric made stay with Terraform, or move to their own components.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/datafusion`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/datafusion)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=datafusion`: render cases `basic`, `full`, `public` (no
SSH rule) and `names`, each validated against Config Connector
v1.160.0's CRD schemas, and the refusals in `tests/*.fail.yaml`.

No fake-cloud case: the fake cloud has no Data Fusion API (a run on
2026-11-12 found mockgcp answering `datafusion.googleapis.com` with "host
name not known"; the SSH rule became Ready and was deleted).

Not applied live: no live-test service account has Data Fusion roles, and
an instance bills while it exists.

## Changes

- **0.1.0** (2026-11-12): the port.
