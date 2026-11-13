# step-functions

A Step Functions state machine with its IAM role and policies and its
CloudWatch log group, as AWS Controllers for Kubernetes (ACK) objects. A
port of terraform-aws-modules'
[`terraform-aws-step-functions`](https://github.com/terraform-aws-modules/terraform-aws-step-functions/tree/16c7a1ffaa72643d714a7b3924216edce9413482)
at v5.1.1 (`16c7a1ff`), Apache-2.0; modified (a translation of the
module's variables into a Helm chart, and its map of service integration
policies, `locals.tf`, carried as data in `templates/_sfn.tpl`). Bundt
Package `aws-step-functions` (`package.yaml`). Checked against ACK's
sfn-controller v1.9.1, iam-controller v1.11.3 and cloudwatchlogs-controller
v1.10.0 (`UPSTREAM.md`, "ACK controllers").

## Example

The module's README usage (`tests/basic.values.yaml`):

```yaml
name: my-stepfunction
region: eu-west-1
definition: '{"StartAt": "Hello", "States": {"Hello": {"Type": "Pass", "End": true}}}'
service_integrations:
  lambda:
    lambda: ["arn:aws:lambda:eu-west-1:111122223333:function:test1"]
tags: {Module: my}
```

renders a `StateMachine` (`hfl.dev/id` `state-machine`), its `Role`
(`role`, trusting `states.eu-west-1.amazonaws.com`) and the Lambda
integration's `Policy` (`policy-service-lambda`), attached by reference.

## What it renders

| Module resource | When | Object (`hfl.dev/id`) |
| --- | --- | --- |
| `aws_sfn_state_machine` | `create` | `sfn/StateMachine` `state-machine`: `name`, `definition`, `roleRef` (or `roleARN` with `use_existing_role`), `type_` (upper-cased), `publish`, `loggingConfiguration` (a `level` other than `OFF`), `tracingConfiguration` (`service_integrations.xray.xray: true`), `tags` (`Name`, `tags`) |
| `aws_iam_role` | `create_role`, not `use_existing_role` | `iam/Role` `role`: named `role_name` (or `name`), trusting `states.<aws_region_assume_role or region>.amazonaws.com` and `trusted_entities`, `description`, `path`, `permissionsBoundary`, `tags` (`tags`, `role_tags`) |
| `aws_iam_policy`, `aws_iam_policy_attachment` (service integrations, `policy_json`, `policy_jsons`, `policy_statements`, CloudWatch Logs) | as the module makes them | `iam/Policy` `policy-service-<key>`, `policy-json`, `policy-jsons-<i>`, `policy-inline`, `policy-logs`, named as the module names them, `path` (`policy_path`), in the role's `policyRefs` |
| `aws_iam_role_policy_attachment` (`policy`, `policies`) | `attach_policy`, `attach_policies` | the role's `policies` (ARNs). ACK's `Role` takes ARNs or references, not both: with ARNs given beside policies this chart makes, every policy is attached by ARN, built from `account_id` |
| `aws_cloudwatch_log_group` | logging, not `use_existing_cloudwatch_log_group` | `cloudwatchlogs/LogGroup` `log-group`: `name` (`cloudwatch_log_group_name`, else `/aws/vendedlogs/states/<name>`), `retentionDays`, `kmsKeyID`, `tags` (`tags`, `cloudwatch_log_group_tags`) |

The service integration policies are the module's (41 integrations): each
statement's Sid, effect, actions, conditions and default resources as
`locals.tf` writes them, a statement's resources the list given or, with
`true`, its default ones. Defaults that name the region or the account
take `aws_region_assume_role` (or `region`) and `account_id`.

`StateMachine` takes its log group by ARN only, so without
`logging_configuration.log_destination` the chart builds the ARN,
`arn:<partition>:logs:<region>:<account_id>:log-group:<name>:*`, and needs
`region` and `account_id`.

## Values

Every module variable is a value of the same name, type and default. The
chart adds `names` (`stateMachine`, `role`, `logGroup`), `namePrefix`,
`labels` (Kubernetes only), `account_id` and `partition` (which the module
reads from the provider) and `deletion_policy`; `tags` is the module's own,
and `region` becomes the annotation `services.k8s.aws/region` on the state
machine and the log group. The trust policy needs a region:
`aws_region_assume_role` or `region` (the module reads the provider's).

Refused or accepted in part (`upstream.yaml`):

- `encryption_configuration`: ACK's `StateMachine` has no field for it.
- `role_force_detach_policies`, in part: `true` only; ACK always detaches
  a role's managed policies before deleting it.
- `sfn_state_machine_timeouts`: Terraform's (by design).

## Outputs

`state_machine_id` and `state_machine_arn` (the ARN, as the module gives
both), `state_machine_name`, `state_machine_creation_date`,
`state_machine_version_arn`, `role_arn`, `role_name`,
`cloudwatch_log_group_arn` (without the `:*` the log group's ARN carries,
as the module trims it) and `cloudwatch_log_group_name`; `""` for what the
component did not make, as the module gives. Not provided:
`state_machine_status` (ACK's status does not report it).

## Tests

`task test CHART=aws/step-functions` renders every `tests/*.values.yaml`
against its golden file and the pinned controllers' CRDs, and checks each
`tests/*.fail.yaml` is refused with its message. `tests/mock.values.yaml`
is the fake-AWS case (`task test-mock-aws`, `hack/mock-apply-aws.sh`).
