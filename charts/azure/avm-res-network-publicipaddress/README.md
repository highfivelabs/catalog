# avm-res-network-publicipaddress

An Azure public IP address with its lock, role assignments and diagnostic
settings, as Azure Service Operator (ASO) objects. A port of the Azure
Verified Module
[`avm-res-network-publicipaddress`](https://github.com/Azure/terraform-azurerm-avm-res-network-publicipaddress/tree/2790d091b373fc2fd9e13aed3165c8d0813a87e4)
at v0.2.1 (`2790d091`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-network-publicipaddress`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

## Example

```yaml
name: pip-example
location: eastus2
resource_group_name: rg-example
subscription_id: <id>
```

renders the ASO `PublicIPAddress` `pip-example`: Standard, Regional,
static IPv4 in zones 1, 2 and 3, DDoS protection inherited from the
network (`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azurerm_public_ip.this` | always | `PublicIPAddress` (`network.azure.com/v20250301`), `public_ip`, owned by the resource group |
| `azurerm_management_lock.this` | `lock` set | `ManagementLock` (aso-extensions), `lock` |
| `azurerm_role_assignment.this` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `azurerm_monitor_diagnostic_setting.this` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` |
| telemetry | never | not ported |

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`); none is refused.

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` |
| `resource_group_name` (required) | `owner.armId`: `/subscriptions/<subscription_id>/resourceGroups/<resource_group_name>`, or `resource_group_name` itself when it is a resource group's ID |
| `allocation_method`, `ip_version` | `publicIPAllocationMethod`, `publicIPAddressVersion` |
| `sku`, `sku_tier` | `sku.name`, `sku.tier` |
| `zones` | `zones`, as strings, sorted |
| `ddos_protection_mode`, `ddos_protection_plan_id` | `ddosSettings.protectionMode`, `ddosSettings.ddosProtectionPlan.reference.armId` |
| `domain_name_label`, `reverse_fqdn` | `dnsSettings.domainNameLabel`, `dnsSettings.reverseFqdn` |
| `edge_zone` | `extendedLocation` (`type: EdgeZone`) |
| `idle_timeout_in_minutes` | `idleTimeoutInMinutes` |
| `ip_tags` | `ipTags` (`ipTagType`, `tag`) |
| `public_ip_prefix_id` | `publicIPPrefix.reference.armId` |
| `tags` | `spec.tags` |
| `lock` | the AVM lock interface, with the module's notes for the kind |
| `role_assignments` | the AVM interface; `skip_service_principal_aad_check` without a `principal_type` sends `ServicePrincipal`, as azurerm does. The module's azurerm resource drops `principal_type`; ASO sends it |
| `diagnostic_settings` | the AVM interface, `Dedicated` left to Azure as the module sends it; a setting without a name is `diag-<name>` |
| `enable_telemetry` | accepted; the chart sends no telemetry |

The module's validations become the schema's: the name, allocation
method, DDoS mode, idle timeout, IP version, SKU, tier and lock kind.

### Not module inputs

| Value | Renders |
| --- | --- |
| `subscription_id` | the subscription of `resource_group_name` when that is a name: the module's azurerm provider knows its subscription, ASO's owner is a resource ID |
| `names.publicIp` | the address's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name`, never of a name under `names`; checked against the 80-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

## Outputs

| Output | From |
| --- | --- |
| `name` | computed from the inputs, as the module sets it |
| `public_ip_address` | the address Azure allocated, ASO's `status.ipAddress` |
| `public_ip_id`, `resource_id` | the address's `status.id` |

## From Terraform

A module block's arguments are the values, plus `subscription_id` when
`resource_group_name` is a name. ASO adopts an address that exists when an
object with its name is applied (the address is kept), so keep the name
and leave `namePrefix` empty; set `deletion_policy: ABANDON` for the first
apply, `terraform state rm` the module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-network-publicipaddress`](https://github.com/Azure/terraform-azurerm-avm-res-network-publicipaddress/tree/v0.2.1)
at v0.2.1 (`2790d091`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-network-publicipaddress`: render cases `basic`,
`basic-ipv6`, `full`, `names` and `mock`, each validated against ASO
v2.22.0's CRD schemas and aso-extensions' `ManagementLock` CRD, and the
refusals in `tests/*.fail.yaml`. Not yet applied live or to the fake cloud
(`docs/azure.md`, "8. Charts").

## Changes

- **0.1.0** (2026-11-12): the port.
