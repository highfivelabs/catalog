# sns

An SNS topic with its policies and subscriptions, as AWS Controllers for
Kubernetes (ACK) objects. A port of terraform-aws-modules'
[`terraform-aws-sns`](https://github.com/terraform-aws-modules/terraform-aws-sns/tree/4538b7e208f5bbd6c9972f427f85c9bd735aedad)
at v7.2.0 (`4538b7e2`), Apache-2.0; modified (a translation of the module's
variables into a Helm chart). Bundt Package `aws-sns` (`package.yaml`).
Checked against ACK's sns-controller v1.13.0 (`UPSTREAM.md`, "ACK
controllers").

## Example

The module's README, "Simple Topic", with the region and account the chart
needs for the default topic policy:

```yaml
name: simple
region: eu-west-1
account_id: "111122223333"
```

renders one `sns.services.k8s.aws/v1alpha1` `Topic` (`hfl.dev/id` `topic`)
whose policy is the module's default statement
(`tests/golden/basic.yaml`).

## What it renders

| Module resource | ACK |
| --- | --- |
| `aws_sns_topic.this` | `Topic` `topic`: `name`, the five feedback role pairs and sample rates, `contentBasedDeduplication` and `fifoTopic` (FIFO), `fifoThroughputScope`, `deliveryPolicy`, `displayName`, `kmsMasterKeyID`, `maximumMessageSize`, `signatureVersion` (not on a FIFO topic, as the module), `tracingConfig`, `tags`; `policy` from `topic_policy` when `create_topic_policy` is false |
| `aws_sns_topic_policy.this` | `Topic` `topic`'s `policy` |
| `aws_sns_topic_data_protection_policy.this` | `Topic` `topic`'s `dataProtectionPolicy` (not on a FIFO topic, as the module) |
| `aws_sns_topic_subscription.this` | `Subscription` `subscriptions/<key>`, `topicRef` to the topic |

ACK's `Topic` takes the policies inline, where Terraform has standalone
resources: the chart owns each whole field (`docs/aws.md`, "Porting
notes").

The topic policy is built as the module's `aws_iam_policy_document` builds
it: the source documents, then the default statement (`DefaultStatementID`:
any principal of the topic's account may manage it) and the statements (in
key order, each `sid` defaulting to its key, `resources` defaulting to the
topic's ARN), then the override documents, merged by `Sid`.

`region` becomes the annotation `services.k8s.aws/region` on every object.

A subscription to an email or HTTP(S) endpoint stays pending until the
endpoint confirms it, and AWS refuses to delete a pending subscription
(it expires after three days): deleting the component leaves ACK's
`Subscription` terminal (`ACK.Terminal`, "Cannot unsubscribe a
subscription that is pending confirmation") until it is confirmed or
expires. Terraform has the same limit, which `endpoint_auto_confirms` only
works around for an endpoint that confirms itself.

## Values

Every module variable is a value of the same name, type and default. The
chart adds `names` (`topic`), `namePrefix`, `labels` (Kubernetes only),
`deletion_policy` (`ABANDON` renders `services.k8s.aws/deletion-policy:
retain`), and `account_id` and `partition`; `tags` is the module's own.

- `name` (or `names.topic`) is required: Terraform would generate a name,
  which would change between renders. A FIFO topic's name ends in `.fifo`,
  as the module adds it.
- `account_id` and `region` are required where the chart writes the
  topic's ARN, `arn:<partition>:sns:<region>:<account_id>:<name>`: the
  default topic policy (on by default) and a statement without
  `resources`. Bundt fills `account_id` from the Environment.

Refused (`upstream.yaml`):

- `archive_policy`: ACK's `Topic` has no archive policy field.
- `subscriptions.<key>.replay_policy`: ACK's `Subscription` has no replay
  policy field.
- `subscriptions.<key>.confirmation_timeout_in_minutes` and
  `endpoint_auto_confirms`: Terraform waits for an HTTP(S) endpoint to
  confirm; ACK does not wait (the subscription stays pending,
  `status.pendingConfirmation`).
- `use_name_prefix`: Terraform's random suffix would change between
  renders. Set `name`; `namePrefix` keeps two Instances' topics apart.

## Outputs

`topic_arn` and `topic_id` (Terraform's id of a topic is its ARN),
`topic_name`, `topic_owner`. Not provided: `topic_beginning_archive_time`
(the archive policy is refused) and `subscriptions`, which are whole
Terraform objects.

## Tests

`task test CHART=aws/sns`: golden renders validated against
sns-controller v1.13.0's CRDs, and the refusal cases.
`tests/mock.values.yaml` is the case the fake-AWS run applies, in the
fake's own account (`tests/mock.set.yaml`; `docs/aws.md`, "Charts").
