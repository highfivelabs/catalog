# avm-res-network-applicationgateway

An Azure application gateway with its frontends, ports, listeners, backend
pools and settings, probes, routing rules, redirects, rewrites, URL path
maps, Private Link, SSL policy and profiles, WAF configuration, the public
IPs it makes, and its lock, role assignments and diagnostic settings, as
Azure Service Operator (ASO) objects. A port of the Azure Verified Module
[`avm-res-network-applicationgateway`](https://github.com/Azure/terraform-azurerm-avm-res-network-applicationgateway/tree/f5961205a9046adc86ea1c85cc490c19e462ecbd)
at v0.6.0 (`f5961205`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-res-network-applicationgateway`
(`package.yaml`). Checked against ASO v2.22.0's CRDs.

**ARM version.** ASO v2.22.0's `ApplicationGateway` is at ARM API version
2022-07-01, its only one; the module sends 2025-03-01. Everything 2022-07-01
carries is mapped; each field the later versions added is refused by name
when set (below), so a module call that uses none of them converts one to
one. The chart renders aso-extensions' `ApplicationGateway`
(`network.azure.hfl.dev/v20260301`, beside ASO's under its name;
aso-extensions `docs/plan.md` §8 open question 11) always, which carries
Entra JWT validation (`entra_jwt_validation_configs`, a rule's
`entra_jwt_validation_config`); its managed public IPs are referenced by
ARM ID, and the lock, role assignments and diagnostic settings own the
gateway by ARM ID (their kinds name ASO's `ApplicationGateway`). The other
later fields are not mapped yet on that kind, and stay refused.

## Example

```yaml
name: appgw-example
location: eastus2
parent_id: /subscriptions/<id>/resourceGroups/rg-example
sku: {name: Standard_v2, tier: Standard_v2, capacity: 1}
public_ip_addresses:
  pub: {name: pip-appgw-example}
gateway_ip_configurations:
  - {name: gw-ip, subnet: {id: /subscriptions/<id>/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-appgw}}
frontend_ip_configurations:
  - {name: fe-public, public_ip_address_key: pub}
frontend_ports:
  - {name: port-80, port: 80}
backend_address_pools:
  - {name: pool-web, backend_addresses: [{ip_address: 10.0.1.4}]}
backend_http_settings_collection:
  - {name: http-80, port: 80, protocol: Http, cookie_based_affinity: Disabled, request_timeout: 30}
http_listeners:
  - {name: listener-80, protocol: Http, frontend_ip_configuration: {frontend_ip_configuration_key: fe-public}, frontend_port: {frontend_port_key: port-80}}
request_routing_rules:
  - {name: rule-basic, rule_type: Basic, priority: 100, http_listener: {http_listener_key: listener-80}, backend_address_pool: {backend_address_pool_key: pool-web}, backend_http_settings: {backend_http_settings_key: http-80}}
```

renders one ASO `ApplicationGateway` `appgw-example` with every component
inline, and the `PublicIPAddress` its frontend uses
(`tests/golden/basic.yaml`).

## Moving from an earlier version

From this version the chart always renders aso-extensions' `ApplicationGateway`
(`network.azure.hfl.dev/v20260301`), never ASO's (`network.azure.com/v1api20220701`), so setting or clearing a newer field
never swaps the object's kind. That needs aso-extensions' manager and CRDs
installed beside Azure Service Operator (`docs/azure.md`, "8. Charts";
aso-extensions pin `ASOX_COMMIT`). For a deployment made by an earlier
version, which rendered ASO's kind, the upgrade replaces the Kubernetes
object with one of the other kind under the same name in Azure. Do it
once, with `deletion_policy: ABANDON`: apply the new version with
`ABANDON` (the old object is detached, and the new one adopts the gateway),
check it is Ready, then remove `ABANDON`. Without it, the old object's
delete deletes the gateway in Azure.

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `azapi_resource.this` | always | aso-extensions' `ApplicationGateway` (`network.azure.hfl.dev/v20260301`), `application_gateway`, owned by the resource group `parent_id` names; every component inline, as ARM carries them; its `entraJWTValidationConfigs` (`name`, `audiences`, `clientId`, `tenantId`, `unAuthorizedRequestAction`) and a rule's `entraJWTValidationConfig` resolved by key or ID as the module resolves every reference |
| `azapi_resource.public_ip_addresses` | one per `public_ip_addresses` entry | `PublicIPAddress` (`v20250301`), `public_ip:<key>`: Standard, Regional, Static, which a frontend with that `public_ip_address_key` references by Kubernetes name |
| `azurerm_management_lock.this` | `lock` set | `ManagementLock` (aso-extensions), `lock`, named `lock-<kind>` by default, with the module's notes for the kind |
| `azurerm_role_assignment.this` | one per entry | `RoleAssignment` (`authorization.azure.com/v20220401`), `role-assignment-<key>` |
| `azurerm_monitor_diagnostic_setting.this` | one per entry | `DiagnosticSetting` (`insights.azure.com/v1api20210501preview`), `diagnostic-setting-<key>` |
| telemetry | never | not ported |

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`). Each component collection is a list,
as in the module; its fields are the module's, flattened (the module's
legacy `properties` wrapper is refused, as the module refuses it).

**Internal references.** A reference object (`probe`, `http_listener`,
`backend_address_pool`, ...) takes `id`, any ARM ID sent as it is, or its
type's `*_key`, which must case-insensitively match the configured `name` of
exactly one component of the target collection; it becomes the gateway's
ARM ID (`parent_id`, the gateway's Azure name), the collection's ARM
segment and that component's name, as the module builds it. A redirect's
path rule reference takes `path_rule_key` with `url_path_map_key`. Both,
neither-resolving and malformed keys stop the render with the module's
messages.

| Module input | ASO |
| --- | --- |
| `name` (required), `location` (required) | `azureName`, `location` |
| `parent_id` (required) | `owner.armId` |
| `sku` | `sku.name`, `tier`, `capacity` (1 to 125, not with `autoscale_configuration`) |
| `autoscale_configuration`, `zones`, `enable_http2`, `enable_fips`, `global_configuration`, `custom_error_configurations`, `force_firewall_policy_association` | the same fields |
| `firewall_policy`, a listener's or path rule's `firewall_policy` | `firewallPolicy.reference.armId` |
| `managed_identities` | `identity`: `type` and `userAssignedIdentities` by ARM ID |
| `tags` | `spec.tags`, and on each public IP under its own `tags` |
| `gateway_ip_configurations` | `gatewayIPConfigurations` (the subnet by ID) |
| `frontend_ip_configurations` | `frontendIPConfigurations`: `privateIPAddress`, `privateIPAllocationMethod`, `privateLinkConfiguration`, `subnet`, `publicIPAddress` (by ID, or the public IP `public_ip_address_key` names, with the module's five validations) |
| `frontend_ports`, `backend_address_pools`, `probes` | the same collections (`probes[].id` is accepted and, as in the module, not sent) |
| `backend_http_settings_collection`, `backend_settings_collection` | the same collections, with `probe` and the certificate references by key or ID |
| `http_listeners`, `listeners` | the same collections, with frontend, port, SSL certificate and SSL profile references |
| `ssl_certificates` | `sslCertificates`: `name`; `data` (the PFX, base64) and `password` as references to a Kubernetes Secret, `{secretName, key}` ([secrets](../../../docs/secrets.md)); `key_vault_secret_id` as it is |
| `authentication_certificates`, `trusted_client_certificates`, `trusted_root_certificates` | the same collections: `name`, `data` as a reference to a Kubernetes Secret (the kind takes a certificate's data only from one), and a trusted root's `key_vault_secret_id` as it is |
| `request_routing_rules`, `routing_rules` | the same collections and references |
| `url_path_maps` | `urlPathMaps`, the defaults and each path rule's references |
| `redirect_configurations` | `redirectConfigurations`, with `targetListener`, `pathRules`, `requestRoutingRules` and `urlPathMaps` references |
| `rewrite_rule_sets` | `rewriteRuleSets` (`id` accepted and, as in the module, not sent) |
| `load_distribution_policies` | `loadDistributionPolicies`; a target by `id` only |
| `private_link_configurations` | `privateLinkConfigurations` |
| `ssl_policy`, `ssl_profiles` | `sslPolicy`, `sslProfiles`; a `Predefined` policy sends only its name and type, as the module does |
| `web_application_firewall_configuration` | `webApplicationFirewallConfiguration` |
| `public_ip_addresses` | one `PublicIPAddress` each, as above: `ddosSettings`, `dnsSettings`, `idleTimeoutInMinutes`, `ipTags`, `publicIPAddressVersion`, `publicIPPrefix`, `zones` (the gateway's unless given), owned by its `parent_id` or the gateway's; the module's validations |
| `lock`, `role_assignments`, `diagnostic_settings` | the AVM interfaces; `skip_service_principal_aad_check` without a `principal_type` sends `ServicePrincipal`, as azurerm does; a setting without a name is `diag-<name>` |
| `enable_telemetry`, `customer_managed_key`, `private_endpoints`, `private_endpoints_manage_dns_zone_group` | accepted; as in the module, they change nothing (the module's private endpoints are schema only, issue #284) |

### Not module inputs

| Value | Renders |
| --- | --- |
| `names.applicationGateway` | the gateway's name in full, used as given |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of `name` and of each public IP's name, never of a name under `names`; checked against the 80-character limit |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused: use `lock` |

### Certificates and secrets

The chart never takes a secret's value ([secrets](../../../docs/secrets.md)).
A certificate's `data` and a PFX's `password` are references to a
Kubernetes Secret in the component's namespace, `{secretName, key}`,
expected to come from External Secrets Operator; a string there stops the
render. An HTTPS listener with its certificate from a Secret:

```yaml
ssl_certificates:
  - name: tls
    data: {secretName: appgw-tls, key: pfx}          # the PFX, base64
    password: {secretName: appgw-tls, key: password}
  - name: tls-kv                                     # or from Key Vault, through
    key_vault_secret_id: https://kv.vault.azure.net/secrets/appgw-tls  # a user-assigned identity
frontend_ports:
  - {name: port-443, port: 443}
http_listeners:
  - {name: listener-443, protocol: Https, frontend_ip_configuration: {frontend_ip_configuration_key: fe-public}, frontend_port: {frontend_port_key: port-443}, ssl_certificate: {ssl_certificate_key: tls}}
```

The Secret must be there before the gateway can be Ready.

### Refused when set

| Variable | Kind | Why |
| --- | --- | --- |
| `ignore_body_changes` | by-design | ASO applies the whole spec it is given |
| `resource_types` | by-design | the API versions are the ASO kinds' |
| `retry`, `timeouts` | by-design | ASO retries itself; Bundt sets a component's time limit |

Accepted in part, the field refused by name when set (ARM 2022-07-01
lacks it):

| Variable | Refused field |
| --- | --- |
| `backend_http_settings_collection` | `dedicated_backend_connection`, `sni_name`, `validate_cert_chain_and_expiry`, `validate_sni` |
| `backend_settings_collection` | `enable_l4_client_ip_preservation` |
| `listeners` | `host_names` |
| `probes` | `enable_probe_proxy_protocol_header` |
| `rewrite_rule_sets` | a header configuration's `header_value_matcher` |
| `ssl_profiles` | `client_auth_configuration.verify_client_auth_mode` |
| `sku` | `family`, and the `Basic` name and tier |
| `load_distribution_policies` | a target's `name`, `backend_address_pool`, `weight_per_server` (ASO's type takes a target only by reference) |
| `private_link_configurations` | an IP configuration's `id` (ASO's type has none; ARM derives it) |
| `url_path_maps` | a path rule's `id` (likewise) |

## Outputs

| Output | From |
| --- | --- |
| `name` | the gateway's `azureName` |
| `resource_id` | the gateway's `status.id` |
| `identity_principal_id`, `identity_tenant_id` | `status.identity`, null without a system-assigned identity |
| `operational_state`, `provisioning_state`, `resource_guid`, `type` | the same `status` fields, null until Azure reports them |
| `private_endpoint_connections` | `status.privateEndpointConnections`, `[]` when none |
| `public_ip_addresses` | keyed like `public_ip_addresses`: each one's `resource_id`, allocated `ip_address` and `fqdn` (null without a DNS label) |

Not an output: `default_predefined_ssl_policy`; ASO's 2022-07-01 status
has no `defaultPredefinedSslPolicy`.

## From Terraform

A module block's arguments are the values. ASO adopts a gateway or public
IP that exists when an object with its name is applied (the gateway is then
written at 2022-07-01, so a gateway using a later field must drop it
first), so keep the names and leave `namePrefix` empty; set
`deletion_policy: ABANDON` for the first apply, `terraform state rm` the
module, then remove `ABANDON`.

## Upstream

Ported from the Azure Verified Module
[`avm-res-network-applicationgateway`](https://github.com/Azure/terraform-azurerm-avm-res-network-applicationgateway/tree/v0.6.0)
at v0.6.0 (`f5961205`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-res-network-applicationgateway`: render cases `basic`,
`full`, `names`, `entra` (aso-extensions' kind), `tls` (certificates from
Secrets and Key Vault), `mock`, `mock-entra` and `mock-tls`, each validated against ASO v2.22.0's CRD
schemas and aso-extensions' CRDs, and the refusals in
`tests/*.fail.yaml` (among them a certificate's data or password given as
a value). `task test-live-azure` (case `appgw`) makes a virtual
network and subnet with the virtual network chart, applies a Standard_v2
gateway of capacity 1 with the public IP it makes on that subnet to the
Azure sandbox, evaluates the outputs, deletes it and checks Azure no longer
has it: passed on 2026-11-13 (run `cat111303093fb2`), 4 objects Ready,
the outputs evaluated, nothing left. `task test-mock-azure` applies
`tests/mock.values.yaml` to aso-extensions' fake cloud: passed on
2026-11-13, both objects Ready and deleted, the outputs evaluated.

## Changes

- **0.4.0** (2026-11-14): `ssl_certificates`, `authentication_certificates`,
  `trusted_client_certificates` and `trusted_root_certificates` are mapped:
  a certificate's `data` and `password` are references to a Kubernetes
  Secret, `{secretName, key}` (docs/secrets.md, the builder's decision),
  `key_vault_secret_id` is sent as it is, and a listener's, settings' or
  profile's reference to one resolves by its `*_key`. A string where a
  reference is expected is refused. Renders without them are unchanged.
- **0.3.0** (2026-11-14): always aso-extensions' `ApplicationGateway` (the
  builder's choice). Moving from an earlier version: above.
- **0.2.0** (2026-11-13): `entra_jwt_validation_configs` and a rule's
  `entra_jwt_validation_config` are mapped: they render aso-extensions'
  `ApplicationGateway` (`network.azure.hfl.dev/v20260301`, aso-extensions
  `8d7f8c2`) in place of ASO's.
- **0.1.0** (2026-11-12): the port.
