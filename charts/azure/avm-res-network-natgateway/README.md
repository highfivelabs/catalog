# avm-res-network-natgateway

An Azure NAT gateway with the public IP addresses it creates, and its
locks, role assignments and diagnostic settings, as Azure Service Operator
(ASO) objects. A port of the Azure Verified Module
[`avm-res-network-natgateway`](https://github.com/Azure/terraform-azurerm-avm-res-network-natgateway/tree/597df2389d997c93da6a559f64fe7096ef30e24e)
at v0.3.2 (`597df238`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-network-natgateway`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

## Example

```yaml
name: natgw-example
location: eastus2
parent_id: /subscriptions/<id>/resourceGroups/rg-example
public_ips:
  ip_1: {name: nat_gw_pip_1}
```

renders the ASO `NatGateway` `natgw-example` (StandardV2, zones 1, 2 and
3) and the `PublicIPAddress` `nat_gw_pip_1` it uses
(`tests/golden/basic.yaml`). A subnet takes the gateway by its
`resource_id` output (`avm-res-network-virtualnetwork`'s
`subnets.<key>.nat_gateway.id`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.this` (`Microsoft.Network/natGateways`) | always | `NatGateway` (`network.azure.com/v20250301`), `nat_gateway`, owned by `parent_id` |
| `azapi_resource.public_ip` (`Microsoft.Network/publicIPAddresses`) | one per `public_ips` entry | `PublicIPAddress`, `public_ip:<key>`, owned by `parent_id`; the gateway names it by Kubernetes reference |
| `azapi_resource.public_ip_lock` | an entry's `public_ip_configuration.lock` | `ManagementLock` (aso-extensions), `public_ip:<key>/lock` |
| `azapi_resource.lock` | `lock` set | `ManagementLock`, `lock` |
| `azapi_resource.role_assignment` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `azapi_resource.diagnostic_setting` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` |
| telemetry | never | not ported |

ASO and the module are both at ARM API version 2025-03-01.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`).

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` |
| `parent_id` (required) | `owner.armId` of the gateway and the public IPs |
| `sku_name` | `sku.name` |
| `zones` | `zones` (sorted); with `StandardV2` always `["1", "2", "3"]`, as the module sends |
| `idle_timeout_in_minutes` | `idleTimeoutInMinutes` |
| `public_ips` | one public IP each, named by the entry (with the `namePrefix`); IPv4 ones in `publicIpAddresses`, IPv6 ones in `publicIpAddressesV6` |
| `public_ip_configuration` | the public IP keyed alike: `allocation_method`, `ddos_protection_mode` and `ddos_protection_plan_id` (`ddosSettings`), `domain_name_label` (`dnsSettings`), `idle_timeout_in_minutes`, `ip_version`, `sku`, `sku_tier`, `zones`, `tags` (in place of the module's `tags`), `lock`; the module's defaults for what is unset. `inherit_tags` is accepted and, as in the module, changes nothing |
| `public_ip_resource_ids`, `public_ip_v6_resource_ids` | `publicIpAddresses`, `publicIpAddressesV6` by `armId`, after the created ones |
| `public_ip_prefix_resource_ids`, `public_ip_prefix_v6_resource_ids` | `publicIpPrefixes`, `publicIpPrefixesV6` |
| `tags` | `spec.tags` of the gateway, and of a public IP without tags of its own |
| `lock` | the lock interface (avm-utl-interfaces 0.5.0: no notes); a public IP's lock has the module's notes |
| `role_assignments` | the AVM interface |
| `diagnostic_settings` | the v2 interface (logs and metrics as given, with their retention policies); a setting needs a name, as Azure does |
| `enable_telemetry` | accepted; the chart sends no telemetry |
| `timeouts` | refused: ASO has none; Bundt sets a component's time limit |

The module's preconditions stop the render with the module's messages: a
`StandardV2` gateway's public IPs must be `StandardV2`, a `Standard`
gateway has at most one zone, and a `StandardV2` public IP uses all three.

The module ignores changes to `zones` after creation. ASO does not, but
Azure refuses them anyway (a resource's zones are fixed), so a changed
`zones` fails rather than being ignored.

### Not module inputs

| Value | Renders |
| --- | --- |
| `names.natGateway` | the gateway's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name` and of each public IP's name (never of a name under `names`); checked against the 80-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

## Outputs

| Output | From |
| --- | --- |
| `resource_id` | the gateway's `status.id` |
| `public_ip_resource` | keyed like `public_ips`: each public IP's `id`, `name` and allocated `ip_address`, the fields consumers take from the module's whole azapi objects |

Not an output: `resource`, the module's whole azapi object.

## From Terraform

A module block's arguments are the values, unchanged. ASO adopts a
gateway or public IP that exists when an object with its name is applied,
so keep the names and leave `namePrefix` empty; set `deletion_policy:
ABANDON` for the first apply, `terraform state rm` the module, then remove
`ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-network-natgateway`](https://github.com/Azure/terraform-azurerm-avm-res-network-natgateway/tree/v0.3.2)
at v0.3.2 (`597df238`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-network-natgateway`: render cases `basic`,
`full`, `standard`, `names` and `mock`, each validated against ASO
v2.22.0's CRD schemas and aso-extensions' `ManagementLock` CRD, and the
refusals in `tests/*.fail.yaml`. `task test-live-azure` applies it to the Azure
sandbox with Azure Service Operator, evaluates the outputs, deletes it
and checks Azure no longer has it: passed on 2026-11-12. `task test-mock-azure` applies its `tests/mock.values.yaml` to aso-extensions'
fake cloud with stock ASO (`docs/azure.md`, "8. Charts").

## Changes

- **0.1.0** (2026-11-12): the port.
