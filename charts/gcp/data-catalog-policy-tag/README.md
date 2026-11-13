# data-catalog-policy-tag

A Data Catalog taxonomy with its policy tags and their IAM, as Config
Connector objects. A port of Cloud Foundation Fabric's
[`modules/data-catalog-policy-tag`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/f706bc3b6166787df01402f73a96f1de57097477/modules/data-catalog-policy-tag)
at v60.0.0 (`f706bc3b`), Apache-2.0, Copyright Google LLC. Bundt Package
`gcp-data-catalog-policy-tag` (`package.yaml`). Checked against Config
Connector v1.160.0.

## Example

```yaml
project_id: my-project
location: eu
name: my-datacatalog-policy-tags
tags:
  low: {}
  medium: {}
  high: {}
```

renders the `DataCatalogTaxonomy` `my-datacatalog-policy-tags` and three
`DataCatalogPolicyTag`s (`tests/golden/basic.yaml`).

## Values

The module's variables, with the same names, types and defaults.

| Variable | Renders |
| --- | --- |
| `names.taxonomy` | not a fabric variable: the taxonomy's display name in full, used as given (no `namePrefix`; at most 200 characters) (`docs/design.md`, "Names, labels and tags"). The cloud assigns the taxonomy's ID |
| `namePrefix` | not a fabric variable: an optional convenience; when set, the taxonomy's display name is `<namePrefix>-<name>`; empty changes nothing |
| `labels` | not a fabric variable: Kubernetes labels on every object; taxonomies and policy tags take no Google Cloud labels |
| `project_id`, `location` | the taxonomy's `projectRef` and `region`, and the project annotation of every object |
| `name`, `description`, `activated_policy_types` | the taxonomy's `displayName`, `description` and `activatedPolicyTypes` |
| `tags` | fabric's own variable (not cloud labels): a `DataCatalogPolicyTag` each, its display name the key and its description fabric's (`<key> - Terraform managed.` unless set); each tag's `iam` and `iam_bindings` an `IAMPartialPolicy` on it, its `iam_bindings_additive` an `IAMPolicyMember` each |
| `iam`, `iam_by_principals`, `iam_bindings` | one `IAMPartialPolicy` on the taxonomy (`docs/design.md`, "IAM": the listed members are kept, others are left alone; `IAMBinding` does not take Data Catalog kinds, so `iam_bindings` are bindings of it) |
| `iam_bindings_additive` | one `IAMPolicyMember` each on the taxonomy |
| `factories_config` | accepted and ignored: a chart cannot read the caller's files |
| `factories_data.taxonomy` | not a fabric variable: the taxonomy file's content, merged as fabric merges it (its description replaces `description`, its tags join `tags` and win a shared key, its IAM joins the taxonomy's) |
| `deletion_policy` | not a fabric variable; `ABANDON` keeps the taxonomy and its tags |

Refused (`upstream.yaml`):

- `context`: Bundt's `${...}` expressions and `valueFrom` replace fabric's
  `$context` lookups (by design).
- `factories_config`, in part: a chart cannot read the caller's files, so
  their contents go under `factories_data.taxonomy` (by design).

## Outputs

| Output | Value |
| --- | --- |
| `id` | the taxonomy's full resource name, from its live status (the cloud assigns its ID) |
| `tags` | `{TAG: the policy tag's full resource name}`, from their live status |

## From Terraform

A `module "x" { source = ".../modules/data-catalog-policy-tag" ... }`
block's arguments become the values unchanged
(`examples/data-catalog-policy-tag/`); a taxonomy factory file's content
goes under `factories_data.taxonomy`. fabric's IAM bindings are
authoritative per role; here they are an `IAMPartialPolicy`, so members
added by hand stay. To adopt an existing taxonomy, its ID (assigned by the
cloud) must be set as the object's `resourceID`, which this chart does not
take: deleting the Terraform-managed taxonomy and letting the chart create
one gives new IDs, so tags already attached to BigQuery columns must be
reattached.

## Upstream

Ported from Cloud Foundation Fabric's
[`modules/data-catalog-policy-tag`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/data-catalog-policy-tag)
at v60.0.0 (`f706bc3b`, Apache-2.0). [`upstream.yaml`](upstream.yaml) records
the repository, path, release, commit, licence and the date last synced, and
the module is listed in [`upstream/modules.yaml`](../../../upstream/modules.yaml)
with every other module the catalog tracks. To take a newer release, see
[`UPSTREAM.md`](../../../UPSTREAM.md), "Moving the pins".

## Tests

`task test CHART=data-catalog-policy-tag`: render cases `basic`, `full`,
`factory` and `names`, each validated against Config Connector v1.160.0's
CRD schemas, and the refusals in `tests/*.fail.yaml`.

No fake-cloud case: the fake cloud does not serve the Data Catalog API (a
run on 2026-11-12, with the `datacatalog` CRDs installed, failed with
`Error creating Taxonomy: googleapi: Error 404: Not Found`), so this chart
is render-tested only.

Not applied live: neither live-test service account has a Data Catalog
role.

## Changes

- **0.1.0** (2026-11-12): the port.
