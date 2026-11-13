# folder

A Google Cloud folder (or an existing one) with its IAM, organization
policies, essential contacts, logging sinks, exclusions and data access
logs, PAM entitlements, tag bindings, hierarchical firewall policy
association and Autokey configuration, as Config Connector objects. A
partial port of Cloud Foundation Fabric's
[`modules/folder`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/folder)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-folder` (`package.yaml`). Checked against Config Connector v1.160.0.

The templates for IAM, organization policies, logging and PAM are the
`project` chart's, on a `Folder` instead of a `Project`.

## Example

```yaml
parent: folders/1122334455
name: Folder name
iam:
  roles/owner: ["group:organization-admins@example.org"]
```

renders the `Folder` `Folder name` and an `IAMPartialPolicy` holding
`roles/owner` on it (`tests/golden/basic.yaml`): the module README's first
example.

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.folder` | not a fabric variable: the folder's display name in full, used as given (no `namePrefix`), at most 30 characters (`docs/design.md`, "Names, labels and tags") |
| `namePrefix` | not a fabric variable: an optional convenience; when set, every name the chart derives (the display name, sinks, exclusions, entitlements) starts with `<namePrefix>-`; empty changes nothing |
| `labels`, `tags` | Kubernetes labels on every object; unprefixed ones and `tags` reach the resources that take Google Cloud labels |
| `folder_create`, `name`, `parent` | the `Folder`, its display name `name`, under `parent` (`folders/N` or `organizations/N`, fabric's check); `folder_create: false` makes none |
| `id` | the existing folder (`folders/N`) everything else goes on when `folder_create` is false (fabric's check that it is set) |
| `iam`, `iam_bindings`, `iam_bindings_additive`, `iam_by_principals`, `iam_by_principals_additive`, `iam_by_principals_conditional` | the folder's IAM, as the `project` chart's: authoritative roles in one `IAMPartialPolicy`, exact bindings as `IAMBinding`s, additive ones as `IAMPolicyMember`s; conditional bindings by principal merged into bindings by role and condition title, with fabric's checks (`docs/design.md`, "IAM") |
| `contacts` | an `EssentialContactsContact` per email, in English, subscribed to its notification types (fabric's check of the types) |
| `org_policies` | an `OrgPolicyPolicy` per constraint on the folder: rules with allow, deny, enforce, conditions and parameters, `inherit_from_parent`, `reset`; a `dry_run:` key is the policy's dry-run spec |
| `firewall_policy` | a `ComputeFirewallPolicyAssociation`, `name`, of the hierarchical policy `policy` (an ID or `locations/global/firewallPolicies/<id>`) with the folder |
| `autokey_config` | a `KMSAutokeyConfig` on the folder naming the key project |
| `tag_bindings` | a `TagsTagBinding` per entry, of the tag value on the folder |
| `logging_data_access` | an `IAMAuditConfig` per service with its log types and exempted members |
| `logging_exclusions` | a `LoggingLogExclusion` per entry, described `<name> (Terraform-managed).` |
| `logging_sinks` | a `LoggingLogSink` per entry on the folder (`include_children`, default true, filter, exclusions, `disabled`, BigQuery partitioned tables), and, with `iam` (the default), an `IAMPolicyMember` granting its writer identity write access to the destination, as fabric grants it. Refused: `intercept_children` (`LoggingLogSink` has no `interceptChildren`; fabric allows it only for a `project` sink), type `project` (a sink's destination is never a project), and `iam` on a `bigquery` sink (dataset IAM is the alpha `BigQueryDatasetAccess`: set `iam: false`) |
| `pam_entitlements` | a `PrivilegedAccessManagerEntitlement` per entry on the folder, as the `project` chart's |
| `deletion_protection` | `false`, the default, is accepted; `true` is refused: Config Connector's `Folder` has no `deletionProtection` (`deletion_policy: ABANDON` keeps the folder when the component is deleted) |
| `context`, `factories_config`, `asset_search` | refused, by design: Bundt replaces `$context` lookups with `${...}` expressions; a chart cannot read the caller's files (their entries go in `org_policies` and `pam_entitlements`); a search is a read at plan time, not a resource |
| `asset_feeds`, `assured_workload_config`, `scc_sha_custom_modules` | refused: `CloudAssetFolderFeed`, `AssuredWorkloadsWorkload` and `SecurityCenterManagementSecurityHealthAnalyticsCustomModule` are `v1alpha1` kinds, not ported yet |
| `iam_deny_policies` | an `IAMDenyPolicy` of config-connector-extensions (`iam.gcp.hfl.dev/v1beta1`) per entry on the folder, named by its key: `display_name`, and each rule's description, denied and exception principals and permissions and denial condition; fabric's check that a rule has a denied principal and a denied permission |
| `cloud_armor_policy`, `logging_settings`, `scc_mute_configs`, `service_agents_config` | refused, gaps: Config Connector has no kind for an organization security policy association, a folder's logging settings, a Security Command Center v2 mute config or a folder's service identities |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the cloud resources |

## Outputs

`id` (`folders/N`: the new folder's, read from its status, else `id`),
`name` (the new folder's display name), `organization_policies_ids` and
`sink_writer_identities`, keyed as fabric keys them. Not outputs:
`asset_search_results`, `assured_workload`, `scc_custom_sha_modules_ids`
and `service_agents` (their variables are refused), and fabric's whole
object (`folder`; `docs/design.md`, "Outputs").

## From Terraform

A `module "x" { source = ".../modules/folder" ... }` block's arguments
become the values unchanged, but for the refused variables above. To
adopt an existing folder, set `folder_create: false` and its `id`: the
folder itself stays outside the component, and its IAM, policies and
logging come under it (`docs/design.md`, "From Terraform").

## Differences from the module

- The description of a logging bucket sink's writer grant names the
  folder by its display name when the chart makes the folder (fabric
  writes `folders/N`, which is not known before the folder exists).

## Config Connector gaps

Found porting this module, for config-connector-extensions: `Folder` has no
`deletionProtection`; `LoggingLogSink` has no `interceptChildren`; no
kinds for `google_compute_organization_security_policy_association`,
`google_logging_folder_settings`,
`google_scc_v2_folder_mute_config` or `google_folder_service_identity`
(`docs/coverage/blocked-kinds.md`).

## Config Connector bugs

- **config-connector-extensions' `IAMDenyPolicy` cannot be deleted once
  its `Folder` object is gone.** In the fake cloud (2026-11-13, run
  `off-catalog-1113174707-3197`, config-connector-extensions `3de8de68`),
  a deny policy on the chart's new folder became Ready, but when every
  object was deleted at once its delete failed with `referenced Folder
  catalog-folder/mock not found`: the kind resolves its `folderRef` again
  to delete (the generated kinds no longer do; this one is not generated).
  Deleting a component should delete its deny policies before the folder,
  or the kind should delete by its recorded name. The deny policy is out
  of `tests/mock.values.yaml` until then; it is render-tested.

- **An `OrgPolicyPolicy` on a `Folder` object cannot be deleted once the
  `Folder` object is gone.** In the fake cloud (2026-11-13, run
  `off-catalog-1113154153-13593`, config-connector-extensions `d54a2075`),
  deleting every object at once left the policy stuck with "Update call
  failed: referenced Folder catalog-folder/mock not found": its controller
  resolves `folderRef.name` on delete, and the cloud policy goes with the
  folder anyway. Deleting a component should therefore delete its org
  policies before the folder (or Config Connector should skip the lookup
  on delete). The fake-cloud case leaves org policies out for this reason;
  they are render-tested only.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/folder`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/folder)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=folder`: render cases `basic` (fabric's README example),
`full` (every value the chart carries), `existing` (an existing folder),
`names`, `deny` (IAM deny policies) and `mock`, validated against Config Connector v1.160.0's CRD
schemas, and the refusals in `tests/*.fail.yaml`.

Applied to the fake cloud on 2026-11-13 on an offload VM (`task test-mock
MOCK_CHARTS=folder`, run `off-catalog-1113160429-12717`, at
config-connector-extensions `d54a2075`): `tests/mock.values.yaml`, a
folder under an organization with an authoritative role, an additive
member and a logging exclusion: all 4 objects Ready, the outputs evaluated
(`id` the folder's `folders/N`), all deleted. An earlier run with an org
policy evaluated `organization_policies_ids` and left the policy undeleted
("Config Connector bugs"). A run with an IAM deny policy (run
`off-catalog-1113174707-3197`, config-connector-extensions `3de8de68`)
had all 5 objects Ready, the deny policy included, and every one but the
deny policy deleted (same section). Contacts, sinks, PAM, tag bindings, the
firewall policy association and Autokey are render-tested only.

Not applied live: live runs are pending KEYLIVE (and the test provisioner's
folder, `docs/design.md`, "The test provisioner").

## Changes

- **0.2.0** (2026-11-13): `iam_deny_policies` as config-connector-extensions'
  `IAMDenyPolicy`.
- **0.1.0** (2026-11-13): the port: the folder, its IAM, organization
  policies, contacts, logging, PAM entitlements, tag bindings, firewall
  policy association and Autokey configuration.
