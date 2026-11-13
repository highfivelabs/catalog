# avm-ptn-network-private-link-private-dns-zones

The private DNS zones Azure Private Link services resolve in (the module's
list of 85, with the region put in the regional ones), each linked to
virtual networks, and a lock and role assignments on the resource group,
as Azure Service Operator (ASO) objects. A port of the Azure Verified
Module pattern
[`avm-ptn-network-private-link-private-dns-zones`](https://github.com/Azure/terraform-azurerm-avm-ptn-network-private-link-private-dns-zones/tree/4d2214f162806d48ea9a157de4b904f879fc61d4)
at v0.23.2 (`4d2214f1`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`), with the data of the two modules it calls:
`avm-res-network-privatednszone` 0.4.3 (the zone and its links) and
`avm-utl-regions` 0.12.0 (region names and codes). Bundt Package
`azure-avm-ptn-network-private-link-private-dns-zones` (`package.yaml`).
Checked against ASO v2.22.0's CRDs.

## Example

```yaml
location: eastus2
parent_id: /subscriptions/<id>/resourceGroups/rg-dns
virtual_network_link_default_virtual_networks:
  hub: {virtual_network_resource_id: /subscriptions/<id>/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-hub}
```

renders 89 ASO `PrivateDnsZone`s (the module's 85 zones, the partitioned
Static Web Apps zone made five times), `privatelink.eastus2.azurecontainerapps.io`
and `privatelink.eus2.backup.windowsazure.com` among them, and one
`PrivateDnsZonesVirtualNetworkLink` per zone to `vnet-hub`, named
`vnet_link-<zone key>-hub` (`tests/golden/default.yaml` has the zones).
Narrow the list with `private_link_private_dns_zones` (a map replaces the
default), `private_link_excluded_zones` or the regex filter.

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `module.avm_res_network_privatednszone` (`azapi_resource.private_dns_zone`) | one per zone | `PrivateDnsZone` (`network.azure.com/v1api20240601`), `private_dns_zone:<zone key>`, location `global`, owned by the resource group |
| its `module.virtual_network_links` | one per zone and link | `PrivateDnsZonesVirtualNetworkLink` (`network.azure.com/v1api20240601`), `virtual_network_link:<zone key>/<link key>`, owned by the zone, registration off |
| `azapi_resource.lock` | `lock` set | `ManagementLock` (aso-extensions), `lock`, on the resource group, named `lock-<resource group name>` unless given |
| `azapi_resource.role_assignments` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>`, on the resource group |
| `module.regions` (`avm-utl-regions`) | never | a table in the chart (`templates/_data.tpl`, below) |
| telemetry | never | not ported |

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`), with the module's validations. The
chart computes the zones and links in the template as the module's
`locals.tf` does (`templates/main.yaml` lists the steps).

| Module input | ASO |
| --- | --- |
| `location` (required) | a region's name or display name; its name fills `{regionName}` and its code (`eus2`, `uks`) `{regionCode}` in the zone names; `${location}` in link names is the value as given |
| `parent_id` (required) | `owner.armId` of every zone, the lock and the role assignments |
| `private_link_private_dns_zones` | the zones: null (the default) is the module's list of 85 (`templates/_data.tpl`); a map replaces it, `{}` makes none. An entry's `zone_name` is the zone's `azureName`, its placeholders filled; `custom_iterator` makes the zone once per replacement value (key `<key>_<value key>`, `{<placeholder>}` replaced with the value's key); `private_dns_zone_supports_private_link: false` sends no resolution policy on its links; `resolution_policy` is its links' policy unless an override or the link gives one |
| `private_link_private_dns_zones_additional` | more zones of the same shape, an entry replacing one of the same key |
| `private_link_private_dns_zones_regex_filter` | when `enabled`, only zones whose `zone_name` (placeholders unfilled) matches `regex_filter` (default `{regionName}\|{regionCode}`: the regional zones). An invalid regular expression stops the render |
| `private_link_excluded_zones` | zones dropped by key or by `zone_name` (placeholders unfilled) |
| `virtual_network_link_default_virtual_networks`, `virtual_network_link_additional_virtual_networks` | links to every zone, the second winning on a key: `virtualNetwork.reference.armId`, the name template, the resolution policy |
| `virtual_network_link_by_zone_and_virtual_network` | links to one zone, winning over the two above on a key; `name` is the link's name template |
| `virtual_network_link_overrides_by_zone_and_virtual_network`, `virtual_network_link_overrides_by_zone`, `virtual_network_link_overrides_by_virtual_network` | a link's name and resolution policy, in that order of precedence, before the link's own; `enabled: false` in any of them makes no link |
| `virtual_network_link_name_template` | a link's name when nothing above names it (default `vnet_link-${zone_key}-${vnet_key}`); `${zone_key}`, `${vnet_key}`, `${vnet_name}` and `${location}` are filled in it and in every override |
| `virtual_network_link_resolution_policy_default` | the policy when nothing above gives one; sent only for a zone that supports Private Link |
| `tags` | `spec.tags` of every zone and link |
| `lock` | the AVM lock interface on the resource group |
| `resource_group_role_assignments` | the AVM role assignment interface on the resource group: a role by name (ASO resolves it) or ID; ASO names each with a stable UUID, as the module's random UUID |
| `enable_telemetry` | accepted; the chart sends no telemetry |

**Regions.** The module looks the location up in `avm-utl-regions`
0.12.0, which reads the subscription's location list live. The chart has
that module's own data instead, as a table (`plpdz.regions` in
`templates/_data.tpl`): the 62 physical regions of its cached list, by
name and display name, with the codes of its `locals.geo.codes.tf.json`,
and the 13 regions it has a code for but no cached entry (by name only).
A location not in the table stops the render, naming it; a region the
table has without a code (`eastusstg`, `southcentralusstg`) stops it too,
as the module, which puts the code in every zone name, fails there.

### Not module inputs

| Value | Renders |
| --- | --- |
| `names`, `namePrefix` | kept so every Azure chart takes them; no name here takes a prefix (a zone's name is its domain, the rest are named inside it) |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

### Refused when set

| Variable | Kind | Why |
| --- | --- | --- |
| `timeouts` | by-design | ASO has no per-request timeouts; Bundt sets a component's time limit |
| `location` (in part) | by-design | a region newer than `avm-utl-regions` 0.12.0's data (above) |
| `virtual_network_link_name_template` (in part) | by-design | a name template takes the module's four documented placeholders; another Terraform template expression (`${upper(vnet_key)}`, a `%{...}` directive) stops the render, here and in every name override |

## Outputs

| Output | From |
| --- | --- |
| `private_dns_zone_resource_ids` | `{<zone key>: <ARM ID>}`, each zone's `status.id` |
| `private_link_private_dns_zones_map` | the module's final map, read back from the applied zones and links: `{<zone key>: {zone_key, zone_name, virtual_network_links: {<link key>: {virtual_network_id, name, private_dns_zone_supports_private_link, registration_enabled, resolution_policy, tags}}}}`. For a zone that does not support Private Link, `resolution_policy` is null: the link carries none, where the module reports the policy it did not send |
| `resource_group_resource_id` | `parent_id` |

## From Terraform

A module block's arguments are the values. A `$${zone_key}` in a `.tf`
file is `${zone_key}` here. ASO adopts a zone that exists when an object
with its name is applied, so the zones of a module already applied are
taken over as they are; set `deletion_policy: ABANDON` for the first
apply, `terraform state rm` the module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-ptn-network-private-link-private-dns-zones`](https://github.com/Azure/terraform-azurerm-avm-ptn-network-private-link-private-dns-zones/tree/v0.23.2)
at v0.23.2 (`4d2214f1`, MIT). [`upstream.yaml`](upstream.yaml) records
the repository, release, commit, licence and the date last synced. The
default zone list is the module's `variables.tf`; the region table is
`avm-utl-regions` v0.12.0 (`e9d62409`, MIT).

## Tests

`task test CHART=avm-ptn-network-private-link-private-dns-zones`: render
cases `default` (the module's default example: all 89 zones), `exclusions`,
`resolution-policy`, `secondary-region`, `custom`, `granular` and `wide`
(the module's examples, the last two on a few of its zones), `full` and
`mock`, each validated against ASO v2.22.0's CRD schemas and
aso-extensions' `ManagementLock` CRD, and the refusals in
`tests/*.fail.yaml`. `task test-live-azure` (case `pldns`) narrows the zone
list with `private_link_private_dns_zones` to three zones of the module's
list (`privatelink.eastus2.azurecontainerapps.io`, with the region's name;
`privatelink.eus2.backup.windowsazure.com`, with its code;
`privatelink.webpubsub.azure.com`) and links each to a network the case
makes beside it; it stops if the group already has one of the zones, as
ASO would adopt it. Passed on 2026-11-13 in run `cat111308205866`
(offload `off-catalog-1113081629-14160`): 7 objects Ready (the network,
three zones, three links), the outputs evaluated (the zones' IDs and the
module's map), deleted, Azure answering 404. `task test-mock-azure` applies
`tests/mock.values.yaml` (two zones, one link each) to aso-extensions' fake
cloud: passed on 2026-11-13 (offload `off-catalog-1113080244-7256`), 4
objects Ready and deleted, the outputs evaluated.

## Changes

- **0.1.0** (2026-11-13): the port.
