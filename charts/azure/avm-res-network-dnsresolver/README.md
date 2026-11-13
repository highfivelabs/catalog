# avm-res-network-dnsresolver

An Azure DNS Private Resolver in a virtual network, with its inbound and
outbound endpoints, DNS forwarding rulesets, forwarding rules and virtual
network links, and its locks and role assignments, as Azure Service
Operator (ASO) objects. A port of the Azure Verified Module
[`avm-res-network-dnsresolver`](https://github.com/Azure/terraform-azurerm-avm-res-network-dnsresolver/tree/73b1df385505485dee12fc3901756d4994fe9cc8)
at v0.8.0 (`73b1df38`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-network-dnsresolver`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

## Example

```yaml
name: resolver
location: eastus2
resource_group_name: rg-dns
subscription_id: <id>
virtual_network_resource_id: /subscriptions/<id>/resourceGroups/rg-dns/providers/Microsoft.Network/virtualNetworks/vnet-dns
inbound_endpoints:
  inbound1: {name: inbound1, subnet_name: inbound}
outbound_endpoints:
  outbound1: {name: outbound1, subnet_name: outbound}
```

renders the ASO `DnsResolver` `resolver` in the network, its
`DnsResolversInboundEndpoint` `inbound1` and `DnsResolversOutboundEndpoint`
`outbound1` (`tests/golden/basic.yaml`). Each endpoint's subnet is
`<virtual_network_resource_id>/subnets/<subnet_name>`, as in the module:
give the network the subnets first (`avm-res-network-virtualnetwork`, each
at least a /28 and delegated to `Microsoft.Network/dnsResolvers`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azurerm_private_dns_resolver.this` | always | `DnsResolver` (`network.azure.com/v1api20220701`), `dns_resolver`, owned by the resource group |
| `azurerm_private_dns_resolver_inbound_endpoint.this` | one per `inbound_endpoints` entry | `DnsResolversInboundEndpoint`, `inbound_endpoint:<key>`, owned by the resolver |
| `azurerm_private_dns_resolver_outbound_endpoint.this` | one per `outbound_endpoints` entry | `DnsResolversOutboundEndpoint`, `outbound_endpoint:<key>`, owned by the resolver |
| `azurerm_private_dns_resolver_dns_forwarding_ruleset.this` | one per ruleset of an outbound endpoint | `DnsForwardingRuleset`, `forwarding_ruleset:<outbound key>-<ruleset name>`, owned by the resource group, on that endpoint |
| `azurerm_private_dns_resolver_forwarding_rule.this` | one per rule | `DnsForwardingRuleSetsForwardingRule`, `forwarding_rule:<ruleset id>-<rule key>`, owned by the ruleset |
| `azurerm_private_dns_resolver_virtual_network_link.default` | a ruleset with `link_with_outbound_endpoint_virtual_network` (default) | `DnsForwardingRuleSetsVirtualNetworkLink` `default-<ruleset name>` to the resolver's network, `virtual_network_link:<ruleset id>` |
| `azurerm_private_dns_resolver_virtual_network_link.additional` | one per `additional_virtual_network_links` entry | `DnsForwardingRuleSetsVirtualNetworkLink`, `virtual_network_link:<ruleset id>-<key>` |
| `azurerm_management_lock.this`, `.rulesets` | `lock` set | `ManagementLock` (aso-extensions) on the resolver (`lock`) and on each ruleset (`ruleset/<ruleset id>/lock`) |
| `azurerm_role_assignment.dnsresolver`, `.rulesets` | one per entry, on the resolver and on each ruleset | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>`, `ruleset/<ruleset id>/role-assignment-<key>` |
| `terraform_data.outbound` | never | not ported: it makes Terraform replace a ruleset when its endpoint is replaced; ASO updates the ruleset's endpoint reference |
| telemetry | never | not ported |

Every DNS resolver kind is at ARM API version 2022-07-01 in ASO, the
version azurerm sends.

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`). All ten are carried; none is
refused.

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` of the resolver; `location` of every endpoint and ruleset |
| `resource_group_name` (required) | `owner.armId` of the resolver and the rulesets: `/subscriptions/<subscription_id>/resourceGroups/<resource_group_name>`, or `resource_group_name` itself when it is a resource group's ID |
| `virtual_network_resource_id` (required) | the resolver's `virtualNetwork`, the endpoints' subnets (`<id>/subnets/<subnet_name>`) and the default links' network |
| `tags` | `spec.tags` of the resolver; of each endpoint and ruleset as the module merges them (below) |
| `inbound_endpoints` | one endpoint each: `name` (default `in-<key>-dnsResolver-inbound`), `subnet_name`, `private_ip_allocation_method` (default `Dynamic`), `private_ip_address` in its one IP configuration; `tags` and `merge_with_module_tags` |
| `outbound_endpoints` | one endpoint each: `name` (default `out-<key>-dnsResolver-outbound`), `subnet_name`, `tags`, `merge_with_module_tags`; `forwarding_ruleset` (below) |
| `outbound_endpoints.*.forwarding_ruleset` | one ruleset each, on its endpoint: `name` (default `ruleset-<outbound key>-<key>`), `tags`, `merge_with_module_tags`; `link_with_outbound_endpoint_virtual_network` makes the default link; `additional_virtual_network_links` one link each (`name`, default `additional-<outbound key>-<ruleset name>-<6 hex>`; `vnet_id`; `metadata`); `rules` one rule each: its key is its Azure name, `domain_name`, `destination_ip_addresses` (`targetDnsServers`, in address order, each port a number), `enabled` (`forwardingRuleState`), `metadata` |
| `lock` | the AVM lock interface, on the resolver (`lock-<kind>`) and on every ruleset (`lock-<outbound key>-<ruleset name>`), or `lock.name` on each, with the module's notes for the kind |
| `role_assignments` | the AVM interface, on the resolver and on every ruleset, as the module does; `skip_service_principal_aad_check` without a `principal_type` sends `ServicePrincipal`, as azurerm does |
| `enable_telemetry` | accepted; the chart sends no telemetry |

A child's tags, as the module computes them: its own `tags` merged over
the module's when `merge_with_module_tags` (the default), its own alone
when not; with no own `tags`, the module's when `merge_with_module_tags`,
none when not.

The module's validation and maps stop the render with a message: the
resolver's name has no `#`; two rulesets with one key
(`<outbound key>-<ruleset name>`), which the module's map cannot hold;
`virtual_network_resource_id` must be a virtual network's ID.

### Kept as the module has them

Three inputs of the module's type have no effect in the module, and none
here, so a module call converts to the same Azure resources:

- a rule's `name`: the module names a rule by its map key;
- a ruleset's `metadata_for_outbound_endpoint_virtual_network_link`: the
  module's default link sends no metadata;
- a ruleset's `additional_outbound_endpoint_link`: the module never reads
  it, and a ruleset is on its own endpoint only.

Two differences from the module's azurerm resources, where ASO does more:
the resolver's role assignments send `description` and `principal_type`
(the module's drop them), and a ruleset's role assignment by role ID
works (the module sends every ruleset's role as a role name).

### Not module inputs

| Value | Renders |
| --- | --- |
| `subscription_id` | the subscription of `resource_group_name` when that is a name: the module's azurerm provider knows its subscription, ASO's owner is a resource ID |
| `names.dnsResolver` | the resolver's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of the resolver's name (never one under `names`) and each ruleset's (rulesets are resources of the group); checked against 80 characters. Endpoints, rules and links are named inside the resolver or a ruleset |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

## Outputs

| Output | From |
| --- | --- |
| `name` | the resolver's `azureName` |
| `resource_id` | the resolver's `status.id` |
| `resource` | the resolver as azurerm's object, with the attributes ASO's status has: `id`, `name`, `location`, `resource_group_name`, `virtual_network_id`, `tags` |
| `inbound_endpoint_ips` | per inbound endpoint key, its IP configuration's private address from `status` (the one Azure allocated, for a dynamic one) |
| `inbound_endpoints` | per key: `id`, `name`, `location`, `private_dns_resolver_id`, `ip_configurations` (`private_ip_address`, `private_ip_allocation_method`, `subnet_id`), `tags` |
| `outbound_endpoints` | per key: `id`, `name`, `location`, `private_dns_resolver_id`, `subnet_id`, `tags` |
| `forwarding_rulesets` | per `<outbound key>-<ruleset name>`, as the module keys them: `id`, `name`, `location`, `resource_group_name`, `private_dns_resolver_outbound_endpoint_ids`, `tags` |

All seven of the module's outputs; the azurerm objects carry the
attributes above, not azurerm's `timeouts`.

## From Terraform

A module block's arguments are the values, plus `subscription_id` when
`resource_group_name` is a name. ASO adopts a resource that exists when an
object with its name is applied, so keep the names and leave `namePrefix`
empty; set `deletion_policy: ABANDON` for the first apply, `terraform
state rm` the module, then remove `ABANDON`. One name differs: an
additional link with no `name` is `additional-<outbound key>-<ruleset
name>-<6 hex>`, and the module's 6 hex are of the MD5 of `vnet_id`, which
Helm cannot compute; the chart's are of its SHA-256. Give such a link its
Terraform name (`name`) before adopting it.

## Upstream

Ported from the Azure Verified Module
[`avm-res-network-dnsresolver`](https://github.com/Azure/terraform-azurerm-avm-res-network-dnsresolver/tree/v0.8.0)
at v0.8.0 (`73b1df38`, MIT). Its `ruleset_vnet_link` submodule (links to
an existing ruleset, called on its own) is not part of the root module and
not ported. [`upstream.yaml`](upstream.yaml) records the repository,
release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-network-dnsresolver`: render cases `basic`,
`full`, `names` and `mock`, each validated against ASO v2.22.0's CRD
schemas and aso-extensions' `ManagementLock` CRD, and the refusals in
`tests/*.fail.yaml`.

Fake cloud (`task test-mock-azure`, `hack/azure-mock.sh`; stock ASO and
aso-extensions' manager against its fakearm at `b9beb5b`): `tests/mock.values.yaml` passed in run
`off-catalog-1113075710-7948` on 2026-11-13: the resolver, its inbound
and outbound endpoints, the ruleset, its rule and default link, and the
locks on the resolver and the ruleset, 8 objects Ready and deleted,
outputs evaluated.

Live (`task test-live-azure`, case `dnspr`): a resolver with a dynamic inbound
endpoint and an outbound endpoint, each in a /28 delegated to
`Microsoft.Network/dnsResolvers` of a network the case first makes with
`avm-res-network-virtualnetwork` (PRE), a ruleset on the outbound endpoint
with one forwarding rule and the default link, the group by name and
`subscription_id`, passed in run `cat111308018ca9` (offload
`off-catalog-1113075755-12342`) on 2026-11-13: 9 objects Ready (the
network and subnets among them), outputs evaluated (the inbound address
Azure allocated, `10.252.0.4`, among them), deleted, Azure answering 404.
About 0.25 USD an hour per endpoint while it exists; the case took about
12 minutes and has a 30-minute limit. The lock is not applied live
(Contributor cannot write locks) and no role assignment is made.

## Changes

- **0.1.0** (2026-11-13): the port.
