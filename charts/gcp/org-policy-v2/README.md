# org-policy-v2

One organization policy, on a boolean or a list constraint, set on an
organization, a folder or a project, with its exclusions on folders and
projects below it, as Config Connector `OrgPolicyPolicy` objects. A port of
terraform-google-modules'
[`org-policy`](https://registry.terraform.io/modules/terraform-google-modules/org-policy/google)
module at v7.4.0 (`36ead6c0`), Apache-2.0, Copyright Google LLC:
[`modules/org_policy_v2`](https://github.com/terraform-google-modules/terraform-google-org-policy/tree/36ead6c0035c8520bc32b72449ec9819b2d5b574/modules/org_policy_v2).
Bundt Package `gcp-org-policy-v2` (`package.yaml`). Checked against Config
Connector v1.160.0.

Organization and folder policies need organization or folder roles, so
this Package runs only where the platform team's identity does
(`docs/design.md`, "Organization, folders and Config Connector's scope").

## Example

The offramp fixture, as values (`tests/offramp.values.yaml`):

```yaml
policy_root: folder
policy_root_id: "111111111111"
constraint: compute.skipDefaultNetworkCreation
policy_type: boolean
rules:
  - enforcement: true
```

renders one `OrgPolicyPolicy`:

```yaml
spec:
  folderRef:
    external: folders/111111111111
  resourceID: "compute.skipDefaultNetworkCreation"
  spec:
    rules:
    - enforce: true
```

A list constraint with an allow list is `tests/offramp-list.values.yaml`, a
conditional exception `tests/offramp-condition.values.yaml`, the module
README's example `tests/basic.values.yaml`.

## Objects

| Terraform resource (one of, by `policy_root` and `policy_type`) | Object | `hfl.dev/id` |
| --- | --- | --- |
| `google_org_policy_policy.org_policy_boolean`, `folder_policy_boolean`, `project_policy_boolean`, `organization_policy`, `folder_policy`, `project_policy` | `OrgPolicyPolicy` named after the component | `policy` |
| `policy_boolean_exclude_folders[<f>]`, `folder_policy_list_exclude_folders[<f>]` (not on a project root) | `OrgPolicyPolicy` `<component>-exclude-folder-<f>` on `folders/<f>` | `exclude-folder:<f>` |
| `policy_boolean_exclude_projects[<p>]`, `project_policy_list_exclude_projects[<p>]` (not on a project root) | `OrgPolicyPolicy` `<component>-exclude-project-<p>` on `projects/<p>` | `exclude-project:<p>` |

## Values: module inputs to Config Connector

Every module input is a value of the same name (`values.yaml`,
`values.schema.json`).

### Not module inputs

| Value | Renders |
| --- | --- |
| `names` | takes no key: an organization policy is named by its parent and its constraint, so the chart gives no cloud name |
| `namePrefix` | nothing, for the same reason (`tests/name-prefix.yaml`) |
| `labels` | Kubernetes labels on every object. Organization policies have no cloud labels |
| `tags` | Kubernetes labels on every object (no cloud labels to carry them to) |
| `deletion_policy` | `DELETE` (default) or `ABANDON`: every policy stays when the component is deleted. `PREVENT` is refused |

### The policy

| Module input | `OrgPolicyPolicy` |
| --- | --- |
| `policy_root`, `policy_root_id` | `organizationRef`, `folderRef` or `projectRef`: `external: <policy_root>s/<policy_root_id>` (`organizations/123`, `folders/456`, `projects/my-project`). `policy_root_id` is needed |
| `constraint` (required) | `resourceID` of every object: the constraint without `constraints/` |
| `policy_type` | `boolean` (`boolean_constraints.tf`) or `list` (`list_constraints.tf`) |
| `inherit_from_parent` (list only) | `spec.inheritFromParent` and `dryRunSpec.inheritFromParent`, `false` by default, as the module sends it |
| `rules` (required) | `spec.rules` (rules with `dry_run` false) and `dryRunSpec.rules` (`dry_run` true); a spec without rules is not rendered, as the module leaves the block out |
| `exclude_folders`, `exclude_projects` | one more policy per folder and per project (above), unless `policy_root` is `project`, where the module ignores them |

### A rule

The module first sets `enforcement` to null in a rule with an `allow` or a
`deny` list (`main.tf`, `local.rules`). Then:

| Rule | Boolean constraint | List constraint |
| --- | --- | --- |
| `enforcement` | `enforce: true` unless `enforcement` is `false` (so `true` when null, and when `allow` or `deny` is set) | `allowAll: true` when `false`, `denyAll: true` when `true`, neither when null |
| `allow` | (only nulls `enforcement`) | `values.allowedValues`, when `deny` is empty |
| `deny` | (only nulls `enforcement`) | `values.deniedValues`, when `allow` is empty |
| `parameters` (JSON) | `parameters`, parsed (a JSON object) | not sent, as the module sends none |
| `conditions` | `condition` from the one entry: `title`, `description`, `expression`, `location`, each left out when empty; `conditions = []` is no condition | the same |
| `dry_run` | the rule goes to `dryRunSpec` | the same |

The exclusions are the module's fixed specs: on a boolean constraint
`spec.rules: [{enforce: false}]`, on a list constraint `spec.reset: true`.

### Refused when set

| Input | Why |
| --- | --- |
| a `parameters` key Config Connector does not know | `OrgPolicyPolicy`'s rule parameters are a closed set of 23 managed-constraint parameters (`allowedDomains`, `allowedServices`, ...), not free JSON; another key would be dropped (`kcc.unsupported`, listed as `rules`, partial, in `upstream.yaml`) |
| `parameters` that is not a JSON object | the module passes the string to the API, which takes an object |
| two or more `conditions` in a rule | the provider's `rules.condition` takes one, as `OrgPolicyPolicy` does; Terraform refuses it at plan |
| `policy_type` other than `boolean` or `list` | the module renders nothing for it; the chart refuses it in the schema |
| `deletion_policy: PREVENT` | no Config Connector equivalent |

## Outputs

| Output | From |
| --- | --- |
| `policy_root`, `policy_root_id`, `constraint` | inputs, as the module outputs them |

## Differences from the module

- **Empty condition fields.** A condition's empty `location` (or another
  empty field) is left out rather than sent as `""`; the API stores no
  value for either. A condition whose four fields are all empty is no
  condition.
- **A list rule with both `allow` and `deny`.** The module writes a
  `values` block with neither list (each needs the other to be empty), and
  no `allowAll` or `denyAll`. What the provider sends for that empty block
  is not certain, so the chart sends no `values` and the rule carries only
  its condition, if any.
- **`policy_type`** other than `boolean` and `list` is refused rather than
  rendering nothing.
- **Exclusions on a project root** are ignored, as in the module.

## Adopting existing policies

An organization policy is named by its parent and its constraint, both
inputs, so Config Connector acquires an existing one by them: no
`resource_ids` value is needed.

## Upstream

Ported from
[`modules/org_policy_v2`](https://github.com/terraform-google-modules/terraform-google-org-policy/tree/v7.4.0/modules/org_policy_v2)
at v7.4.0 (`36ead6c0`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced,
and the module is listed in
[`upstream/modules.yaml`](../../../upstream/modules.yaml) as
`gcp/org-policy-v2`. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins". The module's
root module (the v1 API) and its `bucket_policy_only`,
`domain_restricted_sharing`, `restrict_vm_external_ips` and
`skip_default_network` submodules are not ported.

## Tests

`task test CHART=org-policy-v2`: nine render cases (`basic`,
`boolean-full`, `full`, `project`, `names`, `offramp`, `offramp-list`,
`offramp-condition`, `mock`), each validated against Config Connector
v1.160.0's CRD schemas, and the refusals in `tests/*.fail.yaml`. There is no
`name-prefix-limit.fail.yaml`: the chart gives no name a prefix could make
too long. `tests/mock.values.yaml` (a boolean constraint on `mock-project`,
since the fake cloud's runs have a project and no folder or organization of
their own) is for `hack/mock-apply.sh`
(`task test-mock`); it has not run yet.

## Changes

- **0.1.0** (2026-11-10): the port.

### Fake cloud, 2026-11-11

`task test-mock` on an offload VM (run `off-catalog-1111013211-26916`, config-connector-extensions `1de95478`): the policy Ready (UpToDate), outputs evaluated, deleted.
