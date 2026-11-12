# avm-res-network-networksecuritygroup

An Azure network security group with its security rules, and its lock,
role assignments and diagnostic settings, as Azure Service Operator (ASO)
objects. A port of the Azure Verified Module
[`avm-res-network-networksecuritygroup`](https://github.com/Azure/terraform-azurerm-avm-res-network-networksecuritygroup/tree/c5283612e428c44229a54d1278f184d5203e322b)
at v0.6.0 (`c5283612`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-network-networksecuritygroup`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

## Example

```yaml
name: nsg-example
location: eastus2
parent_id: /subscriptions/<id>/resourceGroups/rg-example
security_rules:
  https:
    name: allow-https
    access: Allow
    direction: Inbound
    priority: 100
    protocol: Tcp
    source_address_prefix: "*"
    source_port_range: "*"
    destination_address_prefix: "*"
    destination_port_range: "443"
```

renders the ASO `NetworkSecurityGroup` `nsg-example` in the group and its
`NetworkSecurityGroupsSecurityRule` `allow-https`
(`tests/golden/basic.yaml`). A subnet takes the group by its `resource_id`
output (`avm-res-network-virtualnetwork`'s `subnets.<key>.network_security_group.id`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.this` (`Microsoft.Network/networkSecurityGroups`) | always | `NetworkSecurityGroup` (`network.azure.com/v20250301`), `network_security_group`, owned by `parent_id` |
| `azapi_resource.security_rules` (`.../securityRules`) | one per `security_rules` entry | `NetworkSecurityGroupsSecurityRule`, `security_rule:<key>`, owned by the group |
| `azapi_resource.lock` | `lock` set | `ManagementLock` (aso-extensions), `lock` |
| `azapi_resource.role_assignments` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `azapi_resource.diagnostic_settings` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` |
| `time_sleep.lock_removal`, telemetry | never | not ported: ASO waits on Azure itself |

ASO is at ARM API version 2025-03-01 for groups and rules, newer than the
module's 2024-10-01. ASO's `NetworkSecurityGroup` has no `securityRules`:
the rules are only ever their own objects, which is what the module
arranges by always ignoring the group's `securityRules`. The module's
`flushConnection: false` is a placeholder it never manages; the chart
leaves it to Azure as well.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`).

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` |
| `parent_id` (required) | `owner.armId` |
| `tags` | `spec.tags` of the group |
| `security_rules` | one rule each: `name` is `azureName`; `access`, `direction`, `priority`, `protocol`, `description`, the source and destination address prefixes, port ranges (sets sorted, as Terraform's) and application security groups (`reference.armId`). The module's empty lists for unset prefixes and ranges are left out. A rule's `timeouts` is refused |
| `lock` | the AVM lock interface; `notes` defaults to the module's note for the kind |
| `role_assignments` | the AVM interface; `skip_service_principal_aad_check` without a `principal_type` sends `ServicePrincipal`, as the module does |
| `diagnostic_settings` | the AVM interface, with no metrics (`metric_categories` is accepted and, as in the module, not sent: a group emits none) and `Dedicated` left to Azure, as the module sends it; a setting without a name is `diag-<name>` |
| `enable_telemetry` | accepted; the chart sends no telemetry |
| `ignore_body_changes`, `resource_types`, `retry`, `timeouts` | refused (below) |

The module's validations stop the render with the module's messages: the
name, `parent_id`, rule priorities and protocols, application security
group IDs, the lock kind, and the diagnostic settings' destinations.

### Not module inputs

| Value | Renders |
| --- | --- |
| `names.networkSecurityGroup` | the group's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name`, never of a name under `names` or a rule's; checked against the 80-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

### Refused when set

| Variable | Why |
| --- | --- |
| `ignore_body_changes` (any non-empty list) | ASO applies every property it is given; it cannot leave a path to another writer |
| `resource_types` | ASO's kinds fix the API versions |
| `retry`, `timeouts`, a rule's `timeouts` | ASO retries every failed request itself; Bundt sets a component's time limit |

## Outputs

| Output | From |
| --- | --- |
| `name` | computed from the inputs, as the module sets it |
| `resource_id` | the group's `status.id` |
| `security_rules` | the module's map, keyed like `security_rules`, with its attribute names (unset lists empty, `resource_group_name` from `parent_id`), each rule's `id` from its object's `status.id` |

## From Terraform

A module block's arguments are the values, unchanged. ASO adopts a group
or rule that exists when an object with its name is applied, so keep the
names and leave `namePrefix` empty; set `deletion_policy: ABANDON` for the
first apply, `terraform state rm` the module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-network-networksecuritygroup`](https://github.com/Azure/terraform-azurerm-avm-res-network-networksecuritygroup/tree/v0.6.0)
at v0.6.0 (`c5283612`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-network-networksecuritygroup`: render cases
`basic`, `full`, `names` and `mock`, each validated against ASO v2.22.0's
CRD schemas and aso-extensions' `ManagementLock` CRD, and the refusals in
`tests/*.fail.yaml`. `task test-live-azure` applies it to the Azure
sandbox with Azure Service Operator, evaluates the outputs, deletes it
and checks Azure no longer has it: passed on 2026-11-12. Not yet applied
to the fake cloud (`docs/azure.md`, "8. Charts").

## Changes

- **0.1.0** (2026-11-12): the port.
