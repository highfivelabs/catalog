# avm-res-network-loadbalancer

An Azure load balancer with its frontends, backend pools (and their
addresses), probes, rules, inbound NAT rules and pools, outbound rules,
the public IPs it makes, and its lock, role assignments and diagnostic
settings, as Azure Service Operator (ASO) objects. A port of the Azure
Verified Module
[`avm-res-network-loadbalancer`](https://github.com/Azure/terraform-azurerm-avm-res-network-loadbalancer/tree/e83d34778efeb54a1779b968106067cc4b2bad63)
at v0.5.0 (`e83d3477`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-network-loadbalancer`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

## Example

```yaml
name: lb-example
location: eastus2
resource_group_name: rg-example
subscription_id: <id>
frontend_subnet_resource_id: /subscriptions/<id>/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-lb
frontend_ip_configurations:
  fe1: {name: myFrontend}
backend_address_pools:
  pool1: {name: myBackendPool}
lb_probes:
  tcp1: {name: tcp1, protocol: Tcp, port: 80}
lb_rules:
  http: {name: myHTTPRule, frontend_ip_configuration_name: myFrontend, backend_address_pool_object_names: [pool1], frontend_port: 80, backend_port: 80, probe_object_name: tcp1}
```

renders one ASO `LoadBalancer` `lb-example`, an internal Standard load
balancer with its frontend, pool, probe and rule (`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azurerm_lb.this` | always | `LoadBalancer` (`network.azure.com/v20250301`), `load_balancer`, owned by the resource group |
| `azurerm_lb_backend_address_pool`, `azurerm_lb_backend_address_pool_address`, `azurerm_lb_probe`, `azurerm_lb_rule`, `azurerm_lb_nat_rule`, `azurerm_lb_outbound_rule`, `azurerm_lb_nat_pool` | one per entry | inline in the `LoadBalancer` (`backendAddressPools[].loadBalancerBackendAddresses`, `probes`, `loadBalancingRules`, `inboundNatRules`, `outboundRules`, `inboundNatPools`), as ARM carries them; one child refers to another by ARM ID, the load balancer's ID and the child's name |
| `azurerm_public_ip.this` | one per frontend with `create_public_ip_address` | `PublicIPAddress` (`v20250301`), `public_ip:<key>`, which the frontend references by Kubernetes name |
| `azurerm_management_lock.this`, `.pip` | `lock` set; a made public IP's lock as the module decides it | `ManagementLock` (aso-extensions), `lock`, `pip-<key>-lock` |
| `azurerm_role_assignment.this`, `.pip` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>`, `pip-<frontend>-role-assignment-<key>` |
| `azurerm_monitor_diagnostic_setting.this`, `.pip` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>`, `pip-<frontend>-diagnostic-setting-<key>` |
| `azurerm_network_interface_backend_address_pool_association.this` | never | refused (below) |
| telemetry | never | not ported |

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`), with the module's defaults for
optional object attributes.

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` |
| `resource_group_name` (required) | `owner.armId`: `/subscriptions/<subscription_id>/resourceGroups/<resource_group_name>`, or `resource_group_name` itself when it is a resource group's ID |
| `sku`, `sku_tier` | `sku.name`, `sku.tier` |
| `edge_zone` | `extendedLocation` (`EdgeZone`) |
| `tags` | `spec.tags`; on a made public IP, merged as the module merges them (`inherit_tags`) |
| `frontend_ip_configurations` | `frontendIPConfigurations`: `name` (default `frontend-<name>`), `privateIPAddress`, `privateIPAddressVersion`, `privateIPAllocationMethod`, `gatewayLoadBalancer`, `publicIPAddress` (the made public IP, or `public_ip_address_resource_id`), `subnet`, `zones` (only with a subnet: Azure takes a frontend's zones for a private address only). `public_ip_prefix_resource_id` is accepted and, as in the module, not sent. With `create_public_ip_address`, a `PublicIPAddress` named `public_ip_address_resource_name` (default `pip-<name>`) in `new_public_ip_resource_group_name` (or the configuration's or the load balancer's group), at `new_public_ip_location`, with the entry's `edge_zone`, `zones`, `tags`, lock, `role_assignments` and `diagnostic_settings` |
| `frontend_subnet_resource_id` | a frontend's `subnet` when it gives none |
| `public_ip_address_configuration` | every made public IP: `publicIPAllocationMethod`, `ddosSettings`, `dnsSettings` (`domainNameLabel`, `reverseFqdn`), `idleTimeoutInMinutes`, `ipTags`, `publicIPAddressVersion`, `publicIPPrefix`, `sku`, `tags`, and `resource_group_name` |
| `backend_address_pools` | `backendAddressPools`: `name` (default `bepool-1`), `virtualNetwork`, `tunnelInterfaces` |
| `backend_address_pool_configuration` | a pool's and an address's `virtualNetwork` when it gives none |
| `backend_address_pool_addresses` | `loadBalancerBackendAddresses` of the pool `backend_address_pool_object_name` names (a key of `backend_address_pools`): `name`, `ipAddress`, `virtualNetwork` |
| `lb_probes` | `probes`: `intervalInSeconds`, `numberOfProbes` (`number_of_probes_before_removal`), `port`, `probeThreshold`, `protocol`, `requestPath` (Http and Https only) |
| `lb_rules` | `loadBalancingRules`: the pools by ID or key (`backendAddressPool` for one, `backendAddressPools` for several), the probe by key or ID, `frontendIPConfiguration` by name, ports, protocol, `disableOutboundSnat`, `enableFloatingIP`, `enableTcpReset`, `idleTimeoutInMinutes`, `loadDistribution` |
| `lb_nat_rules` | `inboundNatRules` (by `name`, as the module keys them): a single port or a port range to a pool, `backendAddressPool`, `enableFloatingIP`, `enableTcpReset`, `idleTimeoutInMinutes` |
| `lb_nat_pools` | `inboundNatPools` |
| `lb_outbound_rules` | `outboundRules`: `allocatedOutboundPorts`, `backendAddressPool`, `frontendIPConfigurations` by name, `enableTcpReset`, `idleTimeoutInMinutes`, `protocol` |
| `lock` | the AVM lock interface, named `lock-<name>` by default, with the module's notes for the kind |
| `role_assignments` | the AVM interface; `skip_service_principal_aad_check` without a `principal_type` sends `ServicePrincipal`, as azurerm does |
| `diagnostic_settings` | the AVM interface; a setting without a name is `diag-<name>` |
| `enable_telemetry` | accepted; the chart sends no telemetry |
| `backend_address_pool_network_interfaces` | refused (below) |

### Not module inputs

| Value | Renders |
| --- | --- |
| `subscription_id` | the subscription of `resource_group_name` (and of a public IP's group) when it is a name: ASO's owner is a resource ID |
| `names.loadBalancer` | the load balancer's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name` and of each made public IP's name, never of a name under `names`; checked against the 80-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

### Refused when set

| Variable | Kind | Why |
| --- | --- | --- |
| `backend_address_pool_network_interfaces` | gap | a NIC joins a pool through its own `ipConfigurations[].loadBalancerBackendAddressPools`; ASO has no association kind and sets a NIC's IP configurations only by owning the whole `NetworkInterface`. Join a pool by IP address (`backend_address_pool_addresses`) instead, or from the NIC's own chart |

## Outputs

| Output | From |
| --- | --- |
| `name` | the load balancer's `azureName` |
| `resource_id` | the load balancer's `status.id` |
| `azurerm_public_ip` | keyed like `frontend_ip_configurations` (made public IPs only): each one's `id`, `name` and allocated `ip_address` |
| `azurerm_lb_backend_address_pool` | keyed like `backend_address_pools`: each pool's `id` and `name` |
| `azurerm_lb_nat_rule` | keyed by rule name, as the module keys it: each rule's `id` and `name` |

Not outputs: `resource` and `azurerm_lb`, the module's whole azurerm
object. The three maps above carry the fields consumers take from the
module's whole objects.

## From Terraform

A module block's arguments are the values, plus `subscription_id` when
`resource_group_name` is a name. ASO adopts a load balancer or public IP
that exists when an object with its name is applied, so keep the names and
leave `namePrefix` empty; set `deletion_policy: ABANDON` for the first
apply, `terraform state rm` the module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-network-loadbalancer`](https://github.com/Azure/terraform-azurerm-avm-res-network-loadbalancer/tree/v0.5.0)
at v0.5.0 (`e83d3477`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-network-loadbalancer`: render cases `basic`,
`full`, `names` and `mock`, each validated against ASO v2.22.0's CRD
schemas and aso-extensions' `ManagementLock` CRD, and the refusals in
`tests/*.fail.yaml`. `task test-live-azure` (case `lb`) and
`task test-mock-azure`: results below.

## Changes

- **0.1.0** (2026-11-12): the port.
