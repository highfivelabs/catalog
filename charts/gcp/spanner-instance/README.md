# spanner-instance

A Cloud Spanner instance, with an optional user-managed instance
configuration, its databases and IAM on the instance and each database, as
Config Connector objects. A port of Cloud Foundation Fabric's
[`modules/spanner-instance`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/spanner-instance)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-spanner-instance` (`package.yaml`). Checked against Config Connector
v1.160.0 (`SpannerInstance`, `SpannerDatabase`, `IAMPartialPolicy`,
`IAMPolicyMember`) and config-connector-extensions' `SpannerInstanceConfig`
(`spanner.gcp.hfl.dev/v1beta1`) at `0ee17dd`; Config Connector's own
`SpannerInstanceConfig` is `v1alpha1`.

## Example

```yaml
project_id: my-project
instance:
  name: my-instance
  display_name: Regional instance in us-central1
  config:
    name: regional-us-central1
  num_nodes: 1
databases:
  my-database: {}
```

renders the `SpannerInstance` `my-instance` and the `SpannerDatabase`
`my-database` in it (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.instance` | not a fabric variable: the instance ID in full, used as given (no `namePrefix`) and checked (2 to 64 characters, a leading letter) (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the instance ID is `<namePrefix>-<instance.name>`; empty changes nothing |
| `labels` | not a fabric variable: Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label on the instance and the instance configuration |
| `tags` | not a fabric variable: Google Cloud labels on the instance and the instance configuration |
| `project_id` | every object's project annotation, and the configuration's `projectRef` |
| `instance.name`, `instance.display_name` | the instance ID (`resourceID`) and `displayName` (`instance.name` when unset, as fabric) |
| `instance.config.name` | the instance's `config`; required when `instance_create` is true, as fabric's resource needs it |
| `instance.config.auto_create` | a `SpannerInstanceConfig` (config-connector-extensions) named `config.name`, with `displayName` (`config.name` when unset), `baseConfigRef`, `replicas` and `labels` |
| `instance.num_nodes`, `processing_units`, `edition`, `default_backup_schedule_type` | the same fields of the `SpannerInstance` |
| `instance.autoscaling` | `autoscalingConfig`: `limits.min_processing_units` and `max_processing_units`, `targets`. `limits.min_nodes` and `max_nodes` are accepted and not rendered, as fabric does not pass them |
| `instance.labels` | Google Cloud labels on the instance (with the chart's `tags` and unprefixed `labels`) |
| `instance.force_destroy` | refused when true (below) |
| `instance_create` | false: no instance is rendered; the databases name the existing instance (`instanceRef.external`, its ID) and its IAM refers to `projects/<project>/instances/<ID>` |
| `databases` | a `SpannerDatabase` each, its name the key: `ddl`, `enableDropProtection`, `versionRetentionPeriod` and `encryptionConfig.kmsKeyRef` from `kms_key_name` |
| `databases.*.database_dialect`, `deletion_protection` | accepted (with fabric's validation) and not rendered: fabric's `google_spanner_database` sets neither from them (it hard-codes `deletion_protection = false`, a Terraform-only flag) |
| `databases.*.default_time_zone` | refused when set (below) |
| `iam`, `iam_bindings` | one `IAMPartialPolicy` on the instance (`docs/design.md`, "IAM") |
| `iam_bindings_additive` | an `IAMPolicyMember` on the instance each |
| `databases.*.iam`, `iam_bindings` | one `IAMPartialPolicy` on the database, with the bindings' conditions; keyed `<database>.<key>` as fabric keys them |
| `databases.*.iam_bindings_additive` | an `IAMPolicyMember` on the database each, with its condition |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the configuration, the instance and its databases |

Refused, in part (`upstream.yaml`):

- `instance.force_destroy: true`. `SpannerInstance` is a direct controller
  with no force-destroy; Terraform's flag deletes the instance's backups
  before the instance. Delete them first.
- `databases.*.default_time_zone`. `SpannerDatabase` has no
  `defaultTimeZone` field.

## Outputs

| Output | Value |
| --- | --- |
| `spanner_instance_id` | `<project>/<instance ID>`, the provider's ID, from the inputs |
| `spanner_database_ids` | `{NAME: <instance ID>/<NAME>}`, the provider's IDs, from the inputs |
| `spanner_instance_config_id` | `projects/<project>/instanceConfigs/<config.name>` when `auto_create` is set, else null |

fabric's `spanner_databases`, `spanner_instance` and
`spanner_instance_config` are whole Terraform objects, which a Package does
not output (`docs/design.md`, "Outputs").

## Differences from the module

- **A short `base_config` is made a full name.** The API takes
  `projects/<project>/instanceConfigs/<name>`; a `base_config` without a
  `/` (`nam11`) is written that way with `project_id`.
- **The instance configuration takes no `namePrefix`.** Spanner requires a
  user-managed configuration's ID to start with `custom-`, so it is
  `instance.config.name` as given (`tests/name-prefix.yaml`).
- **IAM is partial.** fabric's instance and database IAM bindings are
  authoritative per role; here they are an `IAMPartialPolicy`, so members
  added by hand stay.

## From Terraform

A `module "x" { source = ".../modules/spanner-instance" ... }` block's
arguments become the values unchanged. To adopt an existing instance, keep
its ID and set `deletion_policy: ABANDON` for the first apply
(`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/spanner-instance`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/spanner-instance)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=spanner-instance`: render cases `basic`, `autoscaling`,
`custom-config`, `existing` and `iam` (fabric's five README examples, IAM on
the instance added), `full`, `names` and `mock`, each validated against
Config Connector v1.160.0's CRD schemas and config-connector-extensions'
`SpannerInstanceConfig` CRD, and the refusals in `tests/*.fail.yaml`.

Fake cloud: `task test-mock MOCK_CHARTS=spanner-instance` (2026-11-13,
offload VM `off-catalog-1113025758-23434`, config-connector-extensions at
`0ee17dd`): `tests/mock.values.yaml`'s instance configuration, instance,
database and the IAM policies on the instance and the database all Ready
and deleted, and the three outputs evaluated.

Live (`hack/live-apply.sh` `LIVE_CHARTS=spanner-instance`, `tests/live.yaml`; as
cce-live-tests, config-connector-extensions `c2f0c7d2`): a user-managed instance configuration with
regional-us-central1's replicas, an instance on it at 100 processing
units, a database with DDL, and IAM on both. The first run
(`cat-11132355-c86b`) listed one replica, and the API refused the
configuration ("All `replicas` of base config regional-us-central1 must be
included": the base has three read-write replicas), so the case lists all
three. The rerun (2026-11-14, `cat-11140135-fd30`, offload VM
`off-catalog-1114013054-5293`) passed: the configuration, instance,
database and both `IAMPartialPolicy`s Ready, deleted and gone.

## Changes

- **0.1.0** (2026-11-12): the port.
