# vpc

A VPC with its subnets, route tables, internet and NAT gateways, network
ACLs, DHCP options and RDS and ElastiCache subnet groups, as AWS
Controllers for Kubernetes (ACK) objects. A port of terraform-aws-modules'
[`terraform-aws-vpc`](https://github.com/terraform-aws-modules/terraform-aws-vpc/tree/b3abd6df2ecf052451a361ed55b8f06f8742a795)
at v6.7.3 (`b3abd6df`), Apache-2.0; modified (this is a translation of the
module's variables, names and logic into a Helm chart). Bundt Package
`aws-vpc` (`package.yaml`). Checked against ACK's ec2-controller v1.23.1,
rds-controller v1.14.2 and elasticache-controller v1.12.0 (`UPSTREAM.md`,
"ACK controllers").

## Example

The module's own README example:

```yaml
name: my-vpc
cidr: 10.0.0.0/16
azs: [eu-west-1a, eu-west-1b, eu-west-1c]
private_subnets: [10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24]
public_subnets: [10.0.101.0/24, 10.0.102.0/24, 10.0.103.0/24]
enable_nat_gateway: true
enable_vpn_gateway: false
tags: {Terraform: "true", Environment: dev}
```

renders the `VPC`, six `Subnet`s, a public `RouteTable` with a route to
the `InternetGateway`, three private `RouteTable`s each with a route to its
own `NATGateway`, and three `ElasticIPAddress`es for them: the 18 objects
of `tests/golden/basic.yaml`, the resources Terraform plans for the same
call (less the default network ACL, route table and security group, below).

## What it renders

Every object is `<group>/v1alpha1` (ACK serves every kind as `v1alpha1`;
the controllers are GA). Objects of one loop carry their index in their
`hfl.dev/id` and Kubernetes name, in the module's order.

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `aws_vpc`, `aws_vpc_ipv4_cidr_block_association` | `create_vpc` (and `putin_khuylo`) | `ec2/VPC` `vpc`; `secondary_cidr_blocks` follow `cidr` in `cidrBlocks` |
| `aws_subnet` (`public`, `private`, `database`, `elasticache`, `intra`) | one per CIDR | `ec2/Subnet` `<type>-subnet-<i>` |
| `aws_route_table` | per type, as the module counts them (one public or one per subnet; one private per NAT gateway; database and ElastiCache with `create_*_subnet_route_table`; one intra or one per subnet) | `ec2/RouteTable` `<type>-route-table-<i>` |
| `aws_route` (to the internet gateway, to the NAT gateways) | as the module creates them | `RouteTable.routes`, with `gatewayRef` or `natGatewayRef` |
| `aws_route_table_association` | as the module picks each subnet's table | `Subnet.routeTableRefs` |
| `aws_internet_gateway` | public subnets and `create_igw` | `ec2/InternetGateway` `igw`, attached by `vpcRef` |
| `aws_eip` | `enable_nat_gateway`, not `reuse_nat_ips` | `ec2/ElasticIPAddress` `nat-eip-<i>` |
| `aws_nat_gateway` | `enable_nat_gateway`: one, one per AZ, or one per subnet index | `ec2/NATGateway` `nat-<i>`, with `allocationRef` (or `allocationID` from `external_nat_ip_ids`) and `subnetRef` |
| `aws_network_acl`, `aws_network_acl_rule` | `<type>_dedicated_network_acl` | `ec2/NetworkACL` `<type>-network-acl`, rules as `entries`, subnets as `associations` |
| `aws_vpc_dhcp_options`, `aws_vpc_dhcp_options_association` | `enable_dhcp_options` | `ec2/DHCPOptions` `dhcp-options`, with `vpcRefs` |
| `aws_db_subnet_group` | database subnets and `create_database_subnet_group` | `rds/DBSubnetGroup` `database-subnet-group` |
| `aws_elasticache_subnet_group` | ElastiCache subnets and `create_elasticache_subnet_group` | `elasticache/CacheSubnetGroup` `elasticache-subnet-group` |
| `aws_customer_gateway` | `customer_gateways`, with `allow_alpha: true` | `ec2.aws.hfl.dev/CustomerGateway` (ack-extensions) `customer-gateway-<key>` |

References between the chart's objects are ACK references by Kubernetes
name (`vpcRef`, `subnetRef`, `gatewayRef`, ...), so ACK resolves the IDs at
runtime and nothing crosses the plan (`docs/design.md`, "References between
resources").

## Values

Every module variable is a value of the same name, type and default
(`values.yaml`, `values.schema.json`), so a module block's arguments
convert one to one. The ones the chart maps:

| Module input | ACK |
| --- | --- |
| `name` | the `Name` tag of the VPC and the base of every derived `Name` tag (`<name>-<suffix>-<az>`, as the module derives them) |
| `cidr`, `secondary_cidr_blocks`, `ipv4_ipam_pool_id`, `instance_tenancy`, `enable_dns_hostnames`, `enable_dns_support`, `enable_network_address_usage_metrics` | the `VPC`'s fields |
| `region` | the annotation `services.k8s.aws/region` on every object; unset takes the namespace's or the controller's region |
| `tags` and each `*_tags` | the AWS tags, merged as the module merges them (`Name`, then `tags`, then the resource's own map; a later key wins) |
| `azs` | each subnet's `availabilityZone`, or `availabilityZoneID` for an ID such as `use2-az3`, as the module tells them apart |
| `<type>_subnets`, `<type>_subnet_names`, `<type>_subnet_suffix`, `public_subnet_tags_per_az`, `private_subnet_tags_per_az`, `map_public_ip_on_launch`, `<type>_subnet_enable_resource_name_dns_a_record_on_launch`, `<type>_subnet_private_dns_hostname_type_on_launch` | the `Subnet`s' fields and tags |
| `create_multiple_public_route_tables`, `create_multiple_intra_route_tables`, `create_database_subnet_route_table`, `create_elasticache_subnet_route_table`, `create_database_internet_gateway_route`, `create_database_nat_gateway_route`, `create_private_nat_gateway_route`, `nat_gateway_destination_cidr_block` | the route tables, their routes and the subnets' associations |
| `create_igw`, `enable_nat_gateway`, `single_nat_gateway`, `one_nat_gateway_per_az`, `reuse_nat_ips`, `external_nat_ip_ids`, `external_nat_ips` | the gateways and Elastic IPs (`external_nat_ips` only feeds `nat_public_ips`, as in the module) |
| `<type>_dedicated_network_acl`, `<type>_inbound_acl_rules`, `<type>_outbound_acl_rules` | the `NetworkACL`s: `rule_number`, `rule_action`, `protocol`, `cidr_block`, `ipv6_cidr_block`, `from_port`/`to_port` (`portRange`), `icmp_type`/`icmp_code` (`icmpTypeCode`) |
| `enable_dhcp_options`, `dhcp_options_*` | `DHCPOptions.dhcpConfigurations` (`domain-name`, `domain-name-servers`, `ntp-servers`, `netbios-name-servers`, `netbios-node-type`, `ipv6-address-preferred-lease-time`), each when set |
| `create_database_subnet_group`, `database_subnet_group_name`, `create_elasticache_subnet_group`, `elasticache_subnet_group_name` | the subnet groups (the database group's name lower-cased, as the module does) |
| `customer_gateways`, `customer_gateway_tags` | `CustomerGateway`: `ip_address`, `bgp_asn`, `bgp_asn_extended`, `device_name`, `certificate_arn`, `type_: ipsec.1` |
| `manage_default_security_group` | in part: `true` (the default) sets `VPC.disallowSecurityGroupDefaultRules`, which removes the default security group's rules, as the module's `aws_default_security_group` with no rules does |
| `manage_default_network_acl`, `manage_default_route_table` | in part: accepted, and nothing rendered (below) |

Values the chart adds (not Terraform variables): `names`
(`vpc`, `databaseSubnetGroup`, `elasticacheSubnetGroup`), `namePrefix`,
`labels` (Kubernetes labels only: ACK does not copy labels to AWS),
`allow_alpha` and `deletion_policy` (`ABANDON` annotates every object
`services.k8s.aws/deletion-policy: retain`). `tags` is the module's own.

The module's failures are the chart's: subnets without `azs`, NAT gateways
without public subnets, `one_nat_gateway_per_az` with fewer public subnets
than AZs, and `reuse_nat_ips` without `external_nat_ip_ids` stop the
render.

## Refused

Each stops the render, naming the gap, when set to anything but the
module's default (`upstream.yaml` lists every one; `task coverage-verify`
renders each). 127 of the module's 236 variables:

- **IPv6** (`enable_ipv6`, `ipv6_*`, `create_egress_only_igw`, each type's
  `*_ipv6_*`, `*_enable_dns64`, `*_aaaa_record_on_launch`,
  `*_assign_ipv6_address_on_creation`): a subnet's IPv6 block is
  `cidrsubnet()` of the VPC's Amazon-assigned block, known only after
  apply, and `Subnet` has no field that references it; a route to the
  egress-only internet gateway has no reference field either.
- **Redshift subnets** (every `redshift_*`, `enable_public_redshift`): no
  kind for `aws_redshift_subnet_group` (ACK's redshift-controller has no
  release).
- **Outpost subnets** (every `outpost_*`, `customer_owned_ipv4_pool`,
  `map_customer_owned_ip_on_launch`): not ported yet (`Subnet` has
  `outpostARN`).
- **Flow logs** (`enable_flow_log`, `flow_log_*`, `create_flow_log_*`,
  `vpc_flow_log_*`): `FlowLog.resourceID` takes the VPC's ID and has no
  reference field, so one render cannot wire it.
- **The VPN gateway** (`enable_vpn_gateway`, `vpn_gateway_*`,
  `amazon_side_asn`, `propagate_*_route_tables_vgw`): ack-extensions has
  `VPNGateway` and `VPNGatewayRoutePropagation`, but they take the VPC and
  the route table as plain IDs, with no reference field.
- **IPAM by netmask** (`use_ipam_pool`, `ipv4_netmask_length`): ACK's
  `VPC.cidrBlocks` is required.
- **Block Public Access** (`vpc_block_public_access_*`): no kind.
- **The default VPC** (`manage_default_vpc`, `default_vpc_*`): no kind.
- **The VPC's default security group, network ACL and main route table**
  (`default_security_group_*`, `default_network_acl_*`,
  `default_route_table_*`): no kind adopts them by their VPC. With the
  `manage_default_*` defaults, the module only renames and tags them (and
  removes the default security group's rules, which the chart does); the
  chart leaves their names and tags alone.

## Outputs

53 of the module's 119 outputs (`package.yaml`): the VPC's ID, ARN, CIDR
blocks, settings and owner; each subnet type's IDs, ARNs, CIDR blocks and
route table IDs, and network ACL ID and ARN; the NAT gateways' IDs and
interfaces, their Elastic IPs' allocation IDs and addresses; the internet
gateway's ID and ARN; the DHCP options' ID; the subnet groups' names; the
customer gateways' IDs and ARNs; `name` and `azs`. EC2 reports no ARNs, so
ARNs are built as the Terraform provider builds them. Not provided: whole
objects (`*_subnet_objects`, `this_customer_gateway`), route and
association IDs (ACK has no route or association object), and the outputs
of what is refused.

## Differences from Terraform

- **Ordering.** The module creates the NAT gateways and their Elastic IPs
  after the internet gateway (`depends_on`). ACK has no such order: a
  `NATGateway` waits only for its subnet and Elastic IP. Whether AWS
  accepts a public NAT gateway before the VPC's internet gateway is
  attached is to be checked against AWS.
- **Default security group, network ACL and route table**: not tagged or
  renamed (above).
- **Inline routes.** Routes are part of each `RouteTable` (ACK has no route
  kind), so another component cannot add a route to these tables without
  taking over the whole table (`docs/aws.md`, "Inline versus standalone").
- **Adopting from Terraform.** ACK adopts an existing resource only by its
  ID (`services.k8s.aws/adoption-policy`), which these objects do not
  carry yet; moving a Terraform-managed VPC to this chart without
  recreating it is not supported by this version.

## Tests

`task test CHART=aws/vpc`: every case renders to its golden file and
validates with `kubeconform -strict` against the pinned controllers' CRDs;
the refusal cases (`tests/*.fail.yaml`) fail with their message.
`tests/mock.values.yaml` is the case a fake-AWS run will apply; that layer
is not built yet (`docs/aws.md`, "Charts").
