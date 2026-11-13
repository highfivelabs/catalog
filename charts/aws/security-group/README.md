# security-group

A VPC security group with its ingress and egress rules, as an AWS
Controllers for Kubernetes (ACK) object. A port of terraform-aws-modules'
[`terraform-aws-security-group`](https://github.com/terraform-aws-modules/terraform-aws-security-group/tree/58d8e895915f5573767081142d063b7caf7a2b47)
at v6.0.0 (`58d8e895`), Apache-2.0; modified (a translation of the
module's variables and logic into a Helm chart). Bundt Package
`aws-security-group` (`package.yaml`). Checked against ACK's
ec2-controller v1.23.1 (`UPSTREAM.md`, "ACK controllers").

## Example

The module's README example:

```yaml
name: example
description: Example security group
vpc_id: vpc-12345678
ingress_rules:
  https: {from_port: 443, ip_protocol: tcp, cidr_ipv4: 10.0.0.0/16, description: HTTPS from internal}
  self-all: {ip_protocol: "-1", referenced_security_group_id: self, description: All traffic from members of this SG}
egress_rules:
  all: {ip_protocol: "-1", cidr_ipv4: 0.0.0.0/0}
tags: {Environment: dev}
```

renders one `ec2.services.k8s.aws/v1alpha1` `SecurityGroup`
(`hfl.dev/id` `security-group`) with both rule sets inline
(`tests/golden/basic.yaml`).

## What it renders

| Module resource | ACK |
| --- | --- |
| `aws_security_group` | `SecurityGroup`: `name`, `description` (unset, the Terraform provider's default, `Managed by Terraform`, since AWS cannot change a group's description later), `vpcID`, `tags` |
| `aws_vpc_security_group_ingress_rule`, `aws_vpc_security_group_egress_rule` | `SecurityGroup.ingressRules` and `egressRules`, one entry per rule, in key order: `ipProtocol` (default `tcp`), `fromPort`/`toPort` (each defaulting to the other, as the module does), and the source as `ipRanges` (`cidr_ipv4`), `ipv6Ranges` (`cidr_ipv6`), `prefixListIDs` (`prefix_list_id`) or `userIDGroupPairs` (`referenced_security_group_id`; `self` is a pair with no group ID, which ACK fills with the group's own) |
| `aws_vpc_security_group_rules_exclusive` (`enable_exclusive_rules`, default `true`) | inherent: ACK keeps the rules inline and reverts rules added elsewhere |

ACK removes the default allow-all egress rule from a new group, as the
Terraform provider does. The module's validation (each rule sets exactly
one source) stops the render with the module's message.

## Values

Every module variable is a value of the same name, type and default. The
chart adds `names` (`securityGroup`), `namePrefix`, `labels` (Kubernetes
only) and `deletion_policy` (`ABANDON` renders
`services.k8s.aws/deletion-policy: retain`); `tags` is the module's own,
and `region` becomes the annotation `services.k8s.aws/region`.

Refused or accepted in part (`upstream.yaml`):

- `use_name_prefix` (default `true`), in part: the group is named `name`,
  without Terraform's random suffix, since a render must not change
  between plans; `namePrefix` keeps two Instances' groups apart. To adopt a
  group Terraform made, set `names.securityGroup` to its full name.
- `ingress_rules`, `egress_rules`, in part: a rule's `name` and `tags` (the
  rule resource's tags) are not carried; ACK's inline rules have no tags.
- `enable_exclusive_rules: false`: ACK always owns the whole rule set.
- `revoke_rules_on_delete`: no ACK field.
- `vpc_associations`: `aws_vpc_security_group_vpc_association` has no kind.
- `vpc_id`, in part: required. Unset, Terraform takes the account's default
  VPC; ACK's `SecurityGroup` needs its VPC's ID, and the chart cannot look
  the default VPC up (found by the fake-AWS run: ACK leaves such a group
  unresolved, "resource reference wrapper or ID required: VPCID,VPCRef").
- `timeouts`: Terraform's; ACK retries until synced (by design).

The module's 53 preset submodules (`http-80`, `ssh`, ...) are rule sets
written as values; they are not separate charts.

## Outputs

All five: `id`, `arn` (built as the Terraform provider builds it; EC2
reports none), `vpc_id`, `owner_id`, `name`.

## Tests

`task test CHART=aws/security-group`: golden renders validated against
ec2-controller v1.23.1's CRDs, and the refusal cases. `tests/mock.values.yaml`
is the case the fake-AWS run applies (`task test-mock-aws`; `docs/aws.md`,
"Charts"), in a VPC that `tests/mock.needs.yaml` makes.
