# gcs

A Cloud Storage bucket with its IAM, notification and tag bindings, as
Config Connector objects. A port of Cloud Foundation Fabric's
[`modules/gcs`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/gcs)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-gcs` (`package.yaml`). Checked against Config Connector v1.160.0.

## Example

```yaml
project_id: myproject
prefix: test
name: my-bucket
location: EU
versioning: true
labels: {cost-center: devops}
```

renders the `StorageBucket` `test-my-bucket` (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `name`, `prefix`, `project_id`, `location`, `storage_class`, `labels`, `uniform_bucket_level_access`, `default_event_based_hold`, `requester_pays`, `public_access_prevention`, `versioning`, `autoclass`, `cors`, `custom_placement_config`, `encryption_key`, `logging_config`, `lifecycle_rules`, `retention_policy`, `soft_delete_retention`, `website`, `ip_filter` | the `StorageBucket`'s fields of the same meaning; the name is `<prefix>-<name>` lower-cased; `cors.max_age_seconds` is at least 3600, as fabric sets it |
| `force_destroy` | the `cnrm.cloud.google.com/force-destroy` annotation: the bucket's objects are deleted with it |
| `bucket_create: false` | no bucket: IAM, the notification and tag bindings go on the existing bucket `<prefix>-<name>` |
| `iam`, `iam_by_principals`, `iam_bindings` | one `IAMPartialPolicy` on the bucket |
| `iam_bindings_additive` | one `IAMPolicyMember` each |
| `notification_config` | a `StorageNotification`; with `create_topic` (the default) also the `PubSubTopic` and an `IAMPartialPolicy` granting `roles/pubsub.publisher` to `sa_email` |
| `tag_bindings` | one `TagsLocationTagBinding` each |
| `deletion_policy` | not a fabric gcs variable; `ABANDON` keeps the bucket and topic |
| `allow_alpha`, `managed_folders` | alpha: with `allow_alpha: true`, one `StorageManagedFolder` per path (needs `project_id`; the kind takes no project annotation and takes the bucket by the name it has in Google Cloud); otherwise refused |

Refused when set:

| Variable | Why |
| --- | --- |
| `enable_object_retention`, `enable_hierarchical_namespace`, `rpo` | `StorageBucket` has no such field (field gaps; `rpo` is Config Connector PR #13713) |
| `objects_to_upload` | Config Connector has no bucket object kind (gap 5) |
| `managed_folders` with a nested path (`a/b`) | the kind's identity code reads a one-level name only, so such a folder could not be updated or deleted (field gap) |
| `managed_folders[].iam*`, `managed_folders[].force_destroy: true` | IAMPolicyMember cannot reference a managed folder (gap 2), and the kind has no `force_destroy` |
| `kms_autokeys` | a key handle's key is known only after apply, and the bucket cannot reference a handle (gap 8) |
| `context` | use Bundt's `${...}` expressions and `valueFrom` |

## Outputs

| Output | From |
| --- | --- |
| `name`, `id` | the component's inputs, as fabric computes them (`<prefix>-<name>`, lower-cased) |
| `url` | `status.url`; `gs://<name>` with `bucket_create: false` |
| `notification` | the notification's `status.selfLink`, or null |
| `topic` | `projects/<p>/topics/<topic>` when the chart made the topic, or null |

These are fabric's declared outputs, selected (docs/design.md,
"Outputs"); fabric's `bucket` and `objects` (whole Terraform objects) are
not outputs.

## Differences from the module

- Authoritative IAM is `IAMPartialPolicy` (`docs/design.md`, "IAM").
- The notification can be created before the publisher grant is in
  place; Config Connector retries until it is.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/gcs`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gcs)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=gcs`: five render cases, seven refusals.
`tests/mock.values.yaml` is applied to the fake cloud.
