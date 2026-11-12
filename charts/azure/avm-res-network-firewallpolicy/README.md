# avm-res-network-firewallpolicy

An Azure firewall policy with its rule collection groups, and its lock,
role assignments and diagnostic settings, as Azure Service Operator (ASO)
objects. A port of the Azure Verified Module
[`avm-res-network-firewallpolicy`](https://github.com/Azure/terraform-azurerm-avm-res-network-firewallpolicy/tree/8580240f33fee12f92ef4834a9574ab0481686c5)
at v0.3.4 (`8580240f`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`), its `rule_collection_groups` submodule included. Bundt
Package `azure-avm-res-network-firewallpolicy` (`package.yaml`). Checked
against ASO v2.22.0's CRDs.

## Example

```yaml
name: fwp-example
location: eastus2
resource_group_name: rg-example
subscription_id: <id>
firewall_policy_sku: Standard
rule_collection_groups:
  core:
    name: rcg-core
    priority: 200
    network_rule_collection:
      - name: dns
        priority: 400
        action: Allow
        rule:
          - {name: dns, protocols: [UDP], source_addresses: [10.0.0.0/8], destination_addresses: [168.63.129.16], destination_ports: ["53"]}
```

renders the ASO `FirewallPolicy` `fwp-example` in the group and its
`FirewallPoliciesRuleCollectionGroup` `rcg-core` (`tests/golden/mock.yaml`
is the same shape). An Azure Firewall takes the policy by its
`resource_id` output.

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azurerm_firewall_policy.this` | always | `FirewallPolicy` (`network.azure.com/v20250301`), `firewall_policy`, owned by the resource group |
| `module.rule_collection_groups` (`azurerm_firewall_policy_rule_collection_group.this`) | one per `rule_collection_groups` entry | `FirewallPoliciesRuleCollectionGroup` (`v20250301`), `rule_collection_group:<key>`, owned by the policy |
| `azurerm_management_lock.this` | `lock` set | `ManagementLock` (aso-extensions), `lock` |
| `azurerm_role_assignment.this` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `azurerm_monitor_diagnostic_setting.this` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` |
| telemetry | never | not ported |

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`).

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` |
| `resource_group_name` (required) | `owner.armId`: `/subscriptions/<subscription_id>/resourceGroups/<resource_group_name>`, or `resource_group_name` itself when it is a resource group's ID |
| `firewall_policy_sku` | `sku.tier` (Azure's default, Standard, when unset) |
| `firewall_policy_base_policy_id` | `basePolicy.reference.armId` |
| `firewall_policy_auto_learn_private_ranges_enabled` | `snat.autoLearnPrivateRanges` (`Enabled` or `Disabled`) |
| `firewall_policy_private_ip_ranges` | `snat.privateRanges` |
| `firewall_policy_dns` | `dnsSettings` (`enableProxy`, `servers`) |
| `firewall_policy_explicit_proxy` | `explicitProxy` (`enableExplicitProxy`, `enablePacFile`, `httpPort`, `httpsPort`, `pacFile`, `pacFilePort`) |
| `firewall_policy_identity` | `identity` (`UserAssigned`, the identities by `armId`) |
| `firewall_policy_insights` | `insights` (`isEnabled`, `retentionDays`, `logAnalyticsResources`: the default workspace and one per firewall location) |
| `firewall_policy_intrusion_detection` | `intrusionDetection` (`mode`; `configuration`: `privateRanges`, `signatureOverrides` with `state` as `mode`, `bypassTrafficSettings`) |
| `firewall_policy_sql_redirect_allowed` | `sql.allowSqlRedirect` |
| `firewall_policy_threat_intelligence_mode`, `firewall_policy_threat_intelligence_allowlist` | `threatIntelMode`, `threatIntelWhitelist` (`fqdns`, `ipAddresses`) |
| `firewall_policy_tls_certificate` | `transportSecurity.certificateAuthority` (`keyVaultSecretId`, `name`): the secret's ID, never its value |
| `tags` | `spec.tags` of the policy |
| `lock` | the AVM lock interface, with the module's notes for the kind |
| `role_assignments` | the AVM interface; `skip_service_principal_aad_check` without a `principal_type` sends `ServicePrincipal`, as azurerm does |
| `diagnostic_settings` | the AVM interface; a setting without a name is `diag-<name>` |
| `enable_telemetry` | accepted; the chart sends no telemetry |
| `firewall_policy_timeouts` | refused (below) |

### Not module inputs

| Value | Renders |
| --- | --- |
| `rule_collection_groups` | the `rule_collection_groups` submodule, one call per entry with this policy as its `firewall_policy_id`. An entry takes the submodule's variables without their `firewall_policy_rule_collection_group_` prefix: `name`, `priority`, `application_rule_collection`, `nat_rule_collection`, `network_rule_collection` (each rule as azurerm's, with `destination_fqdns` as `targetFqdns`, `destination_urls` as `targetUrls`, `destination_fqdn_tags` as `fqdnTags`, a NAT rule's `destination_address` as its one `destinationAddresses` entry, NAT's `Dnat` as `DNAT`). Its `timeouts` is refused |
| `subscription_id` | the subscription of `resource_group_name` when that is a name: the module's azurerm provider knows its subscription, ASO's owner is a resource ID |
| `names.firewallPolicy` | the policy's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name`, never of a name under `names` or a group's; checked against the 80-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

### Refused when set

| Variable | Why |
| --- | --- |
| `firewall_policy_timeouts` (and a group's `timeouts`) | Azure Service Operator has no per-request timeouts; Bundt sets a component's time limit |

## Outputs

| Output | From |
| --- | --- |
| `resource_id` | the policy's `status.id` |
| `rule_collection_groups` | the submodule's `resource_id` per entry, keyed like `rule_collection_groups` |

Not an output: `resource`, the module's whole azurerm object.

## From Terraform

A module block's arguments are the values, plus `subscription_id` when
`resource_group_name` is a name; each `rule_collection_groups` module call
becomes an entry. ASO adopts a policy or group that exists when an object
with its name is applied, so keep the names and leave `namePrefix` empty;
set `deletion_policy: ABANDON` for the first apply, `terraform state rm`
the modules, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-network-firewallpolicy`](https://github.com/Azure/terraform-azurerm-avm-res-network-firewallpolicy/tree/v0.3.4)
at v0.3.4 (`8580240f`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-network-firewallpolicy`: render cases `basic`,
`full`, `names` and `mock`, each validated against ASO v2.22.0's CRD
schemas and aso-extensions' `ManagementLock` CRD, and the refusals in
`tests/*.fail.yaml`. `task test-live-azure` (case `fwp`) applies a Basic
policy with one rule collection group to the Azure sandbox with Azure
Service Operator, evaluates the outputs, deletes it and checks Azure no
longer has it: passed on 2026-11-12 (run `cat111223417a80`).
`task test-mock-azure` applies `tests/mock.values.yaml` to aso-extensions'
fake cloud: passed on 2026-11-12, both objects Ready and deleted.

## Changes

- **0.1.0** (2026-11-12): the port.
