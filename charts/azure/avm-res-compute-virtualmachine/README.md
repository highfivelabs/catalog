# avm-res-compute-virtualmachine

An Azure virtual machine with the network interfaces, public IPs and data
disks it makes, its extensions, run commands, shutdown schedules and
maintenance assignments, and its locks, role assignments and diagnostic
settings, as Azure Service Operator (ASO) and aso-extensions objects. A
port of the Azure Verified Module
[`avm-res-compute-virtualmachine`](https://github.com/Azure/terraform-azurerm-avm-res-compute-virtualmachine/tree/a6e951bdebcf50656a1fa29881fcc5a4c87e7a77)
at v0.21.0 (`a6e951bd`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-compute-virtualmachine`
(`package.yaml`). Checked against ASO v2.22.0's CRDs and aso-extensions'
copied CRDs (`crds/aso-extensions`).

## Example

```yaml
name: vm-example
location: eastus2
resource_group_name: rg-example
subscription_id: <subscription>
zone: "1"
os_type: Linux
sku_size: Standard_B2s
encryption_at_host_enabled: false
source_image_reference: {publisher: Canonical, offer: ubuntu-24_04-lts, sku: server, version: latest}
account_credentials:
  admin_credentials: {ssh_keys: ["ssh-ed25519 AAAA..."], generate_admin_password_or_ssh_key: false}
network_interfaces:
  nic0:
    name: vm-example-nic
    ip_configurations:
      ipc0: {name: ipconfig1, private_ip_subnet_resource_id: <subnet ID>}
```

renders the `VirtualMachine` `vm-example` and the `NetworkInterface`
`vm-example-nic` it uses (`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azurerm_linux_virtual_machine.this` | `os_type` Linux | aso-extensions' `VirtualMachine` (`compute.azure.hfl.dev/v20250401`), `virtual_machine`, owned by the resource group |
| `azurerm_windows_virtual_machine.this` | `os_type` Windows | the same, with a Windows OS profile (none with `os_disk_attach_mode`) |
| `azurerm_network_interface` and its `*_association` resources | one per `network_interfaces` entry | `NetworkInterface` (`network.azure.com/v20250301`), `network_interface:<key>`; the associations are its fields (`networkSecurityGroup`, and per IP configuration `applicationSecurityGroups`, `loadBalancerBackendAddressPools`, `loadBalancerInboundNatRules`, `applicationGatewayBackendAddressPools`) |
| `azurerm_public_ip` | an IP configuration's `create_public_ip_address` | `PublicIPAddress` (`network.azure.com/v20250301`), `public_ip:<nic key>-<ip configuration key>` |
| `azurerm_managed_disk` | one per `data_disk_managed_disks` entry | `Disk` (`compute.azure.com/v20240302`), `data_disk:<key>` |
| `azurerm_virtual_machine_data_disk_attachment` | each managed and existing data disk | an entry of the machine's `storageProfile.dataDisks` |
| `module.extension*` | one per `extensions` entry | `VirtualMachinesExtension` (`compute.azure.com/v20220301`), `extension:<key>` |
| `module.run_command*` | one per `run_commands` entry | aso-extensions `VirtualMachinesRunCommand` (`compute.azure.hfl.dev/v20220301`), `run_command:<key>` |
| `azurerm_dev_test_global_vm_shutdown_schedule` | one per `shutdown_schedules` entry | aso-extensions `Schedule` (`devtestlab.azure.hfl.dev/v20180915`), `shutdown_schedule:<key>`, named `shutdown-computevm-<machine>` |
| `azapi_resource.this_maintenance_configuration_assignment` | one per `maintenance_configuration_resource_ids` entry | aso-extensions `ConfigurationAssignment` (`maintenance.azure.hfl.dev/v20230401`), `maintenance_configuration_assignment:<key>` |
| `azurerm_management_lock` (machine, interface, data disk, public IP) | `lock`, an entry's `lock_level`, `public_ip_configuration_details.lock_level` | aso-extensions `ManagementLock`, `lock`, `<object id>/lock` |
| `azurerm_role_assignment` (machine, interface, data disk) | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`) |
| `azurerm_role_assignment.system_managed_identity` | one per `role_assignments_system_managed_identity` entry | `RoleAssignment` at the entry's scope, `system_managed_identity_role_assignment:<key>`, its principal read from the ConfigMap `<release>-vm-identity` the machine exports (`operatorSpec.configMapExpressions`, `self.status.identity.principalId`) |
| `azurerm_monitor_diagnostic_setting` (machine, interface) | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`) |
| `random_password`, `tls_private_key`, `azurerm_key_vault_secret`, `azurerm_backup_protected_vm`, telemetry | never | refused or not ported (below) |

ASO's `VirtualMachine` is at ARM API version 2022-03-01, older than
azurerm's. The chart renders aso-extensions' `VirtualMachine`
(`compute.azure.hfl.dev/v20250401`, beside ASO's under its name;
aso-extensions `docs/plan.md` §8 open question 11) always, which carries
`disk_controller_type` (`storageProfile.diskControllerType`) and
`bypass_platform_safety_checks_on_user_schedule_enabled: true`
(`patchSettings.automaticByPlatformSettings.bypassPlatformSafetyChecksOnUserSchedule`,
with `patch_mode: AutomaticByPlatform`, as azurerm requires). The machine names its interfaces and
managed data disks by ARM ID, and the extensions, run commands, shutdown
schedules, maintenance assignments, lock, role assignments and diagnostic
settings own or target it by ARM ID (aso-extensions' kinds resolve ASO's
by ARM ID; ASO's children name ASO's `VirtualMachine`). The other fields
added since 2022-03-01 are the gaps below.

## Moving from an earlier version

From this version the chart always renders aso-extensions' `VirtualMachine`
(`compute.azure.hfl.dev/v20250401`), never ASO's (`compute.azure.com/v20220301`), so setting or clearing a newer field
never swaps the object's kind. That needs aso-extensions' manager and CRDs
installed beside Azure Service Operator (`docs/azure.md`, "8. Charts";
aso-extensions pin `ASOX_COMMIT`). For a deployment made by an earlier
version, which rendered ASO's kind, the upgrade replaces the Kubernetes
object with one of the other kind under the same name in Azure. Do it
once, with `deletion_policy: ABANDON`: apply the new version with
`ABANDON` (the old object is detached, and the new one adopts the machine),
check it is Ready, then remove `ABANDON`. Without it, the old object's
delete deletes the machine in Azure.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`), except where noted.

| Module input | ASO |
| --- | --- |
| `name`, `location`, `resource_group_name` (with `subscription_id`, or a group ID), `zone` | `azureName`, `location`, `owner`, `zones` |
| `sku_size`, `source_image_reference`, `source_image_resource_id`, `os_disk` | `hardwareProfile.vmSize`, `storageProfile.imageReference`, `storageProfile.osDisk` |
| `os_disk_attach_mode`, `os_managed_disk_id` | `osDisk.createOption: Attach` with `managedDisk.reference`; no OS profile |
| `account_credentials.admin_credentials.username`, `admin_username` | `osProfile.adminUsername` (the module's precedence) |
| `account_credentials.admin_credentials.ssh_keys`, `admin_ssh_keys` | `linuxConfiguration.ssh.publicKeys` (path `/home/<user>/.ssh/authorized_keys`) |
| `account_credentials.admin_credentials.password`, `admin_password` | `osProfile.adminPassword` (the module's precedence) on Windows, and on Linux with password sign-in, as a reference to a Kubernetes Secret, `{secretName, key}` ([secrets](../../../docs/secrets.md)); a string is refused, and the catalog never generates one |
| `account_credentials.password_authentication_disabled`, `disable_password_authentication` | `linuxConfiguration.disablePasswordAuthentication` (false needs a password reference) |
| `enable_automatic_updates`, `hotpatching_enabled`, `timezone`, `winrm_listeners` (Windows) | `windowsConfiguration.enableAutomaticUpdates`, `.patchSettings.enableHotpatching`, `.timeZone`, `.winRM.listeners`; null here takes the module's default (true, false), and on Linux they are ignored, as in the module |
| `computer_name`, `custom_data`, `allow_extension_operations`, `secrets`, `provision_vm_agent`, `patch_mode`, `patch_assessment_mode`, `reboot_setting` | `osProfile` and `linuxConfiguration` or `windowsConfiguration` (`patch_mode` defaults to `AutomaticByOS` on Windows, as azurerm; a Windows `computer_name` is at most 15 characters) |
| `user_data`, `license_type`, `plan`, `platform_fault_domain`, `priority`, `eviction_policy` and `max_bid_price` (with Spot only, as azurerm), `extensions_time_budget` | the fields of the same meaning |
| `availability_set_resource_id`, `capacity_reservation_group_resource_id`, `dedicated_host_resource_id`, `dedicated_host_group_resource_id`, `proximity_placement_group_resource_id`, `virtual_machine_scale_set_resource_id` | `*.reference.armId` |
| `boot_diagnostics`, `boot_diagnostics_storage_account_uri` | `diagnosticsProfile.bootDiagnostics` |
| `encryption_at_host_enabled`, `secure_boot_enabled`, `vtpm_enabled`, `os_disk.security_encryption_type` | `securityProfile` (TrustedLaunch or ConfidentialVM, as azurerm sets it) |
| `edge_zone` | `extendedLocation` on the machine, interfaces, public IPs and disks |
| `gallery_applications`, `termination_notification`, `vm_additional_capabilities`, `managed_identities` | `applicationProfile`, `scheduledEventsProfile`, `additionalCapabilities`, `identity` |
| `network_interfaces` | the interfaces; empty is the module's default interface (`templates/_vm.tpl`, since Helm would merge a map default) |
| `public_ip_configuration_details` | each created public IP |
| `data_disk_managed_disks`, `data_disk_existing_disks` | the disks and the machine's `dataDisks` |
| `extensions`, `run_commands`, `shutdown_schedules`, `maintenance_configuration_resource_ids` | their objects |
| `lock`, `role_assignments`, `role_assignments_system_managed_identity`, `diagnostic_settings`, `tags` | the AVM interfaces |
| `enable_telemetry` | accepted; nothing is sent |

**Refused** (`upstream.yaml`): generating an SSH key pair or a password
(give public keys or a password reference: the catalog never generates a
secret), writing one to Key Vault (`account_credentials.key_vault_configuration`,
`generated_secrets_key_vault_secret_config`), `run_commands_secrets`, an
extension's `protected_settings` (its `protected_settings_from_key_vault`
is mapped), and `additional_unattend_contents` (an unattend file can carry
a password, and the kind takes it only in plain text). Gaps: `azure_backup_configurations` (no kind
for a Recovery Services protected item), an extension's
`provision_after_extensions` and a run command's managed identities
(newer than ASO's `VirtualMachinesExtension` and aso-extensions'
`VirtualMachinesRunCommand` API version, 2022-03-01). `timeouts` by design. The
module's `deploy_sequence` is accepted and has no effect: ASO reconciles
every child once the machine is Ready.

## Outputs

`resource_id`, `name`, `admin_username`, `admin_ssh_keys`,
`system_assigned_mi_principal_id`, `data_disks`, `network_interfaces`,
`public_ips` (each object's id and name, a public IP's address too, not
the whole azurerm object) and `virtual_machine_azurerm` (id, identity,
virtual_machine_id, private and public IP addresses). Not provided:
`admin_password` and `admin_generated_ssh_private_key` (secret values the
chart never makes), `resource` and `virtual_machine` (the whole azurerm
object).

## Tests

Render: `tests/*.values.yaml` against `tests/golden`, `kubeconform
-strict`, and the refusals in `tests/*.fail.yaml`; `newer` renders
aso-extensions' kind, `windows` a Windows machine with its admin password
from a Secret, `linux-password` Linux password sign-in. Fake cloud:
`tests/mock.values.yaml`, `tests/mock-newer.values.yaml` and
`tests/mock-windows.values.yaml` (a Windows machine, its password from a
Secret the run makes) (`hack/azure-mock.sh`). 0.4.0 (run
`off-catalog-1114093250-22553`, 2026-11-14, stock ASO v2.22.0 and
aso-extensions' manager at `8d7f8c2`): `mock` (5 objects), `mock-newer`
(6) and `mock-windows` (the machine and its interface, the admin password
a reference to a Secret the run made with a random value) Ready and
deleted, the outputs evaluated. The first run (`off-catalog-1114091618-1539`)
had every object Ready and deleted, but the Windows case's outputs failed:
`admin_ssh_keys` read `linuxConfiguration`, which a Windows machine has
not (fixed in `package.yaml`). Live: the `vm` case of
`hack/azure-live.sh` (`docs/azure.md`, "8. Charts").

## Changes

- **0.4.0** (2026-11-14): the admin password
  (`account_credentials.admin_credentials.password`, `admin_password`) is
  mapped as a reference to a Kubernetes Secret, `{secretName, key}`
  (docs/secrets.md, the builder's decision), so a Windows machine renders
  its OS profile (with `enable_automatic_updates`, `hotpatching_enabled`,
  `timezone` and `winrm_listeners`) and a Linux one can use password
  sign-in. Generating a password or key stays refused;
  `additional_unattend_contents` is refused because its content is plain
  text in the kind.
- **0.3.0** (2026-11-14): always aso-extensions' `VirtualMachine` (the
  builder's choice), its interfaces and disks always by ARM ID. Moving from
  an earlier version: above.
- **0.2.0** (2026-11-13): `disk_controller_type` and
  `bypass_platform_safety_checks_on_user_schedule_enabled` are mapped: they
  render aso-extensions' `VirtualMachine` (`compute.azure.hfl.dev/v20250401`,
  aso-extensions `8d7f8c2`) in place of ASO's.
- **0.1.0** (2026-11-13): the port.
