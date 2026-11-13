# avm-ptn-alz-sub-vending

An Azure landing zone subscription: a new subscription from an alias (or
an existing subscription), its management group and tags, and in it
resource groups, user-assigned identities with federated credentials and
role assignments, virtual networks with hub, mesh and Virtual WAN
connections, network security groups, route tables, role assignments and
budgets, as Azure Service Operator (ASO) and aso-extensions objects. A
port of the Azure Verified Module pattern
[`avm-ptn-alz-sub-vending`](https://github.com/Azure/terraform-azure-avm-ptn-alz-sub-vending/tree/28577b03cf4ad2cd5faa2e9ee7991f07c7c2dab0)
at v0.3.4 (`28577b03`), MIT, Copyright (c) Microsoft Corporation
(`LICENSE.avm`). Bundt Package `azure-avm-ptn-alz-sub-vending`
(`package.yaml`). Checked against ASO v2.22.0's CRDs and aso-extensions'
at `b9beb5b`.

Coverage: 28 of the module's 29 variables, 5 of them in part
(`subscription_register_resource_providers_enabled` is refused:
registering a provider is an action, not a resource); 14 of 14 outputs.

**Two instances for a new subscription.** The module creates the
subscription and the resources in it in one apply, reading the new
subscription's ID from the alias. A render cannot: Azure gives the ID
(the alias's `status.properties.subscriptionId`) only once it has created
the subscription, and ASO puts a `ResourceGroup` in the subscription of its
credential. So an instance with `subscription_alias_enabled` makes the
alias only (placed in its management group and tagged by the alias's
body), and refuses any resource inside the subscription; a second
instance, with `subscription_id` set to the first one's `subscription_id`
output (a Template's `valueFrom`) and ASO's credential for that
subscription, makes the rest.

## Example

```yaml
location: eastus2
subscription_id: <id>
subscription_management_group_association_enabled: true
subscription_management_group_id: landing-zones
resource_group_creation_enabled: true
resource_groups:
  network: {name: rg-network}
virtual_network_enabled: true
virtual_networks:
  primary:
    name: vnet-primary
    address_space: ["10.0.0.0/24"]
    resource_group_key: network
    subnets:
      default: {name: default, address_prefix: 10.0.0.0/26}
```

renders the subscription's placement in `landing-zones`, the group
`rg-network`, the network and its subnet (`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `module.subscription`'s `azapi_resource.subscription` (`Microsoft.Subscription/aliases`) | `subscription_alias_enabled` | `Alias` (`subscription.azure.com/v1api20211001`), `subscription_alias`: `displayName`, `workload`, `billingScope` and `additionalProperties` (`managementGroupId`, `tags`), the module's body |
| `azapi_resource_action.subscription_association` (PUT `managementGroups/<id>/subscriptions/<id>`) | the association, an existing subscription | `ManagementGroupsSubscription` (aso-extensions, `management.azure.hfl.dev/v20230401`), `management_group_subscription_association`; a vended subscription is placed by its alias's `managementGroupId` |
| `azapi_update_resource.subscription_tags` (`Microsoft.Resources/tags`) | `subscription_update_existing` | `TagSet` (aso-extensions, `resources.azure.hfl.dev/v20250401`) on the subscription, `subscription_tags`, always detached on delete (the module's update leaves the tags); a vended subscription is tagged by its alias |
| `azapi_resource_action.subscription_rename` | `subscription_update_existing` with a display name | refused: an action (POST `Microsoft.Subscription/rename`) |
| `azapi_resource_action.subscription_cancel` (at destroy) | `subscription_alias_enabled` | not ported: an action (POST `Microsoft.Subscription/cancel`); deleting the `Alias` removes the alias and leaves the subscription |
| `module.resourcegroup` | `resource_group_creation_enabled` | `ResourceGroup` (`resources.azure.com/v1api20200601`), `resource_group:<key>`; with `lock_enabled` an aso-extensions `ManagementLock` (`CanNotDelete`, `lock_name` or `lock-<group>`), `resource_group:<key>/lock` |
| `module.networksecuritygroup` | `network_security_group_enabled` | `NetworkSecurityGroup` (`network.azure.com/v20250301`), `network_security_group:<key>`, and a `NetworkSecurityGroupsSecurityRule` per rule, `.../security_rule:<rule>` |
| `module.routetable` | `route_table_enabled` | `RouteTable`, `route_table:<key>`, and a `RouteTablesRoute` per route, `.../route:<route>` |
| `module.usermanagedidentity` | `umi_enabled` | `UserAssignedIdentity` (`managedidentity.azure.com/v1api20230131`), `user_managed_identity:<key>`, and a `FederatedIdentityCredential` per GitHub (branch, tag, environment, pull request), Terraform Cloud and advanced credential, named and shaped as the module's, `.../federated_credential:<kind>:<key>` |
| `module.roleassignment_umi` | an identity's `role_assignments` | `RoleAssignment` (`authorization.azure.com/v20220401`), `.../role_assignment:<key>`, its principal from the identity's `principalId` ConfigMap (`principalIdFromConfig`) |
| `module.roleassignment` | `role_assignment_enabled` | `RoleAssignment`, `role_assignment:<key>` |
| `module.budget` | `budget_enabled` | `Budget` (aso-extensions, `consumption.azure.hfl.dev/v20260601`; the module sends 2021-10-01), `budget:<key>` |
| `module.virtualnetwork`'s networks and subnets | `virtual_network_enabled` | `VirtualNetwork`, `virtual_network:<key>`, and a `VirtualNetworksSubnet` per subnet, `.../subnet:<key>` |
| its hub peerings | `hub_peering_enabled` | `VirtualNetworksVirtualNetworkPeering`: to the hub owned by the network (`.../peering_tohub`), from the hub owned by the hub's network by ID (`.../peering_fromhub`), named `peer-<uuidv5 of the remote network's ID>` as the module names them |
| its mesh peerings | `mesh_peering_enabled` on two or more networks | a `VirtualNetworksVirtualNetworkPeering` each way, `.../peering_mesh:<other>` |
| `azapi_resource.vhubconnection` and `.vhubconnection_routing_intent` | `vwan_connection_enabled` | `VirtualHubsHubVirtualNetworkConnection` (aso-extensions, `network.azure.hfl.dev/v20260301`; the module sends 2022-07-01), owned by the hub by ID, `.../vhub_connection`, named `vhc-<uuidv5 of the network's ID>`; without `routingConfiguration` with routing intent, as the module's body |
| `module.resourceproviders` | `subscription_register_resource_providers_enabled` | refused: provider and feature registration is an action |
| telemetry, `time_sleep`, `terraform_data`, the association's data sources, `moved` blocks | | not ported (ASO retries until what an object needs exists) |

Role assignment names are the module's (`uuidv5` of scope, principal and
role definition ID) when all three are known at render: a principal by ID
and a role by ID. A role given by name resolves in Azure (ASO's
`wellKnownName`, where the module reads avm-utl-roledefinitions' table)
and an identity's principal is known only once Azure has made it, so
those, and `use_random_uuid: true`, get ASO's own stable UUID.
`definition_lookup_enabled` has no effect: ASO resolves a name itself.

A reference to a resource of the chart (a subnet's network security group
or route table by `key_reference`, a mesh peering's remote network, a
budget's or role assignment's resource group by key) is the chart's
object, so ASO waits for it; an existing group is its ID
(`/subscriptions/<subscription_id>/resourceGroups/<name>`).

## Values: module inputs to ASO

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`).

| Module input | ASO |
| --- | --- |
| `location` (required) | every resource's location unless its own is set |
| `subscription_alias_enabled`, `subscription_alias_name`, `subscription_display_name`, `subscription_billing_scope`, `subscription_workload` | the `Alias`, its `azureName` and `properties`; each checked as the module describes it |
| `subscription_id` | the subscription every other resource goes into (a lower-case GUID); refused with `subscription_alias_enabled` |
| `subscription_management_group_association_enabled`, `subscription_management_group_id` | the alias's `managementGroupId`, or the `ManagementGroupsSubscription` |
| `subscription_tags` | the alias's tags, or the `TagSet`'s with `subscription_update_existing` |
| `subscription_update_existing` | the `TagSet`; with `subscription_display_name`, refused (a rename) |
| `wait_for_subscription_before_subscription_operations` | accepted, no effect |
| `resource_group_creation_enabled`, `resource_groups` | `ResourceGroup`s: `name` (`azureName`), `location`, `tags`, `lock_enabled`, `lock_name` |
| `network_security_group_enabled`, `network_security_groups` | `name`, `location`, `resource_group_key` or `resource_group_name_existing` (exactly one), `tags`, `security_rules` (every field); `resource_types` refused |
| `route_table_enabled`, `route_tables` | `name`, `location`, the group (`resource_group_name_existing` wins, as the module's `coalesce`), `bgp_route_propagation_enabled` (`disableBgpRoutePropagation`), `tags`, `routes`; `resource_types` refused |
| `umi_enabled`, `user_managed_identities` | `name`, the group (exactly one), `location`, `tags`, `role_assignments`, `federated_credentials_github`, `_terraform_cloud`, `_advanced` |
| `role_assignment_enabled`, `role_assignments` | `principal_id`, `definition` (a name as `wellKnownName`; a scopeless ID with the subscription in front, as the module), `relative_scope`, `resource_group_scope_key`, `condition`, `condition_version`, `principal_type`, `use_random_uuid` (no `azureName`), `definition_lookup_enabled` (no effect) |
| `budget_enabled`, `budgets` | `name`, `amount`, `time_grain`, `time_period_start`, `time_period_end`, `relative_scope` or `resource_group_key` (the owner), `notifications` (`contact_groups` as `contactGroupsReferences`) |
| `virtual_network_enabled`, `virtual_networks` | `name`, `address_space` or `ipam_pools` (`ipamPoolPrefixAllocations`, the prefix length as a count of addresses), the group, `location`, `dns_servers`, `flow_timeout_in_minutes`, `ddos_protection_plan_id` (the module enables DDoS protection whenever a plan is given; `ddos_protection_enabled` has no effect there either), `subnets` (every field), `hub_*`, `mesh_*`, `vwan_*`, `tags`. Hub peering options with `peer_complete_vnets: false` fail as in the module, which passes the peering submodule no remote spaces or subnets |
| `subscription_register_resource_providers_enabled` | refused when true |
| `subscription_register_resource_providers_and_features` | accepted (the module's default list); read only with the above |
| `enable_telemetry` | accepted; the chart sends no telemetry |

### Not module inputs

| Value | Renders |
| --- | --- |
| `namePrefix` | an optional convenience: `<namePrefix>-` in front of the alias's, groups', network security groups', route tables', identities', networks' and budgets' names, and so in the IDs built from them |
| `names` | none: every name is an input; any key is refused |
| `tags` | Azure tags on every resource that takes them (the alias's subscription, the tag set, groups, network security groups, route tables, identities, networks), under each resource's own, which win |
| `labels` | Kubernetes labels on every object. ASO never copies labels to Azure |
| `deletion_policy` | `DELETE` (default) or `ABANDON` (ASO's `detach-on-delete` on every object). `PREVENT` is refused |

### Refused when set

| Variable | Kind | Why |
| --- | --- | --- |
| `subscription_register_resource_providers_enabled` | gap | registering a resource provider or feature is an action on the subscription (POST `.../providers/<namespace>/register`), not a resource |
| `subscription_alias_enabled` (in part) | gap | resources inside the new subscription (its ID comes after the render) and the cancel at destroy (an action) |
| `subscription_update_existing` (in part) | gap | the rename (POST `Microsoft.Subscription/rename`, an action) |
| `network_security_groups`, `route_tables` (in part) | by-design | an entry's `resource_types`: ASO's kinds fix the API versions |
| `subscription_register_resource_providers_and_features` (in part) | gap | read only with the refused registration |

## Outputs

| Output | From |
| --- | --- |
| `subscription_id`, `subscription_resource_id`, `resource_id` | the alias's `status.properties.subscriptionId`, or `subscription_id` |
| `management_group_subscription_association_id` | `/providers/Microsoft.Management/managementGroups/<id>/subscriptions/<subscription>` with the association, else null |
| `resource_group_resource_ids`, `network_security_group_resource_ids`, `route_table_resource_ids`, `budget_resource_id`, `virtual_network_resource_ids` | `{<key>: status.id}` |
| `virtual_network_subnet_resource_ids` | `{<network>: {<subnet>: status.id}}` |
| `umi_client_ids`, `umi_principal_ids`, `umi_resource_ids`, `umi_tenant_ids` | each identity's `status.clientId`, `principalId`, `id`, `tenantId` |

## From Terraform

A module block's arguments are the values. ASO adopts resources that exist
when an object with their name is applied, so keep the names and leave
`namePrefix` empty; set `deletion_policy: ABANDON` for the first apply,
`terraform state rm` the module, then remove `ABANDON`. Role assignments
the module named with its own `uuidv5` keep that name where the chart can
compute it (a role and principal by ID); others get a new name, so remove
the module's assignment first. A vended subscription is adopted by its
alias name, then the resources in it by a second instance with its
`subscription_id`.

## Upstream

Ported from the Azure Verified Module
[`avm-ptn-alz-sub-vending`](https://github.com/Azure/terraform-azure-avm-ptn-alz-sub-vending/tree/v0.3.4)
at v0.3.4 (`28577b03`, MIT). [`upstream.yaml`](upstream.yaml) records the
repository, release, commit, licence and the date last synced.

## Tests

`task test CHART=avm-ptn-alz-sub-vending`: render cases `basic` (an
existing subscription placed in a management group, a group and a
network), `vended` (a new subscription from an alias), `full` (every input
on an existing subscription) and `mock`, each validated against ASO
v2.22.0's CRD schemas and the aso-extensions CRDs it renders
(`crds/aso-extensions`), and the refusals in `tests/*.fail.yaml`.

**Fake cloud** (`tests/mock.values.yaml`: the fake's subscription with
its tags updated, a locked group made by the chart, a network security
group and rule, a route table and route, an identity with a GitHub
credential and a Reader assignment on the group, a role assignment by ID,
a budget, two meshed networks, one with a subnet in the group's network
security group and route table), stock ASO and aso-extensions' manager at
`b9beb5b` against aso-extensions' fakearm, offload run
`off-catalog-1113105137-12955` on 2026-11-13: 17 objects Ready and
deleted, outputs evaluated. The first run (`off-catalog-1113103359-27219`)
found that a role assignment owned by the chart's resource group by name
needs the group's kind too (an extension resource's owner); fixed.

**Not applied live.** A subscription alias creates a subscription (tenant
and billing scope), a management group association and subscription tags
are subscription or management group scope, and resource groups are
subscription scope: the live rules allow none of them, nor role
assignments or locks, and the sandbox identity is Contributor on one
resource group. What remains in a resource group (networks, network
security groups, route tables, identities) is what the resource charts
already apply live.

## Changes

- **0.1.0** (2026-11-13): the port.
