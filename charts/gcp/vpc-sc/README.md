# vpc-sc

VPC Service Controls as Config Connector objects: an Access Context
Manager access policy (or an existing one), its access levels, regular
service perimeters with the ingress and egress policies they name, and IAM
on the policy. A port of Cloud Foundation Fabric's
[`modules/vpc-sc`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/vpc-sc)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-vpc-sc` (`package.yaml`). Checked against Config Connector v1.160.0.

**Organization-scoped.** Access policies, levels and perimeters belong to
the organization, not a project: the chart has no `project_id`, and runs
only in a platform namespace whose Config Connector account has Access
Context Manager roles on the organization (`docs/design.md`,
"Organization, folders and Config Connector's scope").

## Example

```yaml
access_policy: "12345678"
access_levels:
  a1:
    conditions:
      - members: ["user:user1@example.com"]
perimeters:
  p1:
    status:
      access_levels: ["$access_levels:a1"]
      resources: [projects/11111]
      restricted_services: [storage.googleapis.com]
```

renders an `AccessContextManagerAccessLevel` `a1` and an
`AccessContextManagerServicePerimeter` `p1` in policy `12345678`
(`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.policy` | not a fabric variable: the created access policy's title in full, used as given (no `namePrefix`) (`docs/design.md`, "Names, labels and tags"). Access levels and perimeters are named by their keys, as fabric names them |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the policy's title starts with `<namePrefix>-`, and every access level's and perimeter's name with `<namePrefix>_` (its hyphens as underscores: these names hold only letters, digits and `_`, at most 50 characters, checked); empty changes nothing |
| `labels`, `tags` | Kubernetes labels on every object; these resources take no Google Cloud labels |
| `access_policy` | the existing policy (its number) every level, perimeter and IAM object refers to, as `accessPolicies/<number>` |
| `access_policy_create` | an `AccessContextManagerAccessPolicy` titled `title` in the organization `parent` names (the `organization-id` annotation); levels, perimeters and IAM refer to it by its object's name. When set, it wins over `access_policy`, as fabric's `try` |
| `access_levels` | one basic `AccessContextManagerAccessLevel` each, named by its key, titled `title` or the name: `combining_function`, `description`, and each condition's device policy, `ip_subnetworks`, `members`, `negate`, `regions` and `required_access_levels` (`$access_levels:<KEY>` is this chart's level) |
| `ingress_policies`, `egress_policies` | copied into each perimeter block that names them (`$ingress_policies:<KEY>`, `$egress_policies:<KEY>`), as fabric's dynamic blocks do: identity type, identities, ingress sources (access levels, resources), operations with method and permission selectors, resources, and an egress policy's external resources |
| `perimeters` | one regular `AccessContextManagerServicePerimeter` each, named by its key, titled `title` or the name, with `description`, `use_explicit_dry_run_spec`, and its `spec` (dry run) and `status` (enforced): access levels, resources, restricted services, ingress and egress policies, and VPC accessible services (`RESTRICTED-SERVICES` added when `enable_restriction` and `allow_all_restricted_services`, as fabric). A policy a perimeter names that is not defined stops the render with fabric's "Undefined ingress policies" message |
| `factories_config` | accepted and ignored: a chart cannot read the caller's files (`docs/design.md`, "Submodules and factories") |
| `factories_data` | not a fabric variable: the factory folders' files, by file name, each the file's content: `access_levels`, `egress_policies`, `ingress_policies`, `perimeters`. A key in a file and in the matching variable is the variable's, as fabric's `merge` |
| `iam`, `iam_bindings` | one `IAMPartialPolicy` on the policy (`IAMBinding` does not take this kind) |
| `iam_bindings_additive` | one `IAMPolicyMember` each |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the policy, levels and perimeters |

Members and identities: `user:<email>` becomes `user`, and
`serviceAccount:<email>` an external `serviceAccountRef`. Resources
(`projects/<number>`, or a VPC network's full name) become external
`projectRef`s, given as the API takes them.

Refused when set:

| Variable or field | Why |
| --- | --- |
| `context`, and any other `$...` value (`$identity_sets:`, `$resource_sets:`, `$project_numbers:`, ...) | by design: Bundt replaces fabric's `$context` lookups with `${...}` expressions and `valueFrom` in the component's inputs |
| `project_id_search_scope` | by design: a search is a read, not a resource; give `projects/<number>`, from another component's output |
| `access_policy_create.scopes` | gap: `AccessContextManagerAccessPolicy` has no scopes field (Config Connector ignores it) |
| `access_levels.*.conditions.vpc_subnets` | gap: `AccessContextManagerAccessLevel` has no `vpcNetworkSources` |
| `access_levels.*.conditions.members` of `group:` | gap: an access level's members are users and service accounts only |
| `ingress_policies.*` and `egress_policies.*`: `title`, `to.roles`, `from.psc_endpoints`, identities of `group:`, `principal:` or `principalSet:` | gap: `AccessContextManagerServicePerimeter`'s policies have no title, roles or PSC endpoint sources, and their identities are users and service accounts only |
| `egress_policies.*.from.access_levels`, `from.resources` | gap: `egressFrom` has no sources |
| `perimeters.*.{spec,status}.vpc_accessible_services.allowed_service_patterns` | gap: `vpcAccessibleServices` has no `allowedServicePatterns` |
| `perimeters.*.ignore_resource_changes` | gap: fabric's additive perimeters ignore changes to their resources; Config Connector cannot ignore a field's changes |
| `iam_bindings.*.condition`, `iam_bindings_additive.*.condition` | gap: Config Connector's IAM on this kind takes no conditions |
| `deletion_policy: PREVENT` | no Config Connector equivalent |

Differences from Terraform:

- fabric titles each ingress and egress policy after its key; Config
  Connector has no title field, so the policies are untitled.
- A `$access_levels:<KEY>` reference to a level the chart does not define
  stops the render; fabric would send the string to the API.

## Outputs

| Output | Value |
| --- | --- |
| `id`, `access_policy_name` | the policy's number: the created policy's, which Google assigns (`status.name`), else `access_policy` |
| `access_level_names` | each access level's key to its resource name, `accessPolicies/<policy>/accessLevels/<name>` |

fabric's `access_levels`, `access_policy` and `perimeters` are whole
Terraform objects, which a Package does not output (`docs/design.md`,
"Outputs").

## From Terraform

A `module "x" { source = ".../modules/vpc-sc" ... }` block's arguments
become the values unchanged; a factory folder's files go under
`factories_data` (`examples/vpc-sc/`). To adopt existing levels and
perimeters, keep their names: Config Connector acquires the levels and
perimeters of those names. An existing access policy is best kept as
`access_policy` (its number), since a policy's cloud name is the number
Google assigned it (`docs/design.md`, "From Terraform").

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/vpc-sc`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/vpc-sc)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=vpc-sc`: render cases `basic`, `full`, `names` and `mock`,
each validated against Config Connector v1.160.0's CRD schemas, and the
refusals in `tests/*.fail.yaml`.

`tests/mock.values.yaml` (a created policy in a placeholder organization,
one access level, one perimeter around a placeholder project number) is
for `hack/mock-apply.sh` (`task test-mock`), which now installs Access
Context Manager's CRDs in the fake cloud. Run on 2026-11-12 on an offload
VM (`off-catalog-1112191603-19867`, config-connector-extensions
`1de95478`): the policy, the level and the perimeter Ready, the outputs
evaluated (`id` the number mockgcp assigned, `access_level_names` the
level's resource name), and all three deleted at once and gone.

No live run: the chart acts on an organization, and the live-test
service accounts have no Access Context Manager roles there.

## Changes

- **0.1.0** (2026-11-12): the port.
