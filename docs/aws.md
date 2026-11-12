# AWS seed catalog: terraform-aws-modules mapped to ACK

The goal: on the AWS side, mirror charts for each of the top modules of
https://github.com/terraform-aws-modules and their submodules, to make the
transition from Terraform much simpler for teams; kro only if it is
clearly valuable.

This is an inventory. It ranks the modules by use, lists what each top module
and its submodules create, maps every Terraform resource to an ACK kind, and
ranks the gaps for `ack-extensions`. It ends with a kro verdict. Nothing was
built.

## Summary

- The org has 62 repositories, 58 of them Terraform modules. Three are
  archived. Every module is Apache-2.0, with no NOTICE file.
- By downloads in the last year, the top ten are iam, s3-bucket, vpc, eks,
  kms, lambda, security-group, rds, rds-aurora and acm.
- **ACK covers the top 25 well.** Every one of them has a GA (v1.x) ACK
  controller for its main resource. Four are fully covered: sqs, sns,
  dynamodb-table and eks-pod-identity. Elasticache misses only global
  replication groups, and the core of ecs and s3-bucket is covered. The gaps
  are mostly side resources: permissions, attachments, rotation, replicas
  and account-level settings.
- **ACK puts many Terraform side resources inline**: S3 bucket
  configurations, SQS and SNS policies, security group rules, routes, ECR
  lifecycle policies and EFS policies. That makes a chart simple, one object
  per bucket. But a second stack cannot add to a policy or a group's rules
  without owning the whole object (section 5, gap 6).
- The top gaps for `ack-extensions` are:
  1. a Lambda `Permission` kind;
  2. Secrets Manager rotation;
  3. RDS role associations;
  4. Auto Scaling policies and schedules;
  5. KMS replica keys;
  6. EBS volumes and attachments;
  7. VPN and customer gateways;
  8. CloudWatch Logs metric filters and composite alarms;
  9. EventBridge Scheduler and API destinations;
  10. ECR registry-level settings.
- **kro verdict: use Helm for nearly everything.** ACK's `*Ref` fields already
  wire IDs and ARNs between kinds inside one apply. Bundt itself computes
  readiness and outputs as CEL over live status (packages.md A11). kro is
  worth it for two packages, `eks` and `acm` with DNS validation. In both, a
  spec needs a live status value that no ACK reference carries
  (section 6).

## Sources and pins

Read on 2026-11-09 (UTC), read-only, with `gh api` and `curl`.

| Source | Pin |
| --- | --- |
| `gh api orgs/terraform-aws-modules/repos --paginate` | 2026-11-09 07:34 UTC |
| Terraform Registry v1, `GET /v1/modules/terraform-aws-modules/<name>/aws` (total downloads, root and submodule resources) | 2026-11-09 07:34 UTC |
| Terraform Registry v2, `GET /v2/modules/terraform-aws-modules/<name>/aws/downloads/summary` (week, month, year, total) | 2026-11-09 07:35 UTC |
| Module sources | each module's latest release tag; the tag's commit is in the ranking table |
| ACK controllers | each controller's latest GitHub release and its commit; table in section 4 |
| ACK maturity definitions | `aws-controllers-k8s/community` `docs/content/docs/community/releases.md` at `e9929a689eddbe9fc461272402f4fed125fa1a62` |
| ACK community issues | `gh search issues --repo aws-controllers-k8s/community`, 2026-11-09 |
| ack-extensions | `ack-extensions/docs/plan.md`, local, as of 2026-11-08 |
| kro | `kubernetes-sigs/kro` v0.9.4 at `4ba0e410fd8c87ff5d2df638b6942d46766995f7` |

**Ranking key.** Modules are ranked by downloads in the last year, from the
v2 summary. All-time totals favour old modules. GitHub stars are a second
signal only: atlantis, notify-slack and pricing have many stars and few
downloads.

**A registry quirk.** The v2 summary's `week` figure is nearly equal to its
`month` figure for every module (vpc: week 2,545,871, month 2,685,785). The
week figure looks wrong, so it is not used.

## 1. The organisation

- 62 repositories: 58 `terraform-aws-*` modules plus `meta`, `.github`,
  `atlantis-demo` and `terraform-provider-http`.
- Archived: `terraform-aws-s3-object`, `terraform-aws-ebs-optimized` and
  `terraform-provider-http`.
- **Licence.** Every module is Apache-2.0. GitHub reports `NOASSERTION` for
  `security-group` and `eventbridge`, but their `LICENSE` files are the Apache
  2.0 text. `eventbridge`'s file begins "Copyright 2021 Sven Lito". The others
  carry no copyright line. None of the top modules has a `NOTICE` file.

## 2. Ranking

"Year" is downloads in the last year. "Total" is all-time downloads. Both are
from the Terraform Registry on 2026-11-09.

| # | Module | Year | Total | Stars | Release, commit |
| --- | --- | --- | --- | --- | --- |
| 1 | [iam](https://registry.terraform.io/modules/terraform-aws-modules/iam/aws) | 119,564,916 | 440,704,638 | 876 | v6.8.2 `55514b7873c4` |
| 2 | [s3-bucket](https://registry.terraform.io/modules/terraform-aws-modules/s3-bucket/aws) | 80,555,319 | 248,720,295 | 590 | v5.17.0 `9afa4fc8c8f1` |
| 3 | [vpc](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws) | 69,036,256 | 229,752,996 | 3281 | v6.7.3 `b3abd6df2ecf` |
| 4 | [eks](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws) | 64,376,823 | 193,908,942 | 5015 | v21.29.0 `91f11ea01656` |
| 5 | [kms](https://registry.terraform.io/modules/terraform-aws-modules/kms/aws) | 62,311,808 | 157,651,716 | 53 | v4.2.2 `d25e459bd43d` |
| 6 | [lambda](https://registry.terraform.io/modules/terraform-aws-modules/lambda/aws) | 51,197,696 | 153,908,303 | 1043 | v8.13.0 `e73238631a03` |
| 7 | [security-group](https://registry.terraform.io/modules/terraform-aws-modules/security-group/aws) | 41,355,011 | 154,247,965 | 591 | v6.0.0 `58d8e895915f` |
| 8 | [rds](https://registry.terraform.io/modules/terraform-aws-modules/rds/aws) | 27,069,610 | 83,142,885 | 961 | v7.2.2 `175da043429c` |
| 9 | [rds-aurora](https://registry.terraform.io/modules/terraform-aws-modules/rds-aurora/aws) | 23,779,053 | 90,406,226 | 421 | v10.4.2 `652c0648a304` |
| 10 | [acm](https://registry.terraform.io/modules/terraform-aws-modules/acm/aws) | 23,606,983 | 73,492,448 | 206 | v6.3.1 `aae84c011dd6` |
| 11 | [ec2-instance](https://registry.terraform.io/modules/terraform-aws-modules/ec2-instance/aws) | 22,484,794 | 58,363,640 | 812 | v6.4.1 `294fb8928bc0` |
| 12 | [sqs](https://registry.terraform.io/modules/terraform-aws-modules/sqs/aws) | 21,692,594 | 58,539,510 | 105 | v5.2.2 `dd73a96c0155` |
| 13 | [route53](https://registry.terraform.io/modules/terraform-aws-modules/route53/aws) | 21,094,517 | 63,635,799 | 154 | v6.5.1 `883f987d6bb3` |
| 14 | [ecs](https://registry.terraform.io/modules/terraform-aws-modules/ecs/aws) | 19,998,875 | 40,179,700 | 677 | v7.6.1 `60b428812ddc` |
| 15 | [alb](https://registry.terraform.io/modules/terraform-aws-modules/alb/aws) | 19,656,755 | 61,459,747 | 467 | v10.5.1 `6c6e48c10d45` |
| 16 | [dynamodb-table](https://registry.terraform.io/modules/terraform-aws-modules/dynamodb-table/aws) | 16,954,878 | 39,882,327 | 117 | v5.5.2 `c38423ae6c92` |
| 17 | [eventbridge](https://registry.terraform.io/modules/terraform-aws-modules/eventbridge/aws) | 11,817,480 | 30,243,066 | 156 | v4.3.3 `e29707a5057e` |
| 18 | [cloudwatch](https://registry.terraform.io/modules/terraform-aws-modules/cloudwatch/aws) | 10,778,130 | 30,556,830 | 180 | v6.0.0 `f6dff9f79a5f` |
| 19 | [autoscaling](https://registry.terraform.io/modules/terraform-aws-modules/autoscaling/aws) | 10,768,106 | 28,649,488 | 311 | v9.3.2 `f90a581bcca0` |
| 20 | [secrets-manager](https://registry.terraform.io/modules/terraform-aws-modules/secrets-manager/aws) | 10,646,728 | 18,862,408 | 42 | v2.2.0 `f3d3da1c8018` |
| 21 | [cloudfront](https://registry.terraform.io/modules/terraform-aws-modules/cloudfront/aws) | 9,456,598 | 36,416,517 | 139 | v6.7.1 `5b9a0a480220` |
| 22 | [eks-pod-identity](https://registry.terraform.io/modules/terraform-aws-modules/eks-pod-identity/aws) | 8,495,394 | 12,050,786 | 106 | v2.10.0 `f72040b99272` |
| 23 | [ecr](https://registry.terraform.io/modules/terraform-aws-modules/ecr/aws) | 8,322,199 | 19,531,245 | 75 | v3.2.0 `b6ef04d088cf` |
| 24 | [sns](https://registry.terraform.io/modules/terraform-aws-modules/sns/aws) | 7,651,573 | 21,211,577 | 112 | v7.2.0 `4538b7e208f5` |
| 25 | [elasticache](https://registry.terraform.io/modules/terraform-aws-modules/elasticache/aws) | 7,393,809 | 10,961,035 | 32 | v1.11.2 `41a277b73b9d` |
| 26 | [key-pair](https://registry.terraform.io/modules/terraform-aws-modules/key-pair/aws) | 4,560,759 | 12,797,983 | 85 | v3.0.1 `f3221d392c43` |
| 27 | [ssm-parameter](https://registry.terraform.io/modules/terraform-aws-modules/ssm-parameter/aws) | 4,294,882 | 7,111,407 | 23 | |
| 28 | [step-functions](https://registry.terraform.io/modules/terraform-aws-modules/step-functions/aws) | 3,616,045 | 10,057,107 | 81 | |
| 29 | [efs](https://registry.terraform.io/modules/terraform-aws-modules/efs/aws) | 3,523,365 | 10,722,007 | 30 | v2.2.1 `e0ec33d84363` |
| 30 | [vpn-gateway](https://registry.terraform.io/modules/terraform-aws-modules/vpn-gateway/aws) | 3,206,707 | 6,396,959 | 117 | |
| 31 | [rds-proxy](https://registry.terraform.io/modules/terraform-aws-modules/rds-proxy/aws) | 2,778,921 | 6,922,624 | 60 | |
| 32 | [transit-gateway](https://registry.terraform.io/modules/terraform-aws-modules/transit-gateway/aws) | 2,078,861 | 6,362,624 | 163 | |
| 33 | [apigateway-v2](https://registry.terraform.io/modules/terraform-aws-modules/apigateway-v2/aws) | 2,008,915 | 6,735,371 | 165 | |
| 34 | [notify-slack](https://registry.terraform.io/modules/terraform-aws-modules/notify-slack/aws) | 1,812,555 | 7,828,719 | 500 | |
| 35 | [opensearch](https://registry.terraform.io/modules/terraform-aws-modules/opensearch/aws) | 1,505,196 | 2,830,741 | 29 | |
| 36 | [msk-kafka-cluster](https://registry.terraform.io/modules/terraform-aws-modules/msk-kafka-cluster/aws) | 1,437,921 | 2,994,991 | 61 | |
| 37 | [managed-service-prometheus](https://registry.terraform.io/modules/terraform-aws-modules/managed-service-prometheus/aws) | 1,305,164 | 1,374,676 | 34 | |
| 38 | [datadog-forwarders](https://registry.terraform.io/modules/terraform-aws-modules/datadog-forwarders/aws) | 1,180,148 | 3,090,088 | 66 | |
| 39 | [dms](https://registry.terraform.io/modules/terraform-aws-modules/dms/aws) | 759,615 | 2,284,862 | 74 | |
| 40 | [network-firewall](https://registry.terraform.io/modules/terraform-aws-modules/network-firewall/aws) | 606,792 | 5,214,935 | 20 | |

The full commit SHAs, by tag:

- iam `55514b7873c411040395e024a422684998da77c2`
- s3-bucket `9afa4fc8c8f1e0b3fd913474c1bef8d0c454b235`
- vpc `b3abd6df2ecf052451a361ed55b8f06f8742a795`
- eks `91f11ea01656c26b8e6b8eb1b74f19863f60056c`
- kms `d25e459bd43d8d0bdff7c250ba6b237a12be7381`
- security-group `58d8e895915f5573767081142d063b7caf7a2b47`
- lambda `e73238631a030105fc8d09789033cc0bfed83310`
- rds-aurora `652c0648a304e04bb53b5411874f519ace3585b6`
- rds `175da043429cbbe41c512f976105719f6d0e538c`
- acm `aae84c011dd68ace1beb5d10e1feddfe9a334953`
- route53 `883f987d6bb328c09bd4dfc5a04024534b371d59`
- alb `6c6e48c10d450d01cf6715346e926df0b858efc2`
- sqs `dd73a96c0155bc324dda5256f3e7a9ea2c710195`
- ec2-instance `294fb8928bc0f7e0d9ba5bea41a8236c9a7a95d9`
- ecs `60b428812ddcffe48abc6af0988fe826c89da961`
- dynamodb-table `c38423ae6c92825e7cc4376c7f81deb20a676f2b`
- cloudfront `5b9a0a480220b84f29f02d84ff71dd5340953f68`
- cloudwatch `f6dff9f79a5f4d2653b359182364f30db638ad48`
- eventbridge `e29707a5057ec9b0f6ea87686e9a5b48b4addd11`
- autoscaling `f90a581bcca0bab571022a021db155f2860e9b32`
- sns `4538b7e208f5bbd6c9972f427f85c9bd735aedad`
- ecr `b6ef04d088cf91d5ba9505132e9ff7c9f847ed5d`
- secrets-manager `f3d3da1c801816563080065c5f37f212c8dee444`
- key-pair `f3221d392c436a874f189aa2d217d4aff60eb05e`
- eks-pod-identity `f72040b99272c264e0340f44758219e0808a52a2`
- elasticache `41a277b73b9d375a2856886ab8469fd3f8b6d0ef`
- efs `e0ec33d8436363960395b859aff0168ce25c27a4`

## 3. The top 25, module by module

Resources come from the registry's parse of each module at its tag. ACK kinds
are written `controller/Kind`. "inline" means the Terraform resource is a
field of the ACK kind on the left, such as `s3/Bucket.lifecycle`. **GAP**
means no ACK kind or field exists at the controller's latest release.
`ack-ext` means `ack-extensions` has built it. Terraform-only resources
(`null_resource`, `local_file`, `random_*`, `time_sleep`, `terraform_data`,
`tls_private_key`) are left out unless they matter.

### 1. iam (v6.8.2)

The root has no resources; everything is in submodules. A chart per
submodule is the natural port.

| Submodule | Creates | ACK |
| --- | --- | --- |
| `iam-role` | role, inline policy, policy attachment, instance profile | `iam/Role` (with `inlinePolicies` and `policies`/`policyRefs` inline), `iam/InstanceProfile`. Attaching a policy to a role the chart does not own: `ack-ext` `RolePolicyAttachment` |
| `iam-role-for-service-accounts` | IRSA role with policies | `iam/Role`, `iam/Policy`. Its trust policy needs the cluster's OIDC issuer (section 6) |
| `iam-policy`, `iam-read-only-policy` | managed policy | `iam/Policy` |
| `iam-oidc-provider` | OIDC provider | `iam/OpenIDConnectProvider` |
| `iam-user` | user, access key, login profile, SSH key, policies | `iam/User` (policies inline). **GAP**: `AccessKey`, `LoginProfile`, `SSHPublicKey` |
| `iam-group` | group, membership, policy attachments, policy | `iam/Group` (policies inline), `iam/Policy`. **GAP**: group membership (neither `Group` nor `User` has a members or groups field) |
| `iam-account` | account alias, password policy | **GAP**: `AccountAlias`, `AccountPasswordPolicy` |

Coverage: the role and policy half, which is what application stacks use, is
covered. The user and account half is not. That half is for people, and
belongs more in an identity system than in a cluster.

### 2. s3-bucket (v5.17.0)

| Submodule | Creates | ACK |
| --- | --- | --- |
| root | bucket and 20 bucket configurations (ACL, CORS, lifecycle, logging, versioning, encryption, policy, public access block, ownership, replication, website, object lock, inventory, analytics, metrics, intelligent tiering, request payment, accelerate) | `s3/Bucket`, with every configuration inline. **GAP**: `aws_s3_bucket_metadata_configuration`, `aws_s3_directory_bucket` (S3 Express) |
| `notification` | bucket notification, SQS and SNS policies, Lambda permission | `s3/Bucket.notification`, `sqs/Queue.policy`, `sns/Topic.policy`. **GAP**: Lambda permission (gap 1) |
| `object` | S3 object | **GAP** (no object kind; arguably not infrastructure) |
| `account-public-access` | account-wide public access block | **GAP** (`s3control` has only `AccessPoint`) |
| `table-bucket` | S3 Tables bucket, table, policies | `s3tables/TableBucket`, `s3tables/Table`, `s3tables/Namespace` (v1.4.0). Policies not confirmed |
| `vectors` | S3 Vectors bucket, index, policy | `s3vectors/VectorBucket`, `s3vectors/Index` (v1.4.0). Policy not confirmed |
| `file-system` | S3 Files file system, mount targets, access points, sync, IAM, security group | `s3files/FileSystem`, `s3files/MountTarget`, `s3files/AccessPoint` (v1.4.0), `iam/Role`, `ec2/SecurityGroup`. Policy and synchronization configuration not confirmed |

### 3. vpc (v6.7.3)

| Submodule | Creates | ACK (`ec2` unless noted) |
| --- | --- | --- |
| root | VPC, extra CIDR blocks, subnets (public, private, database, ElastiCache, Redshift, intra, outpost), route tables, routes, associations, IGW, egress-only IGW, NAT gateways, EIPs, NACLs and rules, DHCP options, flow log, subnet groups for RDS, ElastiCache and Redshift, VPN gateway, its attachment and route propagation, customer gateways, default VPC, NACL, route table and security group, VPC block public access | `VPC` (`cidrBlocks` inline), `Subnet`, `RouteTable` (`routes` inline, subnet association by `Subnet.routeTableRefs`), `InternetGateway`, `EgressOnlyInternetGateway`, `NATGateway`, `ElasticIPAddress`, `NetworkACL` (entries inline), `DHCPOptions`, `FlowLog`, `rds/DBSubnetGroup`, `elasticache/CacheSubnetGroup`. **GAP**: `VPNGateway` with attachment and route propagation, `CustomerGateway`, block public access, Redshift subnet group (the `redshift-controller` has no release). The default resources can be adopted (ACK's adoption annotations) rather than created |
| `vpc-endpoints` | endpoints, security group | `VPCEndpoint`, `SecurityGroup` |
| `flow-log` | flow log, log group, IAM | `FlowLog`, `cloudwatchlogs/LogGroup`, `iam/Role`, `iam/Policy` |

### 4. eks (v21.29.0)

| Submodule | Creates | ACK |
| --- | --- | --- |
| root | cluster, add-ons, access entries and policy associations, identity provider config, OIDC provider, cluster IAM role and policies, security groups and rules, log group, `aws_ec2_tag` | `eks/Cluster`, `eks/Addon`, `eks/AccessEntry` (`accessPolicies` inline), `eks/IdentityProviderConfig`, `iam/OpenIDConnectProvider`, `iam/Role`, `iam/Policy`, `ec2/SecurityGroup` (rules inline), `cloudwatchlogs/LogGroup`. **GAP**: `aws_ec2_tag`, which tags a resource the chart does not own |
| `eks-managed-node-group` | node group, launch template, IAM, security group, placement group | `eks/Nodegroup`, `ec2/LaunchTemplate`, `iam/Role`, `ec2/SecurityGroup`. **GAP**: placement group |
| `self-managed-node-group` | ASG, launch template, instance profile, access entry, IAM, SG, placement group | `autoscaling/AutoScalingGroup`, `ec2/LaunchTemplate`, `iam/InstanceProfile`, `eks/AccessEntry`, `iam/Role`, `ec2/SecurityGroup`. **GAP**: placement group |
| `fargate-profile` | Fargate profile, IAM | `eks/FargateProfile`, `iam/Role` |
| `karpenter` | SQS queue and policy, EventBridge rules and targets, IAM role and policy, instance profile, access entry, pod identity association | `sqs/Queue` (`policy` inline), `eventbridge/Rule` (`targets` inline), `iam/Role`, `iam/Policy`, `iam/InstanceProfile`, `eks/AccessEntry`, `eks/PodIdentityAssociation`. Fully covered |
| `capability` | EKS capability, IAM | `eks/Capability`, `iam/Role` |
| `hybrid-node-role` | IAM, Roles Anywhere trust anchor and profile | `iam/Role`. **GAP**: Roles Anywhere (`rolesanywhere-controller` exists but is empty and unreleased) |

The chart itself is well covered. What makes it hard is wiring: section 6.

### 5. kms (v4.2.2)

| Submodule | Creates | ACK |
| --- | --- | --- |
| root | key, aliases, grants, external key, replica key, replica external key | `kms/Key`, `kms/Alias`, `kms/Grant`. **GAP**: external and replica keys (`kms-controller` PR #112, per ack-extensions plan) |

### 6. lambda (v8.13.0)

| Submodule | Creates | ACK |
| --- | --- | --- |
| root | function, layer version, event source mappings, function URL, permissions, provisioned concurrency, event invoke config, recursion config, IAM role and policies, log group, and **local packaging** (`null_resource`, `local_file`, an S3 upload) | `lambda/Function` (`functionEventInvokeConfig` inline), `lambda/LayerVersion`, `lambda/EventSourceMapping`, `lambda/FunctionURLConfig`, `lambda/Version` (`provisionedConcurrencyConfig` inline), `iam/Role`, `cloudwatchlogs/LogGroup`. **GAP**: `Permission` (resource-based policy; issues #3051 and #2659 open). Recursion config is not a `Function` field |
| `alias` | alias, its permissions, ESM, invoke config | `lambda/Alias` (`permissions` inline: the hook code for `AddPermission` exists here, on aliases only), `lambda/EventSourceMapping` |
| `deploy` | CodeDeploy app and deployment group, IAM | **GAP**: there is no ACK CodeDeploy controller |
| `docker-build` | ECR repository and lifecycle, Docker build and push | `ecr/Repository`. The build is not portable: a Package takes a built image or zip by reference |

**Porting note.** The module's central feature is building the deployment
package on the machine running Terraform. A chart cannot do that. The
Package must take `code.s3Bucket`/`s3Key` or `imageURI` as values. The build
belongs in the team's CI.

### 7. security-group (v6.0.0)

| Submodule | Creates | ACK |
| --- | --- | --- |
| root | security group, ingress and egress rules (`aws_vpc_security_group_*_rule`), exclusive rules, VPC association | `ec2/SecurityGroup` (`ingressRules` and `egressRules` inline). **GAP**: VPC association. There are no standalone rule kinds |
| 53 submodules (`http-80`, `ssh`, `postgresql`, `redis`, ...) | none of their own: each calls the root with a preset rule set | one chart with presets in its values, not 53 Packages |

### 8. rds (v7.2.2)

| Submodule | Creates | ACK |
| --- | --- | --- |
| `db_instance` | instance, monitoring role, log groups, secret rotation | `rds/DBInstance` (`manageMasterUserPassword` inline), `iam/Role`, `cloudwatchlogs/LogGroup`. **GAP**: rotation of the managed master secret (`secretsmanager-controller` PR #69, a field) |
| `db_subnet_group` | subnet group | `rds/DBSubnetGroup` |
| `db_parameter_group` | parameter group | `rds/DBParameterGroup` |
| `db_option_group` | option group | `ack-ext` `rds.aws.hfl.dev/OptionGroup` (from `rds-controller` PR #257) |
| `db_instance_role_association` | role association | **GAP** (ack-extensions "next") |
| `db_instance_automated_backups_replication` | cross-region backup replication | **GAP** |

### 9. rds-aurora (v10.4.2)

| Submodule | Creates | ACK |
| --- | --- | --- |
| root | cluster, cluster instances, custom endpoints, cluster and DB parameter groups, subnet group, security group, monitoring role, read-replica autoscaling, log groups, role association, activity stream, shard group, secret rotation | `rds/DBCluster`, `rds/DBInstance` (with `dbClusterIdentifier`), `rds/DBClusterEndpoint`, `rds/DBClusterParameterGroup`, `rds/DBParameterGroup`, `rds/DBSubnetGroup`, `ec2/SecurityGroup`, `iam/Role`, `applicationautoscaling/ScalableTarget`, `applicationautoscaling/ScalingPolicy`, `cloudwatchlogs/LogGroup`. **GAP**: role association, activity stream, shard group, rotation |
| `dsql` | Aurora DSQL cluster, peering, policy | `dsql/Cluster` (v1.4.0). **GAP**: peering, policy |

### 10. acm (v6.3.1)

| Submodule | Creates | ACK |
| --- | --- | --- |
| root | certificate, DNS validation records, the validation wait | `acm/Certificate`, `route53/RecordSet`. There is no validation kind: `Certificate` reports `ISSUED` in status once validated. The records' names and values exist only in `Certificate`'s status, so the chart must wire status into new objects (section 6) |

### 11. ec2-instance (v6.4.1)

| Creates | ACK |
| --- | --- |
| instance, spot instance request, EIP, EBS volumes and attachments, instance profile and IAM, security group, `aws_ec2_tag` | `ec2/Instance`, `ec2/ElasticIPAddress`, `iam/InstanceProfile`, `iam/Role`, `ec2/SecurityGroup`. **GAP**: `Volume` and `VolumeAttachment` (`ebs-controller` exists, with no CRDs and no release), spot instance request, `aws_ec2_tag` |

### 12. sqs (v5.2.2)

| Creates | ACK |
| --- | --- |
| queue, queue policy, redrive policy, redrive allow policy | `sqs/Queue` (`policy`, `redrivePolicy` and `redriveAllowPolicy` inline). Fully covered |

### 13. route53 (v6.5.1)

| Submodule | Creates | ACK |
| --- | --- | --- |
| root | zone, records, DNSSEC, key-signing key, VPC association authorization | `route53/HostedZone`, `route53/RecordSet`. **GAP**: DNSSEC, `KeySigningKey`, VPC association authorization (all ignored in ACK's generator, per ack-extensions plan) |
| `resolver-endpoint` | resolver endpoint, rules, associations, SG | `route53resolver/ResolverEndpoint`, `ResolverRule`, `ResolverRuleAssociation`, `ec2/SecurityGroup` |
| `resolver-firewall-rule-group` | firewall domain list, rule group, rules, RAM share | `ram/ResourceShare`. **GAP**: Resolver DNS Firewall |
| `delegation-sets` | reusable delegation set | **GAP** |

### 14. ecs (v7.6.1)

| Submodule | Creates | ACK |
| --- | --- | --- |
| `cluster` | cluster, capacity providers and their association, IAM, instance profile, SG, log group | `ecs/Cluster` (`capacityProviders` and `defaultCapacityProviderStrategy` inline), `ecs/CapacityProvider`, `iam/Role`, `iam/InstanceProfile`, `ec2/SecurityGroup`, `cloudwatchlogs/LogGroup` |
| `service` | service, task definition, task set, autoscaling target, policies and scheduled actions, IAM, SG | `ecs/Service`, `ecs/TaskDefinition`, `applicationautoscaling/ScalableTarget`, `ScalingPolicy`, `iam/Role`, `ec2/SecurityGroup`. **GAP**: task set, scheduled actions |
| `container-definition` | log group (the definition is JSON passed to the service) | `cloudwatchlogs/LogGroup`; the definition becomes a values helper |
| `express-service` | ECS Express gateway service, IAM, SG, logs | **GAP**: express gateway service |

### 15. alb (v10.5.1)

| Submodule | Creates | ACK |
| --- | --- | --- |
| root | load balancer, listeners, listener rules, listener certificates, target groups and attachments, SG, Route 53 records, WAF association, Lambda permission | `elbv2/LoadBalancer`, `elbv2/Listener` (`certificates` inline), `elbv2/Rule`, `elbv2/TargetGroup` (`targets` inline), `ec2/SecurityGroup`, `route53/RecordSet`. **GAP**: WAFv2 web ACL association, Lambda permission. Not checked: whether `Listener.certificates` handles extra certificates (`AddListenerCertificates`) or only the default |
| `lb_trust_store` | trust store and revocations (mTLS) | **GAP** |

### 16. dynamodb-table (v5.5.2)

| Creates | ACK |
| --- | --- |
| table, resource policy, autoscaling targets and policies | `dynamodb/Table` (`resourcePolicy`, `tableReplicas`, `timeToLive` and `continuousBackups` inline), `applicationautoscaling/ScalableTarget`, `ScalingPolicy`. Fully covered |

### 17. eventbridge (v4.3.3)

| Creates | ACK |
| --- | --- |
| buses, rules, targets, archives, permissions, connections, API destinations, pipes, Scheduler schedules and groups, schema discoverer, log delivery, IAM | `eventbridge/EventBus`, `eventbridge/Rule` (`targets` inline), `eventbridge/Archive`, `pipes/Pipe`, `cloudwatchlogs/Delivery*`, `iam/Role`, `iam/Policy`. **GAP**: `Connection`, `ApiDestination`, bus `Permission`, Scheduler `Schedule` and `ScheduleGroup` (there is no Scheduler controller; issue #2784 open), schema discoverer |

### 18. cloudwatch (v6.0.0)

Thirteen submodules, one resource each:

| Submodule | ACK |
| --- | --- |
| `log-group` | `cloudwatchlogs/LogGroup` |
| `log-subscription-filter` | `LogGroup.subscriptionFilters` inline |
| `metric-alarm`, `metric-alarms-by-multiple-dimensions` | `cloudwatch/MetricAlarm` |
| `metric-stream` | `cloudwatch/MetricStream` |
| `log-metric-filter` | **GAP** (`cloudwatchlogs` PR #61) |
| `cis-alarms` | **GAP**: needs metric filters, then `MetricAlarm` |
| `composite-alarm` | **GAP** |
| `log-stream` | **GAP** |
| `query-definition` | **GAP** |
| `log-anomaly-detector` | **GAP** |
| `log-account-policy` | **GAP** |
| `log-data-protection-policy` | **GAP** |

### 19. autoscaling (v9.3.2)

| Creates | ACK |
| --- | --- |
| ASG, launch template, scaling policies, schedules, traffic source attachments, instance profile and IAM | `autoscaling/AutoScalingGroup` (`trafficSources`, `targetGroupRefs` and lifecycle hooks inline), `ec2/LaunchTemplate`, `iam/InstanceProfile`, `iam/Role`. **GAP**: scaling `Policy` and `ScheduledAction` (`autoscaling-controller` v1.5.0 has only `AutoScalingGroup`) |

### 20. secrets-manager (v2.2.0)

| Creates | ACK |
| --- | --- |
| secret, version, policy, rotation | `secretsmanager/Secret` (value from a Kubernetes Secret via `secretString`). **GAP**: resource policy (ack-extensions "next"), rotation (PR #69) |

### 21. cloudfront (v6.7.1)

| Submodule | Creates | ACK |
| --- | --- | --- |
| root | distribution, cache, origin-request and response-headers policies, functions, origin access control, VPC origins, monitoring subscription, connection function, log delivery | `cloudfront/Distribution`, `CachePolicy`, `OriginRequestPolicy`, `ResponseHeadersPolicy`, `Function`, `OriginAccessControl`, `VPCOrigin`, `cloudwatchlogs/Delivery`, `DeliverySource`, `DeliveryDestination`. **GAP**: monitoring subscription, connection function |
| `trust_store` | CloudFront trust store | **GAP** |

### 22. eks-pod-identity (v2.10.0)

| Creates | ACK |
| --- | --- |
| pod identity association, IAM role and policies | `eks/PodIdentityAssociation`, `iam/Role`, `iam/Policy`. Fully covered. Its value is about 40 preset policies (EBS CSI, Karpenter, external-dns, ...): port those as values presets |

### 23. ecr (v3.2.0)

| Submodule | Creates | ACK |
| --- | --- | --- |
| root | repository, repository policy, lifecycle policy, pull-through cache rules, registry policy, registry scanning, replication, ECR Public repository and policy | `ecr/Repository` (`policy` and `lifecyclePolicy` inline), `ecr/PullThroughCacheRule`, `ecrpublic/Repository`. **GAP**: registry policy, registry scanning configuration, replication configuration (PR #121) |
| `repository-template` | creation template, pull-through rule, IAM | `ecr/RepositoryCreationTemplate`, `ecr/PullThroughCacheRule`, `iam/Role` |

### 24. sns (v7.2.0)

| Creates | ACK |
| --- | --- |
| topic, policy, data protection policy, subscriptions | `sns/Topic` (`policy` and `dataProtectionPolicy` inline), `sns/Subscription`. Fully covered |

### 25. elasticache (v1.11.2)

| Submodule | Creates | ACK |
| --- | --- | --- |
| root | cluster, replication group, global replication group, parameter group, subnet group, SG, log groups | `elasticache/CacheCluster`, `ReplicationGroup`, `CacheParameterGroup`, `CacheSubnetGroup`, `ec2/SecurityGroup`, `cloudwatchlogs/LogGroup`. **GAP**: `GlobalReplicationGroup` (PR #237) |
| `user-group` | users, user group, association | `elasticache/User`, `elasticache/UserGroup` (users inline) |
| `serverless-cache` | serverless cache | `elasticache/ServerlessCache` |

### Just below the top 25

- **key-pair** (26): EC2 key pair. **GAP**, PR #396.
- **ssm-parameter** (27): `ssm/Parameter`. Covered.
- **step-functions** (28): `sfn/StateMachine`, `Activity`, `StateMachineAlias`. Covered.
- **efs** (29): `efs/FileSystem` (policy, backup policy and replication inline), `MountTarget`, `AccessPoint`. Covered.
- **rds-proxy** (31): `rds/DBProxy`, plus `ack-ext` `DBProxyTarget`. Still missing: proxy endpoints and the default target group's settings.

## 4. The ACK controllers used

**Maturity** follows ACK's `releases.md`: a controller is **GA** when it
releases with major version 1 or more (`1.x`), and **preview** at `0.x`.
Every API is still `v1alpha1`, even in GA controllers. Each tag below is the
controller's latest GitHub release on 2026-11-09.

| Controller | Release | Commit | Maturity | Kinds (CRD plural names) |
| --- | --- | --- | --- | --- |
| iam | v1.11.3 | `538aed660e54` | GA | groups, instanceprofiles, openidconnectproviders, policies, roles, servicelinkedroles, users |
| s3 | v1.15.0 | `e679633287f9` | GA | buckets |
| ec2 | v1.23.1 | `9303654c2cff` | GA | capacityreservations, dhcpoptions, egressonlyinternetgateways, elasticipaddresses, flowlogs, instances, internetgateways, launchtemplates, managedprefixlists, natgateways, networkacls, routetables, securitygroups, subnets, transitgateways, transitgatewayvpcattachments, vpcendpoints, vpcendpointserviceconfigurations, vpcpeeringconnections, vpcs |
| eks | v1.26.0 | `2549d1be1a9f` | GA | accessentries, addons, capabilities, clusters, fargateprofiles, identityproviderconfigs, nodegroups, podidentityassociations |
| kms | v1.7.0 | `57250fba83d5` | GA | aliases, grants, keys |
| lambda | v1.19.0 | `86905357482d` | GA | aliases, codesigningconfigs, eventsourcemappings, functions, functionurlconfigs, layerversions, versions |
| rds | v1.14.2 | `8ee2451cc31e` | GA | dbclusterendpoints, dbclusterparametergroups, dbclusters, dbclustersnapshots, dbinstances, dbparametergroups, dbproxies, dbsnapshots, dbsubnetgroups, globalclusters |
| acm | v1.11.0 | `ae641dedff0e` | GA | certificates, acmedomainvalidations, acmeendpoints, acmeexternalaccountbindings |
| route53 | v1.8.0 | `73c2b0e3ccf4` | GA | healthchecks, hostedzones, recordsets |
| route53resolver | v1.11.0 | `3b7ef2f717c4` | GA | resolverendpoints, resolverquerylogconfigs, resolverquerylogconfigassociations, resolverrules, resolverruleassociations |
| sqs | v1.9.0 | `0810c99dd5b0` | GA | queues |
| sns | v1.13.0 | `a1f0e5b19582` | GA | platformapplications, platformendpoints, subscriptions, topics |
| ecs | v1.9.2 | `92029ad47285` | GA | capacityproviders, clusters, services, taskdefinitions |
| elbv2 | v1.9.0 | `7d61ceb05889` | GA | listeners, loadbalancers, rules, targetgroups |
| dynamodb | v1.14.2 | `2fcea71a4f8d` | GA | backups, globaltables, tables |
| applicationautoscaling | v1.9.0 | `009baef3a28e` | GA | scalabletargets, scalingpolicies |
| autoscaling | v1.5.0 | `56316c75a5da` | GA | autoscalinggroups |
| eventbridge | v1.9.2 | `fd084a0bb4d9` | GA | archives, endpoints, eventbuses, rules |
| pipes | v1.8.0 | `08b598079c25` | GA | pipes |
| cloudwatch | v1.11.0 | `091119726675` | GA | dashboards, metricalarms, metricstreams |
| cloudwatchlogs | v1.10.0 | `01e3ea012e97` | GA | deliveries, deliverydestinationpolicies, deliverydestinations, deliverysources, loggroups, resourcepolicies |
| secretsmanager | v1.8.2 | `dc099cdc08aa` | GA | secrets |
| cloudfront | v1.10.1 | `6b828699fe89` | GA | cachepolicies, connectiongroups, distributions, distributiontenants, functions, originaccesscontrols, originrequestpolicies, responseheaderspolicies, vpcorigins |
| ecr | v1.11.1 | `72590cedeb2a` | GA | pullthroughcacherules, repositories, repositorycreationtemplates |
| ecrpublic | v1.7.0 | `898fd47a6364` | GA | repositories |
| elasticache | v1.12.0 | `c1c4c0897b82` | GA | cacheclusters, cacheparametergroups, cachesubnetgroups, replicationgroups, serverlesscaches, serverlesscachesnapshots, snapshots, usergroups, users |
| efs | v1.8.0 | `1ebcaad2c889` | GA | accesspoints, filesystems, mounttargets |
| ssm | v1.8.0 | `d07ea0193aef` | GA | documents, parameters, patchbaselines, resourcedatasyncs |
| sfn | v1.9.1 | `8de3cc822d99` | GA | activities, statemachinealiases, statemachines |
| wafv2 | v1.8.1 | `d910e96f94d5` | GA | ipsets, rulegroups, webacls (no association kind) |
| ram | v1.7.0 | `97f62cacffe7` | GA | permissions, resourceshares |
| s3control | v1.9.0 | `2ee9ccbfaaaa` | GA | accesspoints |
| s3tables | v1.4.0 | `1b42f56b0091` | GA | namespaces, tablebuckets, tables |
| s3vectors | v1.4.0 | `90f3dd3381ed` | GA | indices, vectorbuckets |
| s3files | v1.4.0 | `65bf22917a90` | GA | accesspoints, filesystems, mounttargets |
| dsql | v1.4.0 | `881f8c7b2a79` | GA | clusters |
| networkfirewall | v1.7.0 | `6d7cec5f8948` | GA | firewallpolicies, firewalls, rulegroups |
| kafka | v1.14.0 | `7264a328ebd2` | GA | clusters, configurations, serverlessclusters, vpcconnections |
| opensearchservice | v1.9.0 | `ffa3379859d8` | GA | domains, vpcendpointaccesses, vpcendpoints |
| memorydb | v1.9.0 | `8b533f3b1260` | GA | acls, clusters, parametergroups, snapshots, subnetgroups, users |

Controllers that a top module would need but that have no release:
`rolesanywhere` (an empty repository), `ebs` (no CRDs), `redshift`, `batch`
and `vpclattice`. There are no controllers at all for EventBridge Scheduler
or CodeDeploy. The preview (`0.x`) controllers are firehose v0.8.1, dms
v0.4.1, emr v0.4.0 and fsx v0.1.0. None of them is needed in the top 25.

## 5. Gaps ranked for ack-extensions

Ranked by how many top-25 modules need the gap. Ties are broken by whether
the need is core to the module and by the module's downloads. "Core" means
the module's main use needs it. "Optional" means a feature toggle needs it.

| # | Gap | Top-25 modules needing it | Core? | Upstream state | Shape |
| --- | --- | --- | --- | --- | --- |
| 1 | Lambda `Permission` (`AddPermission`/`RemovePermission` on a function) | lambda (6), alb (15), s3-bucket `notification` (2) | core for triggers (S3, ALB, EventBridge and SNS invoking a function) | issues #3051 and #2659 open, no PR found. `Alias.permissions` already wraps the same API | hand-written, like `RolePolicyAttachment` |
| 2 | Secrets Manager rotation (`RotateSecret` on `Secret`) | rds (8), rds-aurora (9), secrets-manager (20) | optional | PR #69 | a field on an existing kind: ack-extensions open question 1 |
| 3 | RDS role associations (`AddRoleToDBInstance`/`AddRoleToDBCluster`) | rds (8), rds-aurora (9) | optional (S3 import and export, Lambda) | none | "next" in ack-extensions; moto supports it |
| 4 | Auto Scaling `Policy` and `ScheduledAction` (EC2 Auto Scaling); Application Auto Scaling `ScheduledAction` | autoscaling (19), ecs `service` (14) | core for autoscaling (without policies the group does not scale) | none found | generated: `PutScalingPolicy` and `PutScheduledUpdateGroupAction` are put/describe/delete shapes |
| 5 | KMS `ReplicaKey`, `ExternalKey` | kms (5) | optional (multi-region) | PR #112 | generated |
| 6 | Standalone security group rules (`AuthorizeSecurityGroupIngress`/`Egress` as their own objects) | security-group (7), and every module that adds a rule to a group it does not own (eks node and cluster groups, alb to targets) | core when stacks share a group | ACK has had SG reconciliation incidents (issues #2951, #2822, both closed) | design question: a rule kind would fight `SecurityGroup.ingressRules`, like `RolePolicyAttachment` against `Role.policies` (ack-extensions section 6.1) |
| 7 | EC2 `VPNGateway` (with attachment and route propagation), `CustomerGateway` | vpc (3); also vpn-gateway (30), customer-gateway | optional | none | generated (EC2 create/describe/delete) |
| 8 | EBS `Volume`, `VolumeAttachment` | ec2-instance (11) | optional | `ebs-controller` repository exists, empty | generated, but belongs upstream |
| 9 | CloudWatch Logs `MetricFilter`; CloudWatch `CompositeAlarm`; `LogStream`, `QueryDefinition`, anomaly detector, account and data-protection policies | cloudwatch (18) | core for its `log-metric-filter`, `cis-alarms` and `composite-alarm` submodules | PR #61 (metric filters) | generated |
| 10 | EventBridge Scheduler `Schedule` and `ScheduleGroup`; EventBridge `Connection`, `ApiDestination`, bus `Permission` | eventbridge (17) | optional | Scheduler controller requested (issue #2784) | Scheduler is a new controller; the others extend `eventbridge` |
| 11 | ECR `ReplicationConfiguration`, `RegistryPolicy`, `RegistryScanningConfiguration` | ecr (23) | optional; account-wide singletons | PR #121 (replication) | generated, singleton |
| 12 | WAFv2 `WebACLAssociation` | alb (15) | optional | none | hand-written (`AssociateWebACL`) |
| 13 | ElastiCache `GlobalReplicationGroup` | elasticache (25) | optional | PR #237 | generated |
| 14 | Route 53 DNSSEC and `KeySigningKey`; VPC association authorization; Resolver DNS Firewall | route53 (13) | optional | ignored in ACK's generator | generated |
| 15 | IAM `GroupMembership`, `AccessKey`, `LoginProfile`, `SSHPublicKey`, account alias and password policy | iam (1) | core for `iam-user`, `iam-group` and `iam-account`, which are for people, not workloads | none | `AccessKey` returns a secret once: needs a Secret write-back |
| 16 | EC2 `PlacementGroup` | eks node groups (4) | optional | none | generated |
| 17 | S3 `Object`, directory buckets, account public access block | s3-bucket (2) | optional | none | |
| 18 | EC2 `KeyPair` | key-pair (26) | core for that module | PR #396 | |

Already built in ack-extensions:

- `RolePolicyAttachment` serves iam's `iam-role` and eks for roles the chart
  does not own.
- `OptionGroup` serves rds `db_option_group`.
- `DBProxyTarget` serves rds-proxy (31).

Not counted as gaps:

- **`aws_ec2_tag`** (eks, ec2-instance) tags resources the chart does not own.
- **Build steps.** The lambda packaging and `docker-build` are not
  infrastructure.

## 6. kro verdict for AWS

**Default: Helm, with `manifests` where there is no logic.** kro is worth it
for **eks** and for **acm with DNS validation**, and nowhere else in the
top 25.

kro offers three things:

1. wiring one resource's live status into another's spec;
2. collections (`forEach`) over lists;
3. an aggregated status.

On AWS with Bundt, most of this is already covered:

- **Wiring by ID or ARN is already in ACK.** Generated kinds have `*Ref`
  fields that ACK's runtime resolves inside one apply. Examples:
  `Subnet.vpcRef`, `RouteTable.vpcRef`, `NATGateway` subnet and allocation
  refs, `Listener.loadBalancerRef`, `Function.roleRef`, `Queue.kmsMasterKeyRef`,
  `DBInstance.dbSubnetGroupRef`, `AccessEntry.clusterRef`,
  `TargetGroup.vpcRef` and `AutoScalingGroup.targetGroupRefs`. A chart that
  writes the refs gets the right order and the right ARNs without kro.
- **Fan-out from inputs is plain Helm.** vpc's subnets, route tables and NAT
  gateways per availability zone are known when the plan renders. Helm
  `range` covers them.
- **Aggregated status and outputs are Bundt's job.** Bundt reads readiness
  from the standard `Ready` condition, which ACK's runtime defines beside
  `ACK.ResourceSynced` (runtime v0.67.0, `apis/core/v1alpha1/conditions.go`).
  It computes outputs as CEL over the rendered resources' live status
  (packages.md R8, A11). A kro instance's status adds nothing here.
- **Wiring between Packages** is the Template's `valueFrom`.

kro wins only when a spec inside one Package needs a live status value that
no ACK reference carries:

- **eks.** Several links have no ref:
  - The IRSA `OpenIDConnectProvider.url`, and every IRSA role's trust
    policy, need `Cluster.status.identity.oidc.issuer`.
  - `AccessEntry.principalARN` is a plain string with no ref (its spec
    fields are `accessPolicies`, `clusterName`, `clusterRef`,
    `kubernetesGroups`, `principalARN`, `tags`, `type` and `username`). So a
    node role's ARN must be copied from `Role.status`.
  - Karpenter and self-managed node user data need the cluster's endpoint
    and CA from status.

  Splitting eks into several Packages joined by `valueFrom` also works, but
  it turns one Terraform module into a Template of four or five Packages.
  For teams moving from Terraform, a kro graph that keeps the module's shape
  is the better port.
- **acm with DNS validation.** The records to create are the
  `Certificate.status.domainValidations[].resourceRecord` entries. That is a
  `forEach` over a status list, which is kro's collections feature. The
  alternative is two Packages, `acm-certificate` and `route53-records`, with
  a list-valued output wired by `valueFrom`. That only works if Bundt outputs
  may be lists. Templates R20 allows list-typed expressions as whole values.
- **iam-role-for-service-accounts**, when shipped inside the eks graph, for
  the same issuer reason. As a standalone Package it takes the issuer as an
  input, and needs no kro.

**No kro for these:** vpc, rds, rds-aurora, lambda, alb, ecs, s3-bucket, sqs,
sns, dynamodb-table, cloudfront, elasticache, ecr, kms, security-group,
eventbridge, cloudwatch, autoscaling, secrets-manager and eks-pod-identity.
Their wiring is ACK refs, Helm `range` or values.

**kro's maturity:** v0.9.4 (2026-09-04) is the latest release; v0.10.0-rc.0
is a pre-release. Its API is `v1alpha1`. It has conditional creation,
`readyWhen`, collections, external references and CEL. Packages.md R15
already refuses kro until L2.4.

## 7. Porting notes

- **Licence and attribution.** All modules are Apache-2.0. A chart that
  translates a module's structure, variable names, defaults or presets is
  arguably a derivative work. Keep the Apache-2.0 licence for those charts,
  say in each chart's README and `Chart.yaml` annotations which module, tag
  and commit it was derived from, and mark it as modified (Apache-2.0
  section 4(b)). There is no NOTICE file to carry. Keep "Copyright 2021 Sven
  Lito" for an eventbridge-derived chart.
- **Values should keep Terraform's variable names**, translated to camelCase
  (`enable_nat_gateway` becomes `enableNatGateway`). Teams can then move
  their `tfvars` mechanically. Outputs should keep the module's output names
  as Bundt output names.
- **Not portable:**
  - lambda's local packaging and `docker-build`;
  - `random_*` passwords: use `manageMasterUserPassword` or a Secret the team
    provides;
  - `tls_private_key` in key-pair;
  - `aws_ec2_tag` on foreign resources;
  - security-group's 53 preset submodules, which become values presets.
- **Inline versus standalone.** Where Terraform has a standalone resource and
  ACK has an inline field (bucket policy, queue policy, SG rules, routes),
  the chart owns the whole field. A second Package cannot add to it. This is
  the main behavioural difference teams will notice. Document it per chart.
- **Every chart needs ACK's identity setup** (IRSA, Pod Identity, or a
  credentials Secret) and the region annotation. That is a Bundt provider
  concern (`spec.providers`), not a chart concern.

## 8. Charts

The AWS charts live in `charts/aws/<module>` and follow `docs/design.md`
("A Package per module", the authoring checklist) with ACK in place of
Config Connector. What differs:

| Topic | AWS charts |
| --- | --- |
| Objects | ACK kinds of the controllers pinned in `UPSTREAM.md` ("ACK controllers"); a kind ACK lacks from ack-extensions (`*.aws.hfl.dev`, CRDs copied in `crds/ack-extensions`) |
| Helpers | `lib/_ack.tpl`, copied into each chart as `templates/_ack.tpl` (`hack/sync-lib.sh`; `hack/test.sh` checks the copies): `ack.metadata`, `ack.tags`, `ack.tagList`, `ack.unsupported`, `ack.unchanged`, `ack.alpha`, and the names helpers `ack.names`, `ack.resourceName`, `ack.cloudName` |
| Package | `aws-<module>`, `providers: [ack]` |
| Region | the module's `region` variable, where it has one, becomes the annotation `services.k8s.aws/region` on every object; unset, ACK takes the namespace's or its controller's region. The account is the namespace's (ACK's cross-account annotations), a Bundt provider concern |
| Tags | the module's `tags` variable is the catalog's `tags`: AWS tags, merged as the module merges them (`ack.tags`), rendered in each kind's own shape (`tags: [{key, value}]`, S3's `tagging.tagSet`, KMS's `tagKey`/`tagValue`) |
| Labels | Kubernetes labels only: ACK does not copy labels to AWS |
| Names | most EC2 resources are named by IDs AWS assigns; their `Name` tags carry the `namePrefix` but are not checked for it (`tests/name-prefix.yaml` exempts the kinds). Names AWS keeps unique (a subnet group, a bucket, an alias) are checked (`nameFields`) |
| Deletion | `deletion_policy: ABANDON` annotates every object `services.k8s.aws/deletion-policy: retain` |
| Alpha | ACK serves every kind as `v1alpha1`, so the API version says nothing about maturity. A GA (v1.x) controller's kinds are on by default; ack-extensions kinds and preview (v0.x) controllers' kinds need `allow_alpha: true` (`ack.alpha`) |
| Refusals | a variable whose Terraform default is not empty (a suffix, a flag that defaults to `true`) is refused when it differs from that default (`ack.unchanged`); the others when set (`ack.unsupported`) |
| References | ACK references by Kubernetes name (`vpcRef: {from: {name: ...}}`) inside a chart. A field that takes another resource's ID and has no reference (`FlowLog.resourceID`, ack-extensions' `VPNGateway.vpc`) cannot be wired in one render: the variable is refused as a gap, and the missing reference is a gap for ack-extensions |
| Coverage | `upstream/aws-kinds.yaml` maps Terraform resource types to ACK and ack-extensions kinds; a tracked module whose every type is listed is classified in `docs/coverage` |
| Tests | the render layer (`task test`): golden files, `kubeconform -strict` against the pinned controllers' CRDs, refusals. A fake-AWS layer (ACK's controllers against moto, as ack-extensions tests its kinds) and live runs in the AWS sandbox account are not built yet: each chart's `tests/mock.values.yaml` is the case they will apply |

| Chart | Module | Notes |
| --- | --- | --- |
| `charts/aws/vpc` | `terraform-aws-vpc` v6.7.3 | partial: IPv6, flow logs, the VPN gateway, redshift and outpost subnets, Block Public Access and the default resources are refused (the chart's README) |
| `charts/aws/security-group` | `terraform-aws-security-group` v6.0.0 | partial: rules inline (no per-rule tags), no random name suffix; VPC associations, `revoke_rules_on_delete` and non-exclusive rules are refused |
| `charts/aws/s3-bucket` | `terraform-aws-s3-bucket` v5.17.0 | partial: one `Bucket` with ownership, public access block, ACL, versioning, encryption, CORS, logging, website, acceleration, request payment, object lock and policy; lifecycle, replication, inventory, analytics, metrics, Intelligent-Tiering, grants and the log-delivery policies not ported yet; directory buckets, metadata and `force_destroy` are gaps |

Gaps the charts found, for ack-extensions (beyond section 5):

| Gap | Needed by | Shape |
| --- | --- | --- |
| A reference from `FlowLog` to the resource it logs (`resourceRef` for a VPC, subnet or network interface) | vpc (`enable_flow_log`) | a reference field on ACK's `FlowLog` (upstream) |
| Reference fields on `VPNGateway` (`vpcRef`) and `VPNGatewayRoutePropagation` (`routeTableRef`) | vpc (`enable_vpn_gateway`, `propagate_*_route_tables_vgw`) | reference fields on ack-extensions' kinds |
| `egressOnlyInternetGatewayRef` on a route; a subnet's IPv6 block from its VPC's (`ipv6CIDRBlock` derived from the VPC's Amazon-provided block) | vpc (IPv6) | reference fields on ACK's `RouteTable` and `Subnet` (upstream) |
| Adopting a VPC's default security group, network ACL and main route table by their VPC | vpc (`default_security_group_*`, `default_network_acl_*`, `default_route_table_*`) | kinds that take a `vpcRef` and manage the VPC's default object |
| Redshift `ClusterSubnetGroup` | vpc (redshift subnets) | generated, or ACK's redshift-controller released |
| VPC Block Public Access options and exclusions | vpc | generated |
| `SecurityGroupVPCAssociation` (`AssociateSecurityGroupVpc`) | security-group (`vpc_associations`) | generated |
| Standalone security group rules with tags (section 5, gap 6) | security-group (each rule's `name` and `tags`) | design question, as in section 5 |
| S3 directory buckets, bucket metadata configurations; emptying a bucket on delete (`force_destroy`) | s3-bucket | generated (directory bucket, metadata); a field and hook on ACK's `Bucket` |
