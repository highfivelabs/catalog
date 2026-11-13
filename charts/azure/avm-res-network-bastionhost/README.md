# avm-res-network-bastionhost

An Azure Bastion host with the public IP it makes, and its lock, role
assignments and diagnostic settings, as Azure Service Operator (ASO)
objects. A port of the Azure Verified Module
[`avm-res-network-bastionhost`](https://github.com/Azure/terraform-azurerm-avm-res-network-bastionhost/tree/7c7d294caf81377671b99687aa75726e1072002e)
at v0.9.0 (`7c7d294c`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-network-bastionhost`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

## Example

```yaml
name: bas-example
location: eastus2
parent_id: /subscriptions/<id>/resourceGroups/rg-example
ip_configuration:
  subnet_id: /subscriptions/<id>/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet/subnets/AzureBastionSubnet
```

renders a Basic `BastionHost` `bas-example` and the zone-redundant
Standard `PublicIPAddress` `pip-bas-example` it uses
(`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.bastion` (`Microsoft.Network/bastionHosts@2024-05-01`) | `sku` other than Developer | `BastionHost` (`network.azure.com/v20250301`), `bastion_host`, owned by `parent_id` |
| `azapi_resource.bastion_developer` | `sku: Developer` | the same `BastionHost`, with only `virtualNetwork` |
| `module.public_ip_address` (avm-res-network-publicipaddress 0.2.0) | `ip_configuration.create_public_ip` (default true) | `PublicIPAddress` (`v20250301`), `public_ip`: Standard, static, IPv4, the host's `zones`, in `parent_id`'s group, as the module calls it |
| `azurerm_management_lock.this`, `.pip` | `lock` set | `ManagementLock` (aso-extensions), `lock` (`lock-<kind>` by default) and `pip-lock` (`lock-<kind>-pip`) |
| `azurerm_role_assignment.this`, `.pip` | one per entry, on the host and on the made public IP | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>`, `pip-role-assignment-<key>` |
| `azurerm_monitor_diagnostic_setting.this` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` |
| `data.azurerm_public_ip.this` | never | not needed: an existing address goes by its ID (`public_ip_address_id`) |
| telemetry | never | not ported |

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`), and the module's validations stop
the render with its messages.

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` |
| `parent_id` (required) | `owner.armId`, a resource group's ID |
| `sku` | `sku.name` (Basic, Standard, Developer or Premium) |
| `copy_paste_enabled` | `disableCopyPaste` (its negation) |
| `file_copy_enabled`, `ip_connect_enabled`, `kerberos_enabled`, `private_only_enabled`, `session_recording_enabled`, `shareable_link_enabled`, `tunneling_enabled` | `enableFileCopy`, `enableIpConnect`, `enableKerberos`, `enablePrivateOnlyBastion`, `enableSessionRecording`, `enableShareableLink`, `enableTunneling` |
| `scale_units` | `scaleUnits` |
| `zones` | `zones` of the host and of the public IP it makes |
| `ip_configuration` | `ipConfigurations[0]`: `name` (default `ipconfig-<name>`), `subnet`, a dynamic private address, `publicIPAddress` (the made address, or `public_ip_address_id`; none when private only); `create_public_ip`, `public_ip_address_name` (default `pip-<name>`), `public_ip_tags` and `public_ip_merge_with_module_tags` shape the made address |
| `virtual_network_id` | `virtualNetwork` (Developer only) |
| `tags` | `spec.tags` of the host; of the public IP as the module merges them |
| `lock` | the AVM lock interface, on the host and the public IP |
| `role_assignments` | the AVM interface, on the host and the public IP |
| `diagnostic_settings` | the AVM interface; a setting without a name is `diag-<name>`; the destination type is left to Azure, as the module leaves it |
| `enable_telemetry` | accepted; the chart sends no telemetry |

The module's precondition that an existing public IP's zones match the
host's is not checked here (it reads the address from Azure); Azure
refuses a mismatch.

### Not module inputs

| Value | Renders |
| --- | --- |
| `names.bastionHost` | the host's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name` and of the made public IP's name, never of a name under `names`; checked against the 80-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

Nothing is refused.

## Outputs

| Output | From |
| --- | --- |
| `name` | the host's `azureName` |
| `resource_id` | the host's `status.id` |
| `dns_name` | the host's `status.dnsName` |

Not an output: `resource`, the module's whole azapi object.

## From Terraform

A module block's arguments are the values. ASO adopts a host or public IP
that exists when an object with its name is applied, so keep the names and
leave `namePrefix` empty; set `deletion_policy: ABANDON` for the first
apply, `terraform state rm` the module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-network-bastionhost`](https://github.com/Azure/terraform-azurerm-avm-res-network-bastionhost/tree/v0.9.0)
at v0.9.0 (`7c7d294c`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-network-bastionhost`: render cases `basic`,
`full`, `developer`, `private`, `names` and `mock`, each validated against
ASO v2.22.0's CRD schemas and aso-extensions' `ManagementLock` CRD, and the
refusals in `tests/*.fail.yaml` (the module's validations).
`task test-live-azure` (case `bas`) applies a Basic host with the public IP
it makes, in an AzureBastionSubnet of a network the case also applies, to
the Azure sandbox with Azure Service Operator, evaluates the outputs (the
host's DNS name among them), deletes it and checks Azure no longer has it:
passed on 2026-11-13 (run `cat1113013124a2`). `task test-mock-azure`
applies `tests/mock.values.yaml` to aso-extensions' fake cloud: passed on
2026-11-13, both objects Ready and deleted, the outputs evaluated.

## Changes

- **0.1.0** (2026-11-12): the port.
