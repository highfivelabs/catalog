# avm-res-network-ddosprotectionplan

An Azure DDoS Network Protection plan, with its lock and role assignments,
as Azure Service Operator (ASO) objects. A port of the Azure Verified
Module
[`avm-res-network-ddosprotectionplan`](https://github.com/Azure/terraform-azurerm-avm-res-network-ddosprotectionplan/tree/2d455cb9c6c61e9061730ba8373b103ae6886cbb)
at v0.3.0 (`2d455cb9`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-network-ddosprotectionplan`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

**Cost.** Azure bills a DDoS Network Protection plan from the moment it
is created, about 2,944 USD a month (covering up to 100 public IPs),
whether or not a network uses it. One plan usually serves a whole tenant:
networks in other subscriptions take it by its `resource_id`
(`avm-res-network-virtualnetwork`'s `ddos_protection_plan.id`).

## Example

```yaml
name: ddos-plan
location: eastus2
resource_group_name: rg-ddos
subscription_id: <id>
```

renders the ASO `DdosProtectionPlan` `ddos-plan` in the group
(`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azurerm_network_ddos_protection_plan.this` | always | `DdosProtectionPlan` (`network.azure.com/v20250301`), `ddos_protection_plan`, owned by the resource group |
| `azurerm_management_lock.this` | `lock` set | `ManagementLock` (aso-extensions), `lock` |
| `azurerm_role_assignment.this` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| telemetry | never | not ported |

A plan has no diagnostic settings (the module says so too).

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`). All seven are carried; none is
refused.

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` |
| `resource_group_name` (required) | `owner.armId`: `/subscriptions/<subscription_id>/resourceGroups/<resource_group_name>`, or `resource_group_name` itself when it is a resource group's ID |
| `tags` | `spec.tags` |
| `lock` | the AVM lock interface (`lock-<kind>` or `lock.name`), with the module's notes for the kind |
| `role_assignments` | the AVM interface; `skip_service_principal_aad_check` without a `principal_type` sends `ServicePrincipal`, as azurerm does. The module's azurerm resource drops `description` and `principal_type`; ASO sends them |
| `enable_telemetry` | accepted; the chart sends no telemetry |

### Not module inputs

| Value | Renders |
| --- | --- |
| `subscription_id` | the subscription of `resource_group_name` when that is a name: the module's azurerm provider knows its subscription, ASO's owner is a resource ID |
| `names.ddosProtectionPlan` | the plan's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name`, never of a name under `names`; checked against the 80-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

## Outputs

| Output | From |
| --- | --- |
| `name` | the plan's `azureName` |
| `resource_id` | the plan's `status.id` |
| `resource` | the plan as azurerm's object, with the attributes ASO's status has: `id`, `name`, `location`, `resource_group_name`, `tags`, `virtual_network_ids` (the networks that use it; empty while none does) |

All three of the module's outputs.

## From Terraform

A module block's arguments are the values, plus `subscription_id` when
`resource_group_name` is a name. ASO adopts a plan that exists when an
object with its name is applied, so keep the name and leave `namePrefix`
empty; set `deletion_policy: ABANDON` for the first apply, `terraform
state rm` the module, then remove `ABANDON`. Adopting an existing plan
costs nothing more; making a new one starts its bill.

## Upstream

Ported from the Azure Verified Module
[`avm-res-network-ddosprotectionplan`](https://github.com/Azure/terraform-azurerm-avm-res-network-ddosprotectionplan/tree/v0.3.0)
at v0.3.0 (`2d455cb9`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-network-ddosprotectionplan`: render cases
`basic`, `full`, `names` and `mock`, each validated against ASO v2.22.0's
CRD schemas and aso-extensions' `ManagementLock` CRD, and the refusals in
`tests/*.fail.yaml`.

Fake cloud (`task test-mock-azure`, `hack/azure-mock.sh`; stock ASO and
aso-extensions' manager against its fakearm at `b9beb5b`): `tests/mock.values.yaml` passed in run
`off-catalog-1113075710-7948` on 2026-11-13: the plan and its lock Ready
and deleted, outputs evaluated.

**Not applied live, by design.** A DDoS Network Protection plan is billed
at about 2,944 USD a month from its creation (about 4 USD an hour), far
above the sandbox's limit of about 1 USD an hour, so `hack/azure-live.sh` has no case for it.
Its renders and the fake cloud are its tests.

## Changes

- **0.1.0** (2026-11-13): the port.
