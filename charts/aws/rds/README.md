# rds

An RDS DB instance with its subnet, parameter and option groups, log
groups, enhanced monitoring role and role associations, as AWS Controllers
for Kubernetes (ACK) objects. A port of terraform-aws-modules'
[`terraform-aws-rds`](https://github.com/terraform-aws-modules/terraform-aws-rds/tree/175da043429cbbe41c512f976105719f6d0e538c)
at v7.2.2 (`175da043`), Apache-2.0; modified (a translation of the module's
variables and its submodules into a Helm chart). Bundt Package `aws-rds`
(`package.yaml`). Checked against ACK's rds-controller v1.14.2,
iam-controller v1.11.3 and cloudwatchlogs-controller v1.10.0, and
ack-extensions' `OptionGroup` and `DBRoleAssociation` (`crds/ack-extensions`).

## Example

The module's README example, without its option group:

```yaml
identifier: demodb
engine: mysql
engine_version: "8.0"
instance_class: db.t3a.large
allocated_storage: 5
db_name: demodb
username: user
port: "3306"
vpc_security_group_ids: [sg-12345678]
family: mysql8.0
create_db_option_group: false
create_db_subnet_group: true
subnet_ids: [subnet-12345678, subnet-87654321]
```

renders a `DBSubnetGroup`, a `DBParameterGroup` and a `DBInstance` that
references both, with the master password managed by RDS in Secrets
Manager (`tests/golden/basic.yaml`). The README example with its option
group is `tests/readme.values.yaml` (`allow_alpha: true`).

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `aws_db_subnet_group` | `create_db_subnet_group` | `rds/DBSubnetGroup` `db-subnet-group`: named `db_subnet_group_name` (or `identifier`), `subnetIDs`, `description`, `tags` |
| `aws_db_parameter_group` | `create_db_parameter_group` (default) | `rds/DBParameterGroup` `db-parameter-group`: named `parameter_group_name` (or `identifier`), `family` (required), `parameterOverrides` (`parameters`), `tags`; `parameter_group_skip_destroy` keeps it (`deletion-policy: retain`) |
| `aws_db_option_group` | `create_db_option_group` (default), engine not postgres, `allow_alpha: true` | ack-extensions `OptionGroup` `db-option-group`: named `option_group_name` (or `identifier`), `engineName`, `majorEngineVersion` (required), `options`, `tags`; the instance takes it by name |
| `aws_db_instance` | `create_db_instance` | `rds/DBInstance` `db-instance`, with `dbSubnetGroupRef`, `dbParameterGroupRef` and `monitoringRoleRef` to the objects above (or the names and ARN given); `manageMasterUserPassword` (default); a read replica by `sourceDBInstanceIdentifier`; the final snapshot and automated backups as ACK's annotations (`rds.services.k8s.aws/skip-final-snapshot`, `final-db-snapshot-identifier`, `delete-automated-backups`) |
| `aws_cloudwatch_log_group` | `create_cloudwatch_log_group`, each of `enabled_cloudwatch_logs_exports` | `cloudwatchlogs/LogGroup` `log-group-<export>`: `/aws/rds/instance/<identifier>/<export>`, `retentionDays`, `kmsKeyID`, `tags`; `cloudwatch_log_group_skip_destroy` keeps it |
| `aws_iam_role` (enhanced monitoring) | `create_monitoring_role` | `iam/Role` `enhanced-monitoring-role`: `monitoring_role_name`, trusting `monitoring.rds.amazonaws.com`, with `AmazonRDSEnhancedMonitoringRole` attached |
| `aws_db_instance_role_association` | each of `db_instance_role_associations`, `allow_alpha: true` | ack-extensions `DBRoleAssociation` `role-association-<feature>`, `dbInstanceRef` to the instance |

## Values

Every module variable is a value of the same name, type and default. The
chart adds `names` (`dbInstance`, `dbSubnetGroup`, `parameterGroup`,
`optionGroup`, `monitoringRole`), `namePrefix`, `labels` (Kubernetes
only), `allow_alpha` and `deletion_policy`; `tags` is the module's own, and
`region` becomes the annotation `services.k8s.aws/region`.

Refused or accepted in part (`upstream.yaml`):

- `password_wo`, `password_wo_version`: a password in values would be in
  the render; use `manage_master_user_password` (the default).
- `manage_master_user_password_rotation` and the four
  `master_user_password_rotat*` variables: no rotation kind
  (secretsmanager-controller PR #69).
- `domain_auth_secret_arn`, `domain_dns_ips`, `domain_fqdn`, `domain_ou`,
  `engine_lifecycle_support`, `dedicated_log_volume`,
  `upgrade_storage_config`, `allow_major_version_upgrade`: no field on ACK's
  `DBInstance`.
- `blue_green_update`, `restore_to_point_in_time`, `s3_import`: no ACK
  support.
- `instance_use_identifier_prefix`, `monitoring_role_use_name_prefix`: a
  random suffix would change between renders.
- `timeouts`, `option_group_timeouts`: Terraform's (by design).
- In part: `apply_immediately` (ACK applies at once), the three groups'
  `*_use_name_prefix` (no random suffix), `parameters` (no
  `apply_method`), `skip_final_snapshot` (the final snapshot's suffix is a
  hash, not random), `create_db_option_group` and
  `db_instance_role_associations` (ack-extensions: `allow_alpha`).
- `engine` is required even for a read replica: ACK's `DBInstance` needs it.

## Outputs

All but six: the refused domain fields (`db_instance_domain_auth_secret_arn`,
`_dns_ips`, `_fqdn`, `_ou`), `db_instance_hosted_zone_id` and
`db_instance_upgrade_rollout_order` (not in ACK's status), and
`db_instance_secretsmanager_secret_rotation_enabled` (refused).

## Tests

`task test CHART=aws/rds`: golden renders (the module's README example
with and without its option group, PostgreSQL with most options, a read
replica, names) validated against the pinned CRDs, and the refusal cases.
`tests/mock.values.yaml` is the case the fake-AWS run applies, in subnets
that `tests/mock.needs.yaml` makes (`docs/aws.md`, "Charts").
