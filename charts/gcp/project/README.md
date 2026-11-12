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
| `tags` | cloud labels on every object (Google Cloud labels); a value that is a map is fabric's `tags` (tag keys), not ported yet and refused |
| `name`, `prefix`, `descriptive_name`, `parent`, `billing_account`, `auto_create_network` | `Project` `<prefix>-<name>` (checked: 6 to 30 characters) under the folder or organization; `auto_create_network` as Config Connector's annotation |
| `project_reuse` | no project: everything else goes on the existing project `<prefix>-<name>` |
| `deletion_policy` | `DELETE` (default) or `ABANDON`; `PREVENT` is refused: use `lien_reason` |
| `lien_reason` | `ResourceManagerLien` restricting `resourcemanager.projects.delete` |
| `services`, `service_config` | one `Service` each; `disable_on_destroy` and `disable_dependent_services` as Config Connector's annotations (both false, as fabric) |
| `iam`, `iam_by_principals` | one `IAMPartialPolicy` on the project |
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
| `tag_bindings` | one `TagsTagBinding` each on the project: the `Project` object (Config Connector reads its number), or with `project_reuse` the number in `project_reuse.attributes.number`, which it then needs |

## Not ported

Config Connector has kinds for these; the chart refuses them until they
are mapped: `logging_sinks`, `logging_metrics`, `log_scopes`,
`metric_scopes`, `notification_channels`, `alerts`, `asset_feeds`,
`bigquery_reservations`, `tags`, `network_tags`, `tags_config`,
`kms_autokeys`, `service_encryption_key_ids`, `workload_identity_pools`,
`pam_entitlements`, `iam_deny_policies` (alpha), `scc_mute_configs`
(alpha), `scc_sha_custom_modules` (alpha), `vpc_sc`, `quotas`,
`factories_config`, `service_agents_config`,
`service_agents_folder_bindings`, `service_agents_project_bindings`,
`iam_by_principals_conditional`.

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

With `project_reuse` there is no project object, so `name` and `number`
have no value.

## Alpha

The chart has no `allow_alpha` value yet: it ports no alpha kind.
`iam_deny_policies`, `scc_mute_configs` and `scc_sha_custom_modules` need
one and are listed under "Not ported"; they will come behind
`allow_alpha` (docs/design.md, "Alpha kinds").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/project`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/project)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=project`: five render cases, ten refusals.
`tests/mock.values.yaml` (no lien and no Shared VPC: mockgcp has
neither) is applied to the fake cloud.

## Changes

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
