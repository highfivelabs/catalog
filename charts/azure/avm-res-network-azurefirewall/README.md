# avm-res-network-azurefirewall

An Azure Firewall in a virtual network or a virtual hub, with its IP
configurations, management IP configuration, policy, SNAT ranges, zones,
and its lock, role assignments and diagnostic settings, as Azure Service
Operator (ASO) objects. A port of the Azure Verified Module
[`avm-res-network-azurefirewall`](https://github.com/Azure/terraform-azurerm-avm-res-network-azurefirewall/tree/e88c8db23982193eb3511c0d69fea71d0dcfbb2c)
at v0.5.0 (`e88c8db2`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-network-azurefirewall`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

## Example

```yaml
name: afw-example
location: eastus2
resource_group_name: rg-example
subscription_id: <id>
firewall_sku_name: AZFW_VNet
firewall_sku_tier: Standard
ip_configurations:
  default:
    name: ipconfig1
    subnet_id: /subscriptions/<id>/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-hub/subnets/AzureFirewallSubnet
    public_ip_address_id: /subscriptions/<id>/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-afw
```

renders one ASO `AzureFirewall` `afw-example`, a Standard firewall in all
three zones (`tests/golden/basic.yaml`). Give it rules with a firewall
policy (`firewall_policy_id`; the `avm-res-network-firewallpolicy` chart).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.this` | always | `AzureFirewall` (`network.azure.com/v20250301`), `azure_firewall`, owned by the resource group |
| `azapi_resource.lock` | `lock` set | `ManagementLock` (aso-extensions), `lock`, named `lock-<kind>` and with the module's notes unless given |
| `azapi_resource.role_assignments` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `azapi_resource.diagnostic_settings` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` |
| `time_sleep.lock_removal`, `data.azapi_resource_list.role_definitions`, telemetry | never | not ported: ASO retries a delete a lock still blocks, and resolves a role by name itself |

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`), with the module's validations.

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` |
| `resource_group_name` (required), `parent_id` | `owner.armId`: `parent_id` when set, else `/subscriptions/<subscription_id>/resourceGroups/<resource_group_name>`, or `resource_group_name` itself when it is a group's ID |
| `firewall_sku_name`, `firewall_sku_tier` (required) | `sku.name`, `sku.tier` |
| `ip_configurations`, `firewall_ip_configuration` (deprecated) | `ipConfigurations`, the deprecated list first and then the map in key order, as the module orders them: a name, the public IP and the subnet (`AzureFirewallSubnet`, in exactly one entry of the map) by ID |
| `firewall_management_ip_configuration` | `managementIpConfiguration` (the `AzureFirewallManagementSubnet` and a public IP; a Basic firewall needs one) |
| `firewall_policy_id` | `firewallPolicy` |
| `firewall_private_ip_ranges` | `additionalProperties["Network.SNAT.PrivateRanges"]`, the ranges joined with commas |
| `firewall_virtual_hub` | `virtualHub` and `hubIPAddresses.publicIPs.count` (default 1) |
| `firewall_zones` | `zones`, sorted; none when empty |
| `tags` | `spec.tags` |
| `lock` | the AVM lock interface, with the module's default name (`lock-<kind>`) and notes |
| `role_assignments` | the AVM interface: an entry's `name` is the assignment's GUID; a role by name (ASO resolves it) or ID; `skip_service_principal_aad_check` without a `principal_type` sends `ServicePrincipal`, as the module does |
| `diagnostic_settings` | the AVM interface: log groups (default `allLogs`), log categories, metric categories (default `AllMetrics`; an empty list sends none), the destination type (default `Dedicated`); a setting without a name is `diag-<name>` |
| `enable_telemetry` | accepted; the chart sends no telemetry |

The module sends the classic rule collections (`applicationRuleCollections`,
`natRuleCollections`, `networkRuleCollections`) and `threatIntelMode` as
placeholders and ignores them after, so rules made outside it survive. ASO
sends neither and cannot ignore a property: an update made by ASO drops
classic rules made outside it, as any PUT without them does. Keep rules in
a firewall policy.

### Not module inputs

| Value | Renders |
| --- | --- |
| `subscription_id` | the subscription of `resource_group_name` when it is a name and `parent_id` is not set: ASO's owner is a resource ID |
| `names.azureFirewall` | the firewall's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name`, never of a name under `names`; checked against the 80-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

### Refused when set

| Variable | Kind | Why |
| --- | --- | --- |
| `ignore_body_changes` | gap | ASO applies every property it is given and cannot leave a path to another writer |
| `resource_types` | by-design | ASO's kinds fix the API versions (`AzureFirewall` 2025-03-01) |
| `retry` | by-design | ASO retries every failed request itself |
| `timeouts`, `firewall_timeouts` | by-design | ASO has no per-request timeouts; Bundt sets a component's time limit |

## Outputs

| Output | From |
| --- | --- |
| `name` | the firewall's `azureName` |
| `resource_id` | its `status.id` |

Not outputs: `private_ip_address`, because ASO's `AzureFirewall` status
gives an IP configuration's ID only, not its private address (a hub
firewall's is in `status.hubIPAddresses`, a network firewall's nowhere);
and `resource`, the module's azurerm-shaped compatibility object, whose IP
configurations need that address.

## From Terraform

A module block's arguments are the values, plus `subscription_id` when
`resource_group_name` is a name and `parent_id` is not set. ASO adopts a
firewall that exists when an object with its name is applied, so keep the
name and leave `namePrefix` empty; set `deletion_policy: ABANDON` for the
first apply, `terraform state rm` the module, then remove `ABANDON`. Move
classic rule collections into a firewall policy first (above).

## Upstream

Ported from the Azure Verified Module
[`avm-res-network-azurefirewall`](https://github.com/Azure/terraform-azurerm-avm-res-network-azurefirewall/tree/v0.5.0)
at v0.5.0 (`e88c8db2`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-network-azurefirewall`: render cases `basic`,
`deprecated`, `full`, `hub`, `names` and `mock`, each validated against ASO
v2.22.0's CRD schemas and aso-extensions' `ManagementLock` CRD, and the
refusals in `tests/*.fail.yaml`. `task test-live-azure` (case `afw`)
applies a zoneless Basic firewall in a network with its two subnets and two
public IPs, which the case makes beside it, evaluates the outputs, deletes
them all and checks Azure no longer has them: passed on 2026-11-13 (run
`cat1113040454ba`, 6 objects). `task test-mock-azure` applies
`tests/mock.values.yaml` to aso-extensions' fake cloud: passed on
2026-11-13, the firewall and its lock Ready and deleted, the outputs
evaluated.

## Changes

- **0.1.0** (2026-11-13): the port.
