# net-vpc

A VPC network with its subnets, routes, peering, Shared VPC, DNS policy
and Private Service Access, as Config Connector objects. A port of Cloud
Foundation Fabric's
[`modules/net-vpc`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/net-vpc)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-net-vpc` (`package.yaml`). Checked against Config Connector
v1.160.0.

## Example

The fabric README's "Simple VPC":

```yaml
project_id: my-project
name: my-network
subnets:
  - name: production
    region: europe-west1
    ip_cidr_range: 10.0.0.0/24
    secondary_ip_ranges:
      pods: {ip_cidr_range: 172.16.0.0/20}
      services: {ip_cidr_range: 192.168.0.0/24}
  - {name: production, region: europe-west2, ip_cidr_range: 10.0.16.0/24}
```

renders the network, two subnets and the three googleapis routes fabric
creates by default (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `name`, `project_id`, `description`, `auto_create_subnetworks`, `delete_default_routes_on_create`, `mtu`, `routing_mode`, `firewall_policy_enforcement_order`, `ipv6_config` | `ComputeNetwork` |
| `vpc_reuse` | no network: everything else goes on the existing network `name` in `project_id` |
| `subnets`, `subnets_proxy_only`, `subnets_private_nat`, `subnets_psc` | one `ComputeSubnetwork` each, with fabric's purposes, roles and default descriptions; secondary ranges, flow logs and IPv6 |
| subnet `iam`, `iam_bindings`, `iam_bindings_additive` | an `IAMPartialPolicy` and `IAMPolicyMember`s on the subnet |
| `factories_data.subnets` | the subnet factory (below) |
| `routes`, `create_googleapis_routes` | one `ComputeRoute` each, named `<name>-<key>`; next hops `gateway`, `ip`, `instance`, `vpn_tunnel`, `ilb` |
| `peering_config` | a `ComputeNetworkPeering`, and the remote one unless `create_remote_peer: false` |
| `shared_vpc_host`, `shared_vpc_service_projects` | `ComputeSharedVPCHostProject` and a `ComputeSharedVPCServiceProject` per service project |
| `dns_policy` | `DNSPolicy` |
| `psa_configs` | a global `ComputeAddress` per range and a `ServiceNetworkingConnection` per producer |
| `firewall_policy_associations.global` | `ComputeNetworkFirewallPolicyAssociation` |
| `allow_alpha` | not a fabric variable: accepts the features below that need an alpha Config Connector kind (see "Alpha") |
| `deletion_policy` | not a fabric net-vpc variable; `ABANDON` keeps every cloud resource |

### Factories

fabric reads subnet files from `factories_config.subnets_folder`. A chart
cannot read the caller's files, so the files' contents go under
`factories_data.subnets`, keyed by file name without `.yaml`, each exactly
as fabric reads it (`psc`, `proxy_only`, `private_nat` choose the kind;
the name defaults to the key):

```yaml
factories_data:
  subnets:
    factory-subnet:
      region: europe-west4
      ip_cidr_range: 10.128.0.0/24
```

`factories_config` is accepted and ignored.

### Alpha

Beta kinds are always on. These features need a `v1alpha1` kind, whose
schema may change between Config Connector releases, so each is refused
until the component sets `allow_alpha: true`. They are render-tested
against the kinds' schemas (`tests/alpha.values.yaml`) and have not been
applied to a cloud, real or fake.

| Variable | Renders |
| --- | --- |
| `network_attachments` | `ComputeNetworkAttachment` per attachment, on a subnet of this chart (`description` is not supported) |
| `psa_configs[].export_routes`, `import_routes` | `ComputeNetworkPeeringRoutesConfig` (only for `servicenetworking.googleapis.com`, whose peering name is known) |
| `psa_configs[].peered_domains` | `ServiceNetworkingPeeredDNSDomain` per domain |

Refused when set:

| Variable | Why |
| --- | --- |
| `bgp_config` | `ComputeNetwork` has no BGP fields (field gap) |
| `internal_ranges`, subnet `reserved_internal_range`, `policy_based_routes`, `service_connection_policies` | alpha kinds not ported yet, even with `allow_alpha` |
| subnet `ip_collection`, `allow_subnet_cidr_routes_overlap` | `ComputeSubnetwork` has no such field (field gaps) |
| `firewall_policy_associations` other than `global` | no regional network firewall policy association kind (gap 6) |
| `context` | use Bundt's `${...}` expressions and `valueFrom` |

## Outputs

| Output | From |
| --- | --- |
| `name`, `id`, `self_link`, `project_id` | the network |
| `subnet_ids`, `subnet_self_links`, `subnet_ips`, `subnet_regions`, `subnet_secondary_ranges`, `subnet_ipv6_external_prefixes` | regular subnets, keyed `<region>/<name>` |
| `subnets_proxy_only`, `subnets_psc`, `subnets_private_nat` | self links of those subnets, keyed `<region>/<name>` |

These are fabric's declared outputs, selected (docs/design.md,
"Outputs"). Not outputs: `network_id` and `internal_ipv6_range`
(`ComputeNetwork` does not report them: field gaps), the maps of internal
ranges, service connection policies and network attachments (those
features are alpha or refused), and fabric's whole-object outputs
(`network`, `subnets`). Where fabric's output is a map of whole subnet
objects (`subnets_proxy_only`, `subnets_psc`, `subnets_private_nat`) the
output is the self link, the field consumers take. `name` and
`project_id` come from the component's inputs; with `vpc_reuse` the
network's `id` and `self_link` have no value.

## Differences from the module

- Subnet IAM's authoritative variables are `IAMPartialPolicy`
  (`docs/design.md`, "IAM").
- The remote peering and Shared VPC service attachments act in other
  projects: the namespace's Google service account needs roles there.

## Tests

`task test CHART=net-vpc`: five render cases, seven refusals.
`tests/mock.values.yaml` is applied to the fake cloud.
