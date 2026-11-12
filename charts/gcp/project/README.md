# project

A Google Cloud project with its services, IAM, organization policies,
lien, essential contacts and Shared VPC attachment, as Config Connector
objects. A partial port of Cloud Foundation Fabric's
[`modules/project`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/project)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-project` (`package.yaml`). Checked against Config Connector
v1.160.0.

Creating a project needs folder or organization roles: this chart runs
only in the platform team's namespace (`docs/design.md`, "Organization,
folders and Config Connector's scope").

## Example

```yaml
name: app-dev
prefix: hfl
parent: folders/1234567890
billing_account: 012345-6789AB-CDEF01
services: [compute.googleapis.com, storage.googleapis.com]
iam:
  roles/viewer: ["group:devs@example.com"]
org_policies:
  compute.disableGuestAttributesAccess: {rules: [{enforce: true}]}
```

## Values ported

| Variable | Renders |
| --- | --- |
| `names.project` | not fabric variables: the cloud name in full, used as given (no `namePrefix`, no `prefix`) and checked against the cloud's limit; a name not set derives from `name` (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience. When set, the derived cloud names this chart gives (the project ID) start with `<namePrefix>-`, in front of the module's own `prefix`; never a name set under `names`; empty changes nothing |
| `labels` | Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label (Config Connector copies it), so it must be a valid one (fabric's `labels`, on the project, are these: here every object carries them) |
| `tags` | a string value: a cloud label on every object (Google Cloud labels). A map value: fabric's tag key, one `TagsTagKey` on the project (unless it has an `id`; its short name takes the `namePrefix`) and one `TagsTagValue` per value (unless it has an `id`), each with its IAM as the module-level IAM variables; `allowed_values_regex` and IAM conditions are refused (no such field; tag keys and values take no conditions) |
| `network_tags` | the same, as tag keys with purpose `GCE_FIREWALL` on the network (`<project>/<vpc>`, or `ALL`) |
| `tags_config` | `ignore_iam` skips the tag keys' and values' IAM; `force_context_ids` is refused (Bundt replaces `$context` ids) |
| `name`, `prefix`, `descriptive_name`, `parent`, `billing_account`, `auto_create_network` | `Project` `<prefix>-<name>` (checked: 6 to 30 characters) under the folder or organization; `auto_create_network` as Config Connector's annotation |
| `project_reuse` | no project: everything else goes on the existing project `<prefix>-<name>` |
| `deletion_policy` | `DELETE` (default) or `ABANDON`; `PREVENT` is refused: use `lien_reason` |
| `lien_reason` | `ResourceManagerLien` restricting `resourcemanager.projects.delete` |
| `services`, `service_config` | one `Service` each; `disable_on_destroy` and `disable_dependent_services` as Config Connector's annotations (both false, as fabric) |
| `iam`, `iam_by_principals` | one `IAMPartialPolicy` on the project |
| `iam_by_principals_conditional` | merged into `iam_bindings` as fabric merges it: one binding per role and condition title, keyed `iam-bpc:<role>-<title>`; fabric's checks |
| `iam_bindings` | one `IAMBinding` each (exact per role; config-connector-extensions, `v1beta1`) |
| `iam_bindings_additive`, `iam_by_principals_additive` | one `IAMPolicyMember` each |
| `org_policies` | one `OrgPolicyPolicy` per policy; a `dry_run:<policy>` key is its `dryRunSpec`; boolean, list, condition and parameters rules as fabric |
| `contacts` | one `EssentialContactsContact` per email |
| `shared_vpc_service_config` | `host_project`: a `ComputeSharedVPCServiceProject`; `network_users` and `iam_bindings_additive`: `IAMPolicyMember`s on the host project |
| `default_service_account` | only `keep` (the default) |
| `shared_vpc_host_config` | `enabled`: a `ComputeSharedVPCHostProject`; `service_projects`: one `ComputeSharedVPCServiceProject` each, attached to this project |
| `custom_roles` | one `IAMCustomRole` each, its ID the key; title `Custom role <key>` and description `Terraform-managed.` unless given, as fabric; fabric's stage check |
| `logging_data_access` | one `IAMAuditConfig` per service (`allServices` for all), a log config per type set, with its exempted members |
| `logging_exclusions` | one `LoggingLogExclusion` each, named by its key (with the `namePrefix`), described `<name> (Terraform-managed).` |
| `logging_sinks` | one `LoggingLogSink` each, named by its key (with the `namePrefix`), described `<name> (Terraform-managed).` unless given, with a unique writer identity unless `unique_writer: false`, its exclusions, and `bigqueryOptions` for a dataset; with `iam` (the default) one `IAMPolicyMember` granting the sink's writer identity (`memberFrom.logSinkRef`) `roles/storage.objectCreator` on the bucket, `roles/pubsub.publisher` on the topic, or `roles/logging.bucketWriter` on the log bucket's project with fabric's condition naming the bucket. Refused: type `project` (no such destination in `LoggingLogSink`), and `iam` on a `bigquery` sink (dataset IAM is the alpha `BigQueryDatasetAccess`: set `iam: false`) |
| `logging_metrics` | one `LoggingLogMetric` each, named by its key (with the `namePrefix`), with its bucket, extractors, bucket options and metric descriptor |
| `log_scopes` | one `LoggingLogScope` each (alpha: needs `allow_alpha: true`), bare project IDs written `projects/<id>` as fabric does |
| `metric_scopes` | one `MonitoringMonitoredProject` each, adding this project to that scoping project's metrics scope |
| `notification_channels` | one `MonitoringNotificationChannel` each, with its type, description, `enabled`, labels and user labels (as the object's labels). Config Connector names a channel by its Kubernetes object, so the channel's display name is `<component>-channel-<key>`: `display_name` is refused, and so are `sensitive_labels` (a secret would be in the rendered manifest) |
| `alerts` | one `MonitoringAlertPolicy` each, with its conditions (absent, matched log, MQL, PromQL, threshold), strategy, documentation and user labels; a notification channel named by a key of `notification_channels` is a reference to it, any other is used as given; `display_name` is required (fabric leaves it to the API). Refused: `alert_strategy.notification_prompts`, `documentation.subject` and `links`, and a PromQL condition's `disable_metric_validation` (no such fields) |
| `quotas` | one `APIQuotaPreference` each, named by its key (with the `namePrefix`); `ignore_safety_checks` is refused (no such field) |
| `allow_alpha` | not a fabric variable: accept `log_scopes`, whose kind is `v1alpha1` |
| `tag_bindings` | one `TagsTagBinding` each on the project: the `Project` object (Config Connector reads its number), or with `project_reuse` the number in `project_reuse.attributes.number`, which it then needs |

## Not ported

Config Connector has kinds for these; the chart refuses them until they
are mapped: `asset_feeds`,
`bigquery_reservations`, `kms_autokeys`, `service_encryption_key_ids`, `workload_identity_pools`,
`pam_entitlements`, `iam_deny_policies` (alpha), `scc_mute_configs`
(alpha), `scc_sha_custom_modules` (alpha), `vpc_sc`,
`factories_config`, `service_agents_config`,
`service_agents_folder_bindings`, `service_agents_project_bindings`.

Refused because Config Connector cannot express them:

| Variable | Why |
| --- | --- |
| `compute_metadata` | `ComputeProjectMetadata` owns all of a project's metadata; fabric sets single keys (gap 10) |
| `default_network_tier`, `default_service_account` other than `keep` | no kind (gap 10) |
| `shared_vpc_service_config.service_agent_iam`, `service_agent_subnet_iam`, `service_iam_grants`, `network_subnet_users` | grants to service agents name the project number, known only after apply (gap 8) |
| `cloud_armor_policy` | `ComputeOrganizationSecurityPolicyAssociation` is alpha |
| `asset_search` | a read, not a resource |
| `universe`, `skip_delete`, `context` | other universes are not supported; `skip_delete` is deprecated in fabric; use Bundt expressions |

## Outputs

Fabric's declared outputs for what the chart ports, selected.

| Output | From |
| --- | --- |
| `project_id`, `id` | the component's inputs, as fabric computes them (`<prefix>-<name>`), so they have a value with `project_reuse` too |
| `name` | `spec.name` |
| `number` | `status.number` |
| `services` | the services the chart enables, sorted |
| `organization_policies_ids` | `projects/<id>/policies/<policy>` per policy |
| `sink_writer_identities` | each sink's `status.writerIdentity`, by its key |
| `tag_keys`, `tag_values`, `network_tag_keys`, `network_tag_values` | the IDs (`tagKeys/<n>`, `tagValues/<n>`) of the keys and values the chart makes, by fabric's keys (`<key>/<value>` for values); fabric outputs whole objects |
| `alert_ids`, `notification_channel_names` | each alert policy's and channel's `status.name` (`projects/<id>/alertPolicies/<n>`), by its key |

With `project_reuse` there is no project object, so `name` and `number`
have no value.

## Alpha

`allow_alpha: true` accepts `log_scopes` (`LoggingLogScope` is
`v1alpha1`), render-tested only (docs/design.md, "Alpha kinds").
`iam_deny_policies`, `scc_mute_configs` and `scc_sha_custom_modules` need
alpha kinds too and are not ported yet, even with `allow_alpha`.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/project`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/project)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=project`: ten render cases (`extras` carries the
0.5.0 variables, `logging` the 0.6.0 ones, `monitoring` the 0.7.0 ones, `tags` the 0.8.0 ones, `reuse-tags` tag bindings on a
reused project), twenty-seven refusals. `tests/mock.values.yaml` (no lien and no Shared VPC: mockgcp has
neither) is applied to the fake cloud.

On 2026-11-12 (`task test-mock MOCK_CHARTS=project`, offload VM), with the
0.5.0 variables added to the case: the project, services, contacts, IAM,
organization policy, `IAMCustomRole`, `IAMAuditConfig` and
`LoggingLogExclusion` all Ready, the outputs evaluated, all deleted. A
`TagsTagBinding` needs a tag value that exists, which the fake cloud's
case cannot name (Google Cloud assigns its ID), so tag bindings are
render-tested only and the case no longer sets one.

On 2026-11-12 again (0.6.0, offload VM), with a log sink to the project's
`_Default` log bucket (its writer identity's conditional
`roles/logging.bucketWriter` grant) and a log-based metric added: all
13 objects Ready, `sink_writer_identities` evaluated, all deleted. And for
0.7.0 (the fake cloud now installs the monitoring and cloud quota CRDs): a
notification channel, an alert policy that refers to it by its key, and
a quota preference added, all 16 objects Ready, outputs evaluated, all
deleted. Metric scopes need a second project and are render-tested
only. And for 0.8.0: a tag key with a value added, all 18 objects
Ready and deleted; tag IAM and network tags are render-tested only. Log
scopes (alpha) are render-tested only. No live run: the project chart's
live case waits for the test provisioner (`docs/design.md`, "The test
provisioner").

## Changes

- **0.8.0** (2026-11-12): fabric's tags: `tags` entries whose value is a
  map (tag keys), `network_tags` and `tags_config` (one `TagsTagKey` per
  key and one `TagsTagValue` per value, with their IAM;
  `allowed_values_regex`, IAM conditions on tags and `force_context_ids`
  refused), `iam_by_principals_conditional` (merged into `iam_bindings`),
  and the outputs `tag_keys`, `tag_values`, `network_tag_keys` and
  `network_tag_values`. A `tags` value that is a map is no longer
  refused. Values that set none of them render as before, with the new
  version label.
- **0.7.0** (2026-11-12): fabric's monitoring and quotas:
  `notification_channels` (one `MonitoringNotificationChannel` each;
  `display_name` and `sensitive_labels` refused), `alerts` (one
  `MonitoringAlertPolicy` each; prompts, documentation subject and links
  and PromQL's `disable_metric_validation` refused), `metric_scopes` (one
  `MonitoringMonitoredProject` each) and `quotas` (one
  `APIQuotaPreference` each; `ignore_safety_checks` refused), and the
  outputs `alert_ids` and `notification_channel_names`. Values that set
  none of them render as before, with the new version label.
- **0.6.0** (2026-11-12): fabric's logging: `logging_sinks` (one
  `LoggingLogSink` each and, with `iam`, the writer identity's grant on its
  destination; type `project`, and `iam` on a `bigquery` sink, refused),
  `logging_metrics` (one `LoggingLogMetric` each), `log_scopes` (alpha,
  behind the new `allow_alpha`), and the output `sink_writer_identities`.
  Values that set none of them render as before, with the new version
  label.
- **0.5.0** (2026-11-12): five more of fabric's variables:
  `custom_roles` (one `IAMCustomRole` each, fabric's default title and
  description), `logging_data_access` (one `IAMAuditConfig` per service),
  `logging_exclusions` (one `LoggingLogExclusion` each, with the
  `namePrefix`), `tag_bindings` (one `TagsTagBinding` each, on the Project
  object, or by `project_reuse.attributes.number`) and
  `shared_vpc_host_config` (a `ComputeSharedVPCHostProject` and one
  `ComputeSharedVPCServiceProject` per service project). Values that set
  none of them render as before, with the new version label.
- **0.4.0** (2026-11-10): `iam_bindings` render one exact `IAMBinding` each (config-connector-extensions, `iam.gcp.hfl.dev/v1beta1`) by default (K5, K12), instead of bindings of the `IAMPartialPolicy`: members added to those roles out of band are now removed, as fabric removes them. Values that set `iam_bindings` render different objects (`docs/design.md`, "Versioning and the OCI layout").
- **0.3.0** (2026-11-10): `names` (`names.project`) sets cloud names in full;
  `labels` and `tags` go on every object; `namePrefix` is an optional
  convenience that never touches a name set in full. fabric's `labels` now label every object, not only the core resource. A `tags` entry whose value is a string is a cloud label.
- **0.2.0** (2026-11-09): `namePrefix`.
- **0.1.0** (2026-11-09): the pilot port.
