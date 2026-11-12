# cloudsql-instance

A Cloud SQL instance with its read replicas, databases, IAM users and client
certificates, as Config Connector objects. A port of Cloud Foundation
Fabric's
[`modules/cloudsql-instance`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/cloudsql-instance)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-cloudsql-instance` (`package.yaml`). Checked against Config Connector
v1.160.0.

## Example

The module README's simple example, as values
(`tests/basic.values.yaml`):

```yaml
project_id: myproject
network_config:
  connectivity:
    psa_config:
      private_network: projects/myproject/global/networks/my-network
name: db
region: europe-west8
database_version: POSTGRES_13
tier: db-g1-small
```

renders the `SQLInstance` `db`, reachable on the network's private
services access range only (`tests/golden/basic.yaml`). The network needs
its private services access connection first (the `net-vpc` chart's
`psa_configs`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.instance` | not a fabric variable: the primary's cloud name in full, used as given (no `namePrefix`, no `prefix`) and checked against 98 characters, starting with a letter; not set, it derives from `name` (`docs/design.md`, "Names, labels and tags"). Read replicas are named by their keys, as in fabric |
| `namePrefix` | not a fabric variable: an optional convenience. When set, the derived instance names (the primary and every replica) start with `<namePrefix>-`, in front of the module's own `prefix`; never a name set under `names`; empty changes nothing |
| `labels` | Kubernetes labels on every object; an unprefixed key also becomes a Google Cloud label (Config Connector copies it to the instances' user labels), so it must be a valid one. fabric's `labels`, the instances' user labels, are these |
| `tags` | cloud labels on every object (Google Cloud labels) |
| `name`, `prefix` | the primary's name, `<prefix>-<name>` (`<name>` with `prefix` null); `prefix` cannot be `""`, as in fabric |
| `project_id` | the `cnrm.cloud.google.com/project-id` annotation of every object |
| `region`, `database_version`, `encryption_key_name` | the primary `SQLInstance`'s `region`, `databaseVersion` and `encryptionKMSCryptoKeyRef` |
| `tier`, `edition`, `availability_type`, `activation_policy`, `collation`, `connector_enforcement`, `time_zone`, `disk_type`, `disk_autoresize_limit`, `gcp_deletion_protection` | `settings` fields of the same meaning (`deletionProtectionEnabled` for `gcp_deletion_protection`) |
| `disk_size` | `settings.diskSize`; null turns `diskAutoresize` on, as fabric does |
| `data_cache` | `settings.dataCacheConfig`, on `ENTERPRISE_PLUS` only, as fabric applies it |
| `flags` | `settings.databaseFlags`, on the primary and every replica |
| `network_config` (required) | `settings.ipConfiguration`: `public_ipv4` is `ipv4Enabled`, `psa_config.private_network` is `privateNetworkRef`, `allocated_ip_ranges.primary` and `.replica` the `allocatedIpRange` of each, `authorized_networks` (`{NAME: CIDR}`) `authorizedNetworks`, `psc_config` a `pscConfig` with `pscEnabled: true` and its `allowed_consumer_projects`, `enable_private_path_for_services` `enablePrivatePathForGoogleCloudServices`. `psc_allowed_consumer_projects` is refused when not empty, as fabric refuses it (obsolete) |
| `ssl.mode`, `ssl.client_certificates` | `ipConfiguration.sslMode`; one `SQLSSLCert` per common name on the primary |
| `backup_configuration` | `settings.backupConfiguration`, with fabric's defaults and rules: binary logging on for MySQL with backups when asked, or when there are replicas or regional availability; point-in-time recovery explicitly off when backups are; retained backups counted only when backups are on. null leaves backups to the cloud |
| `insights_config` | `settings.insightsConfig` with `queryInsightsEnabled: true`; null disables Query Insights |
| `maintenance_config` | `settings.maintenanceWindow` and `settings.denyMaintenancePeriod` (its `time` defaults to `00:00:00`, as fabric's) |
| `password_validation_policy` | `settings.passwordValidationPolicy`; `default_complexity: true` is `COMPLEXITY_DEFAULT`, otherwise unset as fabric leaves it; `change_interval` (seconds) becomes `"<n>s"` |
| `replicas` | one `SQLInstance` per entry, `hfl.dev/id` `replica:<key>`, named `<prefix>-<key>`, its `masterInstanceRef` the primary: its own `region`, `encryption_key_name`, `availability_type` and `tier` (the primary's when unset), and the primary's disk, flags, network and SSL settings, as fabric copies them |
| `databases` | one `SQLDatabase` each on the primary, `hfl.dev/id` `database:<name>` |
| `users` | one `SQLUser` each on the primary, `hfl.dev/id` `user:<key>`, for `CLOUD_IAM_USER` and `CLOUD_IAM_SERVICE_ACCOUNT` users; on PostgreSQL a user's name drops `.gserviceaccount.com`, as fabric's (below for `BUILT_IN`) |
| `terraform_deletion_protection` | accepted and ignored, whatever its value (below, "Differences from the module") |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the instances, databases and users when the component is deleted |

Refused when set:

| Variable | Why |
| --- | --- |
| `root_password`, `users` of type `BUILT_IN` (the default type) | a password given in values would be in the rendered manifest, and Terraform's `random_password` has no Config Connector equivalent. `SQLInstance` and `SQLUser` take a password from a Kubernetes Secret (`valueFrom.secretKeyRef`), which the chart does not take yet: how a component gets a database password is an open question. SQL Server needs a root password, so it cannot be created with this chart yet |
| `users[].database_roles`, `users[].password_version` | `SQLUser` has no such fields |
| `data_api_access`, `enable_dataplex_integration` | `SQLInstance` has no such fields |
| `backup_configuration.retain_backups_on_delete`, `backup_configuration.final_backup` | `SQLInstance` has no such fields |
| `insights_config.enhanced_query_insights_enabled: true` | `insightsConfig` has no such field |
| `managed_connection_pooling_config.enabled: true` on PostgreSQL `ENTERPRISE_PLUS` (where fabric applies it; elsewhere ignored, as in fabric) | `SQLInstance` has no connection pool field |
| `network_config.connectivity.psc_config`'s `network_attachment_uri`, `psc_auto_connection_policy_enabled`, `psc_auto_connections`, `psc_auto_dns_enabled`, `psc_write_endpoint_dns_enabled` | `pscConfig` has only `pscEnabled` and `allowedConsumerProjects` |
| `context` | use Bundt's `${...}` expressions and `valueFrom` |

## Outputs

| Output | From |
| --- | --- |
| `name`, `names` | the instances' `spec.resourceID` |
| `id`, `ids` | `projects/<project>/instances/<name>`, as Terraform's `id` |
| `connection_name`, `connection_names` | `status.connectionName` |
| `dns_name`, `dns_names` | `status.dnsName`, or null |
| `ip`, `ips` | `status.privateIpAddress` (fabric's `ip` is the private address), or null |
| `psc_service_attachment_link`, `psc_service_attachment_links` | `status.pscServiceAttachmentLink`, or null |
| `self_link`, `self_links` | `status.selfLink` |

The maps are keyed `primary` and each replica's key, as fabric keys them.
Not outputs: `client_certificates`, `instances` and `user_passwords`, whole
or sensitive Terraform objects (`docs/design.md`, "Outputs"); the chart
makes no passwords.

## Differences from the module

- **`terraform_deletion_protection`** (default `true`) is accepted and
  does nothing, whatever its value: it is Terraform's own guard, and
  `SQLInstance` has no field for it. `gcp_deletion_protection` (default
  `true`) is Google's, and is carried: while it is on, deleting the
  component fails at the cloud and the instance stays, so set it to
  `false` first, or use `deletion_policy: ABANDON` to keep the instance.
- **Passwords**: no `BUILT_IN` users and no root password (above).
- **Client certificates**: Config Connector keeps a `SQLSSLCert`'s private
  key in the object's `status`, where Terraform keeps it in its state:
  whoever can read the object in the cluster can read the key.
- **Outputs** come from the live objects, so a dependent waits until they
  are ready.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/cloudsql-instance`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloudsql-instance)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml)
records the repository, path, release, commit, licence and the date last
synced, and the module is listed in
[`upstream/modules.yaml`](../../../upstream/modules.yaml) with every other
module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=cloudsql-instance`: render cases `basic` (the module
README's example), `full` (every accepted input: regional MySQL with
backups, insights, maintenance, a password policy, two replicas, databases,
IAM users, a client certificate, ABANDON), `postgres-iam` (PostgreSQL,
Private Service Connect, backups off, service account users), `names` and
`mock`, each validated against Config Connector v1.160.0's CRD schemas, and
the refusals in `tests/*.fail.yaml`. `tests/name-prefix.yaml` exempts the
kinds named inside their instance.

`tests/mock.values.yaml` (a small PostgreSQL instance and one database) is
for the fake cloud (`task test-mock`); it has not run yet.

## Changes

- **0.1.0** (2026-11-12): the port.
