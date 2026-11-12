# dynamodb-table

A DynamoDB table with its indexes, replicas and resource policy, as an AWS
Controllers for Kubernetes (ACK) object. A port of terraform-aws-modules'
[`terraform-aws-dynamodb-table`](https://github.com/terraform-aws-modules/terraform-aws-dynamodb-table/tree/c38423ae6c92825e7cc4376c7f81deb20a676f2b)
at v5.5.2 (`c38423ae`), Apache-2.0; modified (a translation of the
module's variables into a Helm chart). Bundt Package `aws-dynamodb-table`
(`package.yaml`). Checked against ACK's dynamodb-controller v1.14.2
(`UPSTREAM.md`, "ACK controllers").

## Example

The module's README usage:

```yaml
name: my-table
hash_key: id
range_key: title
table_class: STANDARD
deletion_protection_enabled: false
attributes:
  - {name: id, type: "N"}
  - {name: title, type: S}
  - {name: age, type: "N"}
global_secondary_indexes:
  - {name: TitleIndex, hash_key: title, range_key: age, projection_type: INCLUDE, non_key_attributes: [id]}
tags: {Terraform: "true", Environment: staging}
```

renders one `dynamodb.services.k8s.aws/v1alpha1` `Table` (`hfl.dev/id`
`table`) (`tests/golden/basic.yaml`). Quote `"N"` in YAML: unquoted, YAML
1.1 reads it as a boolean.

## What it renders

| Module resource | ACK |
| --- | --- |
| `aws_dynamodb_table.this` | `Table`: `tableName`, `billingMode`, `attributeDefinitions`, `keySchema` (`hash_key`, `range_key`), `provisionedThroughput`, `streamSpecification`, `tableClass`, `deletionProtectionEnabled`, `timeToLive`, `continuousBackups` (point-in-time recovery), `localSecondaryIndexes`, `globalSecondaryIndexes` (with throughput and on-demand limits), `onDemandThroughput`, `tableReplicas` (region, KMS key), `sseSpecification`, `tags` (with `Name`, as the module) |
| `aws_dynamodb_resource_policy.this` | `Table`'s `resourcePolicy`, `__DYNAMODB_TABLE_ARN__` replaced by the table's ARN as the module replaces it |

`region` becomes the annotation `services.k8s.aws/region`.

## Values

Every module variable is a value of the same name, type and default. The
chart adds `names` (`table`), `namePrefix`, `labels` (Kubernetes only),
`deletion_policy` (`ABANDON` renders `services.k8s.aws/deletion-policy:
retain`), and `account_id` and `partition` (needed, with `region`, only
when `resource_policy` says `__DYNAMODB_TABLE_ARN__`); `tags` is the
module's own. `name` (or `names.table`) and `hash_key` are required.
`timeouts` is accepted and has no effect (Terraform's own waits).

Refused (`upstream.yaml`):

- `autoscaling_enabled`, `autoscaling_read`, `autoscaling_write`,
  `autoscaling_indexes`: the Application Auto Scaling targets and policies
  are not ported yet (ACK's applicationautoscaling-controller has them).
- `import_table`, `restore_*`: ACK's `Table` has no import from S3 and no
  restore.
- `warm_throughput` (the table's and an index's), `global_table_witness`:
  no ACK field.
- `replica_regions[*]` `propagate_tags`, `point_in_time_recovery`,
  `deletion_protection_enabled`, `consistency_mode`: ACK's replicas take a
  region, a KMS key, a table class and throughput overrides only.
- `ignore_changes_global_secondary_index`: the controller reconciles the
  indexes to the spec.

## Outputs

`dynamodb_table_arn`, `dynamodb_table_id` (Terraform's id of a table is
its name), `dynamodb_table_stream_arn`, `dynamodb_table_stream_label`. Not
provided: the replica outputs, which ACK's `Table` does not report per
replica.

## Tests

`task test CHART=aws/dynamodb-table`: golden renders validated against
dynamodb-controller v1.14.2's CRDs, and the refusal cases.
`tests/mock.values.yaml` is the case the fake-AWS run applies
(`docs/aws.md`, "Charts").
