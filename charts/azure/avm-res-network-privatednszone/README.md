# avm-res-network-privatednszone

An Azure private DNS zone with its records and virtual network links, and
its lock and role assignments, as Azure Service Operator (ASO) objects. A
port of the Azure Verified Module
[`avm-res-network-privatednszone`](https://github.com/Azure/terraform-azurerm-avm-res-network-privatednszone/tree/97ed94c12535fac61c3bad293754ba408b8a8d56)
at v0.6.0 (`97ed94c1`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-network-privatednszone`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

## Example

```yaml
domain_name: privatelink.example.internal
parent_id: /subscriptions/<id>/resourceGroups/rg-example
a_records:
  web: {name: web, ttl: 300, ip_addresses: [10.0.0.4]}
virtual_network_links:
  hub:
    name: hub-link
    virtual_network_id: /subscriptions/<id>/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-hub
```

renders the ASO `PrivateDnsZone` `privatelink.example.internal`, its A
record `web` and its link `hub-link` to the network
(`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.private_dns_zone` (`Microsoft.Network/privateDnsZones`) | always | `PrivateDnsZone` (`network.azure.com/v1api20240601`), `private_dns_zone`, location `global`, owned by `parent_id` |
| `module.a_record`, `aaaa_record`, `cname_record`, `mx_record`, `ptr_record`, `srv_record`, `txt_record` | one per entry of `a_records` ... `txt_records` | `PrivateDnsZones{A,AAAA,CNAME,MX,PTR,SRV,TXT}Record`, `<type>_record:<key>`, owned by the zone |
| `module.virtual_network_links` | one per entry | `PrivateDnsZonesVirtualNetworkLink`, `virtual_network_link:<key>`, owned by the zone |
| `azapi_resource.lock` | `lock` set | `ManagementLock` (aso-extensions), `lock` |
| `azapi_resource.role_assignments` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `azapi_update_resource.private_dns_zone_soa_record` | `soa_record` | refused (below) |
| `time_sleep`, telemetry | never | not ported |

ASO and the module are both at ARM API version 2024-06-01.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`), but for `retry` and `timeouts`,
whose module defaults are the module's own settings (null here).

| Module input | ASO |
| --- | --- |
| `domain_name` (required) | the zone's `azureName` |
| `parent_id` (required) | `owner.armId` |
| `tags` | `spec.tags` of the zone |
| `a_records`, `aaaa_records` | `aRecords` (`ipv4Address`), `aaaaRecords` (`ipv6Address`) from `ip_addresses`, else `records` (sorted, unique) |
| `ptr_records` | `ptrRecords` (`ptrdname`) from `domain_names`, else `records` |
| `cname_records` | `cnameRecord.cname` from `cname`, else `record` |
| `mx_records`, `srv_records`, `txt_records` | `mxRecords`, `srvRecords`, `txtRecords` from the `records` map's values, in key order; an MX record's name defaults to `@` |
| every record's `name`, `ttl` | `azureName`, `ttl` |
| `virtual_network_links` | one link each: `name` (or `vnetlinkname`), `virtualNetwork.reference.armId` from `virtual_network_id` (or `vnetid`), `registrationEnabled` from `registration_enabled` (or `autoregistration`, else false), `resolutionPolicy` only when `private_dns_zone_supports_private_link`, the entry's own `tags` |
| `lock` | the AVM lock interface: named `lock-<domain_name>` unless named, no notes (as the module's) |
| `role_assignments` | the AVM interface |
| `role_assignment_name_use_random_uuid` | `true` (the default) accepted: ASO gives each assignment a stable UUID of its own. `false` is refused |
| `location`, `enable_telemetry` | accepted: they serve only the module's telemetry, which the chart does not send |
| `soa_record`, `retry`, `timeouts` | refused (below) |

The module's validations stop the render with the module's messages: an
A, AAAA or PTR record's addresses or names, a CNAME's target, a link's
name, network and name length, and `parent_id`.

### Not module inputs

| Value | Renders |
| --- | --- |
| `names`, `namePrefix` | kept so every Azure chart takes them, and change nothing: the zone's name is the domain it serves, which a prefix would change, and every other name is inside the zone |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

### Refused when set

| Variable | Why |
| --- | --- |
| `soa_record` | the zone's SOA record (`Microsoft.Network/privateDnsZones/SOA`) exists with the zone and is only updated; ASO has a kind for every other record type, none for SOA (gap) |
| `retry`, `timeouts` | ASO retries every failed request itself; Bundt sets a component's time limit |
| `role_assignment_name_use_random_uuid: false` | ASO names each assignment with its own stable UUID; the module's legacy deterministic names cannot be given |

## Outputs

| Output | From |
| --- | --- |
| `name` | `domain_name` |
| `resource_id` | the zone's `status.id` |
| `a_record_outputs` ... `txt_record_outputs` | `{<key>: {id, fqdn}}` from each record's status, as the module builds them |
| `virtual_network_link_outputs` | `{<key>: {id}}` |
| `soa_record_outputs` | `{}`, as the module's without `soa_record` |

Not an output: `resource`, the module's whole azapi object.

## From Terraform

A module block's arguments are the values, unchanged. ASO adopts a zone,
record or link that exists when an object with its name is applied; set
`deletion_policy: ABANDON` for the first apply, `terraform state rm` the
module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-network-privatednszone`](https://github.com/Azure/terraform-azurerm-avm-res-network-privatednszone/tree/v0.6.0)
at v0.6.0 (`97ed94c1`, MIT), its record and link submodules included.
[`upstream.yaml`](upstream.yaml) records the repository, release, commit,
licence and the date last synced.

## Tests

`task test CHART=avm-res-network-privatednszone`: render cases `basic`,
`full` and `mock`, each validated against ASO v2.22.0's CRD schemas and
aso-extensions' `ManagementLock` CRD, and the refusals in
`tests/*.fail.yaml`. Not yet applied live or to the fake cloud
(`docs/azure.md`, "8. Charts").

## Changes

- **0.1.0** (2026-11-12): the port.
