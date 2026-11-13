# sqs

An SQS queue with its access and redrive policies, as an AWS Controllers
for Kubernetes (ACK) object. A port of terraform-aws-modules'
[`terraform-aws-sqs`](https://github.com/terraform-aws-modules/terraform-aws-sqs/tree/dd73a96c0155bc324dda5256f3e7a9ea2c710195)
at v5.2.2 (`dd73a96c`), Apache-2.0; modified (a translation of the module's
variables into a Helm chart). Bundt Package `aws-sqs` (`package.yaml`).
Checked against ACK's sqs-controller v1.9.0 (`UPSTREAM.md`, "ACK
controllers").

## Example

The module's README usage, with the dead-letter queue as its own component
(`create_dlq` is refused, below):

```yaml
name: user
region: eu-west-1
redrive_policy:
  deadLetterTargetArn: arn:aws:sqs:eu-west-1:111122223333:user-dlq  # the dead-letter component's queue_arn
  maxReceiveCount: 10
tags: {Environment: dev}
```

renders one `sqs.services.k8s.aws/v1alpha1` `Queue` (`hfl.dev/id` `queue`)
(`tests/golden/basic.yaml`); `tests/dlq.values.yaml` is the dead-letter
component, its redrive allow policy naming the queue.

## What it renders

| Module resource | ACK |
| --- | --- |
| `aws_sqs_queue.this` | `Queue` `queue`: every attribute (`queueName`, deduplication, delay, FIFO, KMS or SQS-managed encryption, message size, retention, long polling, visibility timeout), `tags` |
| `aws_sqs_queue_policy.this` | the `Queue`'s `policy` |
| `aws_sqs_queue_redrive_policy.this` | the `Queue`'s `redrivePolicy` |
| `aws_sqs_queue_redrive_allow_policy.this` | the `Queue`'s `redriveAllowPolicy` |

ACK's `Queue` takes the policies inline, where Terraform has standalone
resources: the chart owns each whole field, and a second Package cannot
add to a queue's policy (`docs/aws.md`, "Porting notes").

The queue policy is built as the module's `aws_iam_policy_document` builds
it: the source documents, then the statements (in key order, each `sid`
defaulting to its key, `condition` and `conditions` both taken,
`resources` defaulting to the queue's own ARN), then the override
documents, merged by `Sid`. A policy with no statement is not set.

`region` becomes the annotation `services.k8s.aws/region`; unset, ACK
takes the namespace's or its controller's region.

## Values

Every module variable is a value of the same name, type and default. The
chart adds `names` (`queue`), `namePrefix`, `labels` (Kubernetes only),
`deletion_policy` (`ABANDON` renders `services.k8s.aws/deletion-policy:
retain`), and `account_id` and `partition`; `tags` is the module's own.

- `name` (or `names.queue`) is required: Terraform would generate a name,
  which would change between renders. A FIFO queue's name ends in `.fifo`,
  as the module adds it.
- `account_id` and `region` are required for a queue policy statement
  without `resources`, whose default is the queue's ARN,
  `arn:<partition>:sqs:<region>:<account_id>:<name>`, which the module
  reads from the provider. Bundt fills `account_id` from the Environment.

Refused (`upstream.yaml`):

- `create_dlq` and every variable of the dead-letter queue (`dlq_*`,
  `create_dlq_queue_policy`, `create_dlq_redrive_allow_policy`, the
  `*_dlq_queue_policy_documents`): SQS refuses a redrive policy naming a
  queue that does not exist yet ("Dead letter target does not exist"),
  ACK's `Queue` has no reference to its dead-letter queue to wait for it,
  and ACK treats the refusal as terminal, so a queue and its dead-letter
  queue applied together never sync (AWS Emulator showed it; moto does
  not check). Make the dead-letter queue its own component and pass its
  `queue_arn` into this queue's `redrive_policy.deadLetterTargetArn`:
  Bundt applies a dependent once its producer is ready.
- `use_name_prefix`: Terraform's random suffix would change between
  renders. Set `name`; `namePrefix` keeps two Instances' queues apart.

## Outputs

`queue_id` and `queue_url` (Terraform's id of a queue is its URL),
`queue_arn`, `queue_arn_static` (from the queue's name and the region and
account ACK reports), `queue_name`. Not provided: the dead-letter queue's
five (`create_dlq` is refused).

## Tests

`task test CHART=aws/sqs`: golden renders validated against
sqs-controller v1.9.0's CRDs, and the refusal cases.
`tests/mock.values.yaml` is the case the fake-AWS run applies, with its
dead-letter queue from `tests/mock.needs.yaml` and the fake's own account
(`tests/mock.set.yaml`; `docs/aws.md`, "Charts").
