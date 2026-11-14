# backup-dr

A Backup and DR backup vault, backup plans that store their backups in
it, and optionally a management server, as Config Connector objects. A
port of Cloud Foundation Fabric's
[`modules/backup-dr`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/backup-dr)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-backup-dr` (`package.yaml`). Checked against Config Connector
v1.160.0 (`BackupDRBackupVault`, `BackupDRBackupPlan`) and
config-connector-extensions' `BackupDRManagementServer`
(`backupdr.gcp.hfl.dev/v1beta1`, at `11baa460`).

## Example

```yaml
project_id: your-gcp-project-id
location: us-central1
name: backup-vault
backup_plans:
  my-backup-plan:
    resource_type: compute.googleapis.com/Instance
    description: Backup Plan for GCE Instances.
    backup_rules:
      - rule_id: daily-backup-rule
        backup_retention_days: 30
        standard_schedule:
          recurrence_type: HOURLY
          hourly_frequency: 6
          time_zone: America/Los_Angeles
          backup_window: {start_hour_of_day: 1, end_hour_of_day: 5}
```

renders the `BackupDRBackupVault` `backup-vault` and the
`BackupDRBackupPlan` `my-backup-plan` referring to it
(`tests/golden/basic.yaml` has fabric's second, monthly rule too).

## Values

The module's variables, with the same names, types and defaults. The
chart carries all seven; `vault_config` in part.

| Variable | Renders |
| --- | --- |
| `names` | not a fabric variable: `names.vault` and `names.managementServer` set those cloud names in full |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every name not set under `names` (the vault's, each plan's, the management server's) starts with `<namePrefix>-`; empty changes nothing |
| `labels` | not a fabric variable: Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label on the vault and the management server |
| `tags` | not a fabric variable: cloud labels on every resource that takes them |
| `project_id` | every object's project annotation and `projectRef` |
| `location` | every object's `location` |
| `name` | a `BackupDRBackupVault` of that name; null makes none. With `vault_reuse` it stops the render, as fabric's validation does |
| `vault_config` | the vault: `description`, `backup_minimum_enforced_retention_duration` (fabric's default `100000s`), `annotations`, `access_restriction`, `ignore_inactive_datasources` (with it, Config Connector deletes the vault with `force`), and `labels` as the vault's own labels, copied to the cloud. Refused: `backup_retention_inheritance` (`BackupDRBackupVault` has no such field), and `force_update`, `ignore_backup_plan_references` and `allow_missing` set to true (request flags Config Connector does not send); false, their default, is accepted |
| `vault_reuse` | the plans' vault: `vault_id` as given when it is a path, else `projects/<project>/locations/<location>/backupVaults/<vault_id>` |
| `backup_plans` | one `BackupDRBackupPlan` per key, named by the key: `resource_type`, `description`, and each rule's ID, retention and standard schedule (recurrence, hourly frequency, days of the week or month, months, week day of the month, time zone, window). A plan with no vault (no `name`, no `vault_reuse`) stops the render, where Terraform's would fail at apply |
| `management_server_config` | one `BackupDRManagementServer` (config-connector-extensions, `v1beta1`): `name`, `type` (default `BACKUP_RESTORE`), and the network with its `peering_mode` (default `PRIVATE_SERVICE_ACCESS`) |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the vault, plans and management server |

Name lengths: a name set under `names`, and with a `namePrefix` a derived
name, over 63 characters stops the render. 63 is an assumption: the API
documents no limit for vault, plan or management server IDs, and 63 is the
length the catalog uses for names that have none documented.

## Outputs

| Output | From |
| --- | --- |
| `backup_vault_id` | `projects/<project>/locations/<location>/backupVaults/<name>` when the chart makes the vault, else null (fabric's), from the inputs |
| `backup_plans` | `{<key>: projects/<project>/locations/<location>/backupPlans/<name>}`, from the inputs. fabric's output is a map of whole plan objects; a Package outputs the field a consumer takes (`docs/design.md`, "Outputs") |
| `management_server` | the server's ID, `projects/<project>/locations/<location>/managementServers/<name>`, or null; fabric's is the whole object |
| `management_server_uri` | `{api, web_ui}` from the server's `status.observedState.managementUri`, or null: fabric's `management_uri` |

## From Terraform

A `module "x" { source = ".../modules/backup-dr" ... }` block's arguments
become the values unchanged (`examples/backup-dr/`), except the refused
`vault_config` fields above. Names are fabric's, so the vault, plans and
management server adopt what Terraform made (`docs/design.md`, "From
Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/backup-dr`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/backup-dr)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=backup-dr`: render cases `basic` (fabric's README example
"Create vault and plan"), `defaults` ("Create backup vault (basic
usage)"), `reuse` ("Create only backup plan with existing vault"), `full`
(every field the chart carries, with a management server), `names` and
`mock`, each validated against Config Connector v1.160.0's CRD schemas and
config-connector-extensions' `BackupDRManagementServer` CRD, and the
refusals in `tests/*.fail.yaml`.

Fake cloud (`task test-mock`, `tests/mock.values.yaml`): a vault, a plan
in it and a management server. On 2026-11-12 (offload VM
`off-catalog-1113002414-8197`, config-connector-extensions `11baa460`) all
three became Ready, the outputs evaluated (`management_server_uri` null:
mockgcp's server reports no management URI) and all three were deleted.

Live (`hack/live-apply.sh` `LIVE_CHARTS=backup-dr`, `tests/live.yaml`, with
a network of the run that has private services access; as
cce-live-tests, config-connector-extensions `c2f0c7d2`). Failed, on the
API's side: on 2026-11-14 (run `cat-11140135-fd30`, offload VM
`off-catalog-1114013054-5293`) Backup and DR refused the management server
(config-connector-extensions' `BackupDRManagementServer`): "Invalid
resource state ... Management Console is on path for deprecation and
creation of new Management server is restricted"
(`MANAGEMENT_SERVER_CREATION_RESTRICTED`), so the kind cannot be proven
live in a new project. The vault and plan (Config Connector's) were made
and Ready, then Config Connector tried to update both and failed: the
vault's update "'access_restriction' is required in this request", the
plan's "updating BackupPlan is not supported, fields: [backup_rules]";
neither was deleted within the run's limit, and the sweep (the vault by
hand, with `force`) deleted both. An earlier run (`cat-11132355-83c4`) was
stopped by offload's 45-minute silence limit while it waited for the
server; everything it made was deleted by hand.

## Changes

- **0.1.0** (2026-11-12): the port: the vault, backup plans and the
  management server; four `vault_config` fields refused.
