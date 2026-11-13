# billing-account

A billing account's IAM, its budgets with their notification channels,
and its log sinks. A port of Cloud Foundation Fabric's
[`modules/billing-account`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/billing-account)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-billing-account` (`package.yaml`). The billing account itself is
not made or changed, as fabric's module takes its ID. IAM, budgets and
notification channels are Config Connector kinds (`v1beta1`); a log sink
is config-connector-extensions' `LoggingBillingAccountSink` (`v1alpha1`),
at `d54a2075`, since Config Connector has no billing account sink.

## Example

```yaml
id: 012345-6789AB-CDEF01
budget_notification_channels:
  billing-default:
    project_id: tf-playground-simple
    type: email
    labels:
      email_address: gcp-billing-admins@example.com
budgets:
  folder-net-month-current-100:
    display_name: 100 dollars in current spend
    amount:
      units: 100
    filter:
      period:
        calendar: MONTH
    threshold_rules:
      - percent: 0.5
    update_rules:
      default:
        monitoring_notification_channels: ["$notification_channels:billing-default"]
```

renders an email `MonitoringNotificationChannel` and a
`BillingBudgetsBudget` that alerts it at half the monthly amount
(`tests/golden/budgets.yaml`; fabric's README example).

## Values

The module's variables, with the same names, types and defaults. The
chart carries 9 of the 11; two are refused, and four are accepted in part.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: this chart gives no fixed names, so it takes none |
| `namePrefix` | not a fabric variable: `<namePrefix>-` in front of each log sink's name |
| `labels`, `tags` | not fabric variables: labels on every object; unprefixed ones are cloud labels (a channel's user labels) |
| `allow_alpha` | not a fabric variable: required for `logging_sinks` |
| `deletion_policy` | not a fabric variable: `DELETE` (default) or `ABANDON`; `PREVENT` is refused |
| `id` | the billing account every object is on (`billingAccountRef`, `resourceRef`) |
| `iam`, `iam_by_principals`, `iam_bindings` | one `IAMPartialPolicy` on the `BillingAccount`: `iam` and `iam_by_principals` merged by role, then `iam_bindings` with their conditions |
| `iam_bindings_additive` | one `IAMPolicyMember` per entry, with its condition |
| `budget_notification_channels` | one `MonitoringNotificationChannel` per key in its `project_id`: `type`, `description`, `enabled` (default true), `force_delete`, `labels` (the channel's configuration, such as `email_address`), `user_labels` (its object's labels, which Config Connector copies to the channel). **`display_name` is refused** (a gap): Config Connector takes a channel's display name from its object's name, `<release>-channel-<key>`, where fabric's default is `Budget email notification <key>.`; **`sensitive_labels` is refused** too: it holds secret values (the builder's open SECV question) |
| `budgets` | one `BillingBudgetsBudget` per key: `display_name`, `amount` (`lastPeriodAmount` with `use_last_period`, else `specifiedAmount`), `budgetFilter` (fabric's credit types treatment, `creditTypes`, `calendarPeriod` or `customPeriod`, `labels` from `filter.label`, `projects`, `services`, `subaccounts`), `thresholdRules` (`spendBasis` from `forecasted_spend`) and `allUpdatesRule` (schema version `1.0`, the Pub/Sub topic, `disableDefaultIamRecipients`, and channels: `$notification_channels:<key>` is that channel's object, anything else a channel ID). **`ownership_scope` and `filter.resource_ancestors` are refused** (a gap): the kind has neither. Fabric's validations hold: an amount needs `units` or `use_last_period`, a rule a topic or channels; a second update rule is refused, as the API holds one |
| `logging_sinks` | one `LoggingBillingAccountSink` per key, **with `allow_alpha: true`**: named by its key (with the `namePrefix`), described `<key> (Terraform-managed).` unless given, `filter`, `disabled`, `exclusions`, `bigqueryOptions` for `bigquery`, and its destination by type (`storage`, `bigquery`, `pubsub`, `logging`; `project` is a log bucket reference to `projects/<id>`, as fabric rewrites it). **The writer identity's grant on the destination is not made** (below) |
| `factories_config` | accepted and ignored (by design): a chart cannot read the caller's files; each budget file's contents go under `budgets.<file name>` |
| `projects` | **refused when set** (a gap): Config Connector has no kind for a project's billing link alone; the project chart's `billing_account` sets a project's billing account on its `Project` |
| `context` | **refused when set** (by design): Bundt expressions (`${...}`) and `valueFrom` replace fabric's `$context` lookups |

## Outputs

| Output | From |
| --- | --- |
| `billing_budget_ids` | each budget's key to `billingAccounts/<id>/budgets/<budget>`, the name the API gives it, which Config Connector writes to `spec.resourceID` |
| `monitoring_notification_channel_ids` | each channel's key to its `status.name`, `projects/<p>/notificationChannels/<n>` |

## Differences from the module

- **No grant to a log sink's writer identity.** Fabric grants each sink's
  writer identity a role on its destination (`objectCreator` on a bucket,
  `dataEditor` on a dataset, `publisher` on a topic, `bucketWriter` or
  `logWriter` on a project). No Config Connector or config-connector-extensions
  IAM kind can take its member from a `LoggingBillingAccountSink`, so the
  chart makes none: grant the sink's `status.writerIdentity` on the
  destination (in the destination's own component, for example) until it
  can.
- **Channel display names** follow the object's name (above).
- **No `projects`** (above).

## From Terraform

A `module "x" { source = ".../modules/billing-account" ... }` block's
arguments become the values unchanged, with `allow_alpha: true` when
`logging_sinks` is set. Budgets and channels have IDs the API gives them,
so adopting the ones Terraform made needs their IDs in `spec.resourceID`
(`docs/design.md`, "From Terraform"); sinks keep their names and adopt
the sinks Terraform made.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/billing-account`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/billing-account)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=billing-account`: render cases `basic`, `iam`, `budgets`
and `sinks` (fabric's README examples), `full`, `names` and `mock`,
validated against Config Connector's and config-connector-extensions'
CRDs, and the refusals in `tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`): a role and an
additive member on the billing account, an email channel, a budget that
alerts it and a log sink to a bucket. On 2026-11-13 (offload VM
`off-catalog-1113134113-21852` and a rerun, config-connector-extensions
`d54a2075`) all five objects became Ready, the outputs evaluated and all
five were deleted. The first run found two things the chart now does:
config-connector-extensions resolves a sink's bucket only as
`projects/<p>/buckets/<b>` (the chart sends `projects/_/buckets/<name>`,
and the extension passes the API the name alone), and Config Connector
writes a budget's full name, not its bare ID, to `spec.resourceID`.

Not applied live: live runs are pending KEYLIVE.

## Changes

- **0.1.0** (2026-11-13): the port: IAM on the billing account, budgets,
  their notification channels and log sinks.
