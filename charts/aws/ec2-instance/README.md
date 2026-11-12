# ec2-instance

An EC2 instance, with an IAM role and instance profile, as AWS Controllers
for Kubernetes (ACK) objects. A port of terraform-aws-modules'
[`terraform-aws-ec2-instance`](https://github.com/terraform-aws-modules/terraform-aws-ec2-instance/tree/294fb8928bc0f7e0d9ba5bea41a8236c9a7a95d9)
at v6.4.1 (`294fb892`), Apache-2.0; modified (a translation of the module's
variables and logic into a Helm chart). Bundt Package `aws-ec2-instance`
(`package.yaml`). Checked against ACK's ec2-controller v1.23.1 and
iam-controller v1.11.3 (`UPSTREAM.md`, "ACK controllers").

## Example

The module's README example "Single EC2 Instance", with the security group
passed in rather than made:

```yaml
name: single-instance
instance_type: t3.micro
key_name: user1
monitoring: true
subnet_id: subnet-eddcdzz4
vpc_security_group_ids: [sg-12345678]
create_security_group: false
tags: {Terraform: "true", Environment: dev}
```

renders one `ec2.services.k8s.aws/v1alpha1` `Instance` (`hfl.dev/id`
`instance`) launched from the module's default AMI parameter
(`tests/golden/basic.yaml`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `aws_instance` | `create` | `ec2/Instance` `instance`: `imageID` (`ami`, or `resolve:ssm:<ami_ssm_parameter>`, which EC2 resolves at launch, where the module reads the parameter itself), `instanceType`, `subnetID`, `securityGroupIDs`, `keyName`, `iamInstanceProfile`, `placement` (`availability_zone`, `placement_group`, `placement_partition_number`, `host_id`, `host_resource_group_arn`, `tenancy`), `privateIPAddress`, `ipv6AddressCount`, `ipv6Addresses`, `networkInterfaces` (`network_interface`), `blockDeviceMappings` (`ephemeral_block_device`), `capacityReservationSpecification`, `cpuOptions`, `creditSpecification` (T instances), `disableAPIStop`, `disableAPITermination`, `ebsOptimized`, `enclaveOptions`, `hibernationOptions`, `instanceInitiatedShutdownBehavior`, `instanceMarketOptions`, `launchTemplate`, `maintenanceOptions`, `metadataOptions` (the module's defaults: IMDSv2 required, hop limit 1), `monitoring`, `privateDNSNameOptions`, `sourceDestCheckEnabled`, `userData` (base64, as EC2 takes it), `tags` (`tags`, `instance_tags`, `Name`) |
| `aws_iam_role`, `aws_iam_role_policy_attachment` | `create_iam_instance_profile` | `iam/Role` `iam-role`: named `iam_role_name` (or `name`), trusting EC2 (`EC2AssumeRole`), `path`, `description`, `permissionsBoundary`, `policies` (`iam_role_policies`), `tags` (`tags`, `iam_role_tags`) |
| `aws_iam_instance_profile` | `create_iam_instance_profile` | `iam/InstanceProfile` `iam-instance-profile`: named as the role, `roleRef` to it; the instance takes it by name |

## Values

Every module variable is a value of the same name, type and default. The
chart adds `names` (`iamRole`, which the instance profile shares),
`namePrefix` (on the role's name and the instance's `Name` tag), `labels`
(Kubernetes only) and `deletion_policy`; `tags` is the module's own, and
`region` becomes the annotation `services.k8s.aws/region` on the instance.

Refused or accepted in part (`upstream.yaml`):

- `create_security_group` (default `true`), in part: ACK's `Instance` takes
  security group IDs only, with no reference, so a group this component
  made could not be attached in one render. Set `create_security_group:
  false` and pass a `security-group` component's `id` output in
  `vpc_security_group_ids`. The group's variables (`security_group_*`) are
  refused with it.
- `ebs_volumes`: ack-extensions' `VolumeAttachment` takes the instance's ID
  with no reference, and a `Volume` needs the instance's Availability Zone.
- `create_eip`, `eip_domain`, `eip_tags`: ACK's `ElasticIPAddress` has no
  instance association.
- `create_spot_instance` and `spot_*`: no Spot request kind;
  `instance_market_options` requests Spot through `RunInstances`.
- `root_block_device`: the root device's name depends on the AMI.
- `associate_public_ip_address`, `secondary_private_ips`: ACK takes them
  only on a network interface it creates, whose spec has no security
  groups.
- `enable_primary_ipv6`, `secondary_network_interface`,
  `placement_group_id`, `force_destroy`, `get_password_data`,
  `user_data_replace_on_change`, `volume_tags`: no ACK field.
- `cpu_options`, in part: not `amd_sev_snp`.
- `ignore_ami_changes`, in part: ACK never replaces an instance.
- `enable_volume_tags`, in part: ACK tags the volumes an instance launches
  with the instance's tags.
- `iam_role_use_name_prefix`, in part: no random suffix.
- `timeouts`: Terraform's (by design).

## Outputs

`id`, `arn` (built as the Terraform provider builds it), `ami`,
`availability_zone`, `capacity_reservation_specification`,
`instance_state`, `outpost_arn`, `private_dns`, `public_dns`, `public_ip`,
`private_ip`, `ipv6_addresses`, `tags_all`, `ephemeral_block_device`, and
the role's and instance profile's. Not provided: the refused resources'
outputs, `password_data`, `primary_network_interface_id`,
`root_block_device` and `ebs_block_device`.

## Tests

`task test CHART=aws/ec2-instance`: golden renders (the module's README
example, most options at once, existing network interfaces with a launch
template, names) validated against the pinned CRDs, and the refusal
cases. `tests/mock.values.yaml` is the case the fake-AWS run applies, in a
subnet that `tests/mock.needs.yaml` makes (`docs/aws.md`, "Charts").
