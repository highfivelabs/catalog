# pubsub

A Pub/Sub topic with its schema, subscriptions and IAM, as Config
Connector objects. A port of Cloud Foundation Fabric's
[`modules/pubsub`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/pubsub)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-pubsub` (`package.yaml`). Checked against Config Connector v1.160.0.

## Example

```yaml
project_id: my-project
name: my-topic
iam:
  roles/pubsub.viewer: ["group:viewers@example.org"]
```

renders the `PubSubTopic` `my-topic` and an `IAMPartialPolicy` on it
(`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.topic` | not a fabric variable: the topic name in full, used as given (no `namePrefix`) and checked (255 characters, a leading letter); unset, the name is `name`; the schema is `<topic>-schema` (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the derived topic name and every subscription name start with `<namePrefix>-`; empty changes nothing |
| `labels` | Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label (fabric's `labels`, on the topic and on subscriptions without their own, are these) |
| `tags` | cloud labels on every object (Google Cloud labels) |
| `project_id`, `name`, `kms_key`, `message_retention_duration`, `regions`, `message_storage_enforce_in_transit` | the `PubSubTopic`: project annotation, `resourceID`, `kmsKeyRef`, `messageRetentionDuration`, `messageStoragePolicy` |
| `schema` | a `PubSubSchema` `<topic>-schema` and the topic's `schemaSettings` (encoding `ENCODING_UNSPECIFIED` unless given) |
| `subscriptions` | one `PubSubSubscription` each, named by its key, on the topic: ack deadline, retention, filter, ordering, exactly-once, expiration, dead letter topic, retry policy (seconds, as fabric), push (attributes, no wrapper, OIDC token), BigQuery (fabric's `project.dataset.table` or `project:dataset.table` as the table's reference) and Cloud Storage delivery; its `labels` are the object's own; `deletion_policy: ABANDON` keeps it when deleted |
| `subscriptions.<s>.iam`, `.iam_bindings`, `.iam_bindings_additive` | on the subscription: one `IAMPartialPolicy`, one `IAMBinding` each, one `IAMPolicyMember` each |
| `iam`, `iam_by_principals`, `iam_bindings`, `iam_bindings_additive` | the same on the topic |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the topic, schema and subscriptions |

Refused when set:

| Variable | Why |
| --- | --- |
| `subscriptions.<s>.bigquery.use_table_schema`, `.service_account_email` | `bigqueryConfig` has no such fields |
| `subscriptions.<s>.deletion_policy: PREVENT` | Config Connector has no equivalent; `ABANDON` keeps the subscription |
| `context` | use Bundt's `${...}` expressions and `valueFrom` |

## Outputs

| Output | From |
| --- | --- |
| `id` | `projects/<project>/topics/<name>`, from the inputs, as fabric's static id |
| `schema_id` | `projects/<project>/schemas/<topic>-schema`, or null |
| `subscription_id` | each subscription's `projects/<project>/subscriptions/<name>`, by key |

These are fabric's declared outputs, selected (`docs/design.md`,
"Outputs"); `topic`, `schema` and `subscriptions` (whole Terraform
objects) are not outputs.

## Differences from the module

- `iam` is an `IAMPartialPolicy`, which keeps the listed members but does
  not remove others; `iam_bindings` are exact, as `IAMBinding`
  (`docs/design.md`, "IAM").
- A subscription's `false` flags (`retain_acked_messages`,
  `enable_message_ordering`, `enable_exactly_once_delivery`) are not
  rendered; false is the API's default.

## From Terraform

A `module "x" { source = ".../modules/pubsub" ... }` block's arguments
become the values unchanged, except refused fields (`examples/pubsub/`).
To adopt an existing topic and subscriptions, keep their names: Config
Connector acquires the resources of those names (`docs/design.md`, "From
Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/pubsub`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/pubsub)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=pubsub`: render cases `basic`, `full` (every field the
chart carries), `names` and `mock`, each validated against Config Connector
v1.160.0's CRD schemas (and `IAMBinding` against config-connector-extensions'),
and the refusals in `tests/*.fail.yaml`.

## Changes

- **0.1.0** (2026-11-12): the port: topic, schema, subscriptions of every
  delivery type, IAM on the topic and each subscription.
