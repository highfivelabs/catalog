# organization

An existing Google Cloud organization's IAM, custom roles, organization
policies and custom constraints, essential contacts, logging sinks,
exclusions and data access logs, PAM entitlements, tag keys and values,
network tags, tag bindings, hierarchical firewall policy association,
access levels, asset feeds and Workforce Identity Federation pools, as
Config Connector objects. A partial port of Cloud Foundation Fabric's
[`modules/organization`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/organization)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-organization` (`package.yaml`). Checked against Config Connector
v1.160.0.

The chart never makes an organization (nothing can): everything it renders
goes on the one `organization_id` names. The templates for IAM,
organization policies, logging and PAM are the `folder` chart's, and those
for custom roles and tags the `project` chart's, on the organization
(`organizationRef`, or an IAM `resourceRef` of kind `Organization`).

## Example

```yaml
organization_id: organizations/1122334455
iam_by_principals:
  "group:organization-admins@example.org": [roles/owner]
org_policies:
  compute.skipDefaultNetworkCreation:
    rules: [{enforce: true}]
```

renders an `IAMPartialPolicy` holding `roles/owner` on the organization and
an `OrgPolicyPolicy` enforcing the constraint. `tests/basic.values.yaml` is
the module README's first example in full (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `organization_id` | the organization everything goes on, `organizations/N` (fabric's check); required |
| `names` | not a fabric variable: the chart makes no collision-prone resource of its own, so it takes no key |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the names the chart derives (sinks, exclusions, entitlements, tag keys, the firewall policy association) start with `<namePrefix>-`; custom roles and custom constraints take none (their IDs take no `-`); empty changes nothing |
| `labels` | Kubernetes labels on every object; unprefixed ones reach the resources that take Google Cloud labels |
| `iam`, `iam_bindings`, `iam_bindings_additive`, `iam_by_principals`, `iam_by_principals_additive`, `iam_by_principals_conditional` | the organization's IAM, as the `folder` chart's: authoritative roles in one `IAMPartialPolicy`, exact bindings as `IAMBinding`s, additive ones as `IAMPolicyMember`s; conditional bindings by principal merged into bindings by role and condition title, with fabric's checks (`docs/design.md`, "IAM") |
| `custom_roles` | an `IAMCustomRole` per entry on the organization (the `cnrm.cloud.google.com/organization-id` annotation), its ID the key, titled `Custom role <key>` and described `Terraform-managed.` unless given; fabric's check of the stage |
| `contacts` | an `EssentialContactsContact` per email, in English, subscribed to its notification types (fabric's check of the types) |
| `org_policies` | an `OrgPolicyPolicy` per constraint on the organization: rules with allow, deny, enforce, conditions and parameters, `inherit_from_parent`, `reset`; a `dry_run:` key is the policy's dry-run spec |
| `org_policy_custom_constraints` | an `OrgPolicyCustomConstraint` per entry, named by its key (`custom.<name>`), with its resource and method types, condition, action, display name and description |
| `firewall_policy` | a `ComputeFirewallPolicyAssociation`, `name`, of the hierarchical policy `policy` (an ID or `locations/global/firewallPolicies/<id>`) with the organization |
| `tags` | a map value: fabric's tag key, one `TagsTagKey` on the organization (unless it has an `id`; its short name takes the `namePrefix`) and one `TagsTagValue` per value (unless it has an `id`), each with its IAM as the module-level IAM variables; `allowed_values_regex` and IAM conditions are refused (no such field; tag keys and values take no conditions). A string value: a cloud label on every object (the catalog's `tags`) |
| `network_tags` | the same, as tag keys with purpose `GCE_FIREWALL` on the network (`<project>/<vpc>`, or `ALL`; fabric's check) |
| `tags_config` | `ignore_iam` skips the tag keys' and values' IAM; `force_context_ids` is refused (Bundt replaces `$context` ids) |
| `tag_bindings` | a `TagsTagBinding` per entry, of the tag value on the organization |
| `logging_data_access` | an `IAMAuditConfig` per service with its log types and exempted members |
| `logging_exclusions` | a `LoggingLogExclusion` per entry, described `<name> (Terraform-managed).` |
| `logging_sinks` | a `LoggingLogSink` per entry on the organization (type `logging` by default, `include_children`, default true, filter, exclusions, `disabled`, BigQuery partitioned tables), and, with `iam` (the default), an `IAMPolicyMember` granting its writer identity write access to the destination, as fabric grants it. Refused: `intercept_children` (`LoggingLogSink` has no `interceptChildren`; fabric allows it only for a `project` sink), type `project` (a sink's destination is never a project), and `iam` on a `bigquery` sink (dataset IAM is the alpha `BigQueryDatasetAccess`: set `iam: false`) |
| `pam_entitlements` | a `PrivilegedAccessManagerEntitlement` per entry on the organization, as the `folder` chart's |
| `access_policy`, `access_levels` | a basic `AccessContextManagerAccessLevel` per entry in the access policy `access_policy` (its number), named by its key (with a `namePrefix`, `<namePrefix>_<key>`, hyphens as underscores), titled by its title or key, with its combining function and conditions: device policy, IP subnetworks, members (users and service accounts, fabric's check), `negate`, regions, required access levels (another level's resource name, or `$access_levels:<key>` for one of this chart's); fabric's checks of the combining function, encryption statuses and management levels. A condition's `vpc_subnets` is refused (`AccessContextManagerAccessLevel` has no `vpcNetworkSources`) |
| `asset_feeds` | an `AssetFeed` per entry on the organization, its ID the key, to the Pub/Sub topic `projects/<project>/topics/<topic>`, with its content type (fabric's check), asset types and names and condition. `billing_project` is not carried ("Differences from the module") |
| `workforce_identity_pools` | an `IAMWorkforcePool` per entry on the organization (location `global`, its ID the key) and an `IAMWorkforcePoolProvider` per provider: attribute condition and mapping (on fabric's `azuread` or `okta` template when named), `disabled`, and an OIDC (issuer, client ID, JWKS, web SSO config) or SAML identity provider, with fabric's checks. Refused: `access_restrictions` (`IAMWorkforcePool` has none); a provider's `detailed_audit_logging: true`, `scim_usage` and `oauth2_client_config` (`IAMWorkforcePoolProvider` has none); `scim_tenant` (no kind); an OIDC `client_secret` (its value would be in the rendered manifest, and `path` names a file on the caller's machine) |
| `context`, `factories_config`, `asset_search` | refused, by design: Bundt replaces `$context` lookups with `${...}` expressions; a chart cannot read the caller's files (their entries go in `custom_roles`, `org_policies`, `org_policy_custom_constraints`, `pam_entitlements` and `tags`); a search is a read at plan time, not a resource |
| `cloud_armor_policy`, `context_aware_access_bindings`, `iam_deny_policies`, `model_armor_floor_setting`, `scc_mute_configs`, `scc_sha_custom_modules` | refused: `ComputeOrganizationSecurityPolicyAssociation`, `AccessContextManagerGCPUserAccessBinding`, `IAMDenyPolicy`, `ModelArmorFloorSetting`, `SecurityCenterMuteConfig` and `SecurityCenterManagementSecurityHealthAnalyticsCustomModule` are `v1alpha1` kinds, not ported yet |
| `logging_settings`, `service_agents_config` | refused, gaps: Config Connector has no kind for an organization's logging settings or its service identities (`ServiceIdentity` takes only a project) |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the cloud resources |

## Outputs

`id` and `organization_id` (`organization_id` as given),
`custom_constraint_ids` (`organizations/N/customConstraints/<name>`),
`custom_role_id` (`organizations/N/roles/<id>`),
`organization_policies_ids`, `sink_writer_identities`, and `tag_keys`,
`tag_values`, `network_tag_keys` and `network_tag_values` (each new key's
or value's `tagKeys/N` or `tagValues/N`), `workforce_identity_pool_ids`
and `workforce_identity_provider_names` (`locations/global/workforcePools/...`),
keyed as fabric keys them. Not outputs: `asset_search_results`,
`context_aware_access_bindings`, `logging_identities`,
`scc_custom_sha_modules_ids`, `scc_mute_configs`, `scim_tenants` and
`service_agents` (their variables are refused), and fabric's whole objects
(`access_levels`, `custom_roles`, `logging_sinks`,
`workforce_identity_providers`; `docs/design.md`, "Outputs").

## From Terraform

A `module "x" { source = ".../modules/organization" ... }` block's
arguments become the values unchanged, but for the refused variables
above. The organization itself is never under the component: only what the
chart renders on it.

## Differences from the module

- fabric orders an organization policy after the custom constraints and tag
  keys of the same call (`depends_on`); Config Connector retries a policy
  on a constraint that does not exist yet until it does, so the chart has
  no order to keep.
- An asset feed's `billing_project` is not carried: `AssetFeed` has no
  field for it, and Config Connector bills the Cloud Asset API call to the
  billing project its controller is configured with (with none, a feed on
  an organization may be refused for want of a quota project).

## Config Connector gaps

Found porting this module, for config-connector-extensions:
`LoggingLogSink` has no `interceptChildren`; `TagsTagKey` has no
`allowedValuesRegex`; `AccessContextManagerAccessLevel` has no
`vpcNetworkSources`; `IAMWorkforcePool` has no `accessRestrictions`;
`IAMWorkforcePoolProvider` has no `detailedAuditLogging`, `scimUsage` or
OAuth 2.0 client attributes; `AssetFeed` has no billing project; no kinds
for `google_logging_organization_settings`,
`google_organization_service_identity` or
`google_iam_workforce_pool_provider_scim_tenant`
(`docs/coverage/blocked-kinds.md`).

## Config Connector bugs

- **An `OrgPolicyPolicy` cannot be deleted once the object its parent
  reference names is gone** (the `folder` chart's README, "Config Connector
  bugs"): its controller resolves the reference on delete. This chart's
  policies name the organization by `organizationRef.external`, which is
  never a Kubernetes object, so they do not hit it; but a policy on a
  custom constraint the same component makes still needs the constraint
  until the policy is gone. No test here depends on the order Config
  Connector deletes objects in.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/organization`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/organization)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=organization`: render cases `basic`, `iam-bpc`,
`custom-constraints`, `tags`, `logging`, `pam`, `workforce` and
`access-levels` (the module README's
examples, less what the chart refuses), `full` (every value the chart
carries), `names` and `mock`, validated against Config Connector
v1.160.0's CRD schemas, and the refusals in `tests/*.fail.yaml`.

The fake-cloud run is pending (`task test-mock MOCK_CHARTS=organization`;
`tests/mock.values.yaml`, on a fake organization ID).

Not applied live: live runs are pending KEYLIVE, and a live run needs an
organization the test identity may change (nothing can create one).

## Changes

- **0.2.0** (2026-11-13): access levels (`access_policy`,
  `access_levels`), asset feeds and Workforce Identity Federation pools
  and providers; the `workforce_identity_pool_ids` and
  `workforce_identity_provider_names` outputs.
- **0.1.0** (2026-11-13): the port: the organization's IAM, custom roles,
  organization policies and custom constraints, contacts, logging, PAM
  entitlements, tag keys, network tags, tag bindings and firewall policy
  association.
