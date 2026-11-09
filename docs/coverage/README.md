# Coverage against the open-source modules

How much of the Terraform modules that teams use today the catalog carries.
`task coverage` writes everything here and the coverage section of the root
`README.md`; `task coverage-check` fails when the committed files are out of
date. Nothing here is edited by hand except this page.

| File | Holds |
| --- | --- |
| `modules.csv` | one row per tracked module: `cloud,module,upstream_url,pinned_version,chart,status,variables_total,variables_covered,outputs_total,outputs_covered,resource_types_total,resource_types_with_stable_kind,resource_types_missing,pct_variables,pct_outputs,notes` |
| `variables.csv` | one row per variable of every tracked module: `cloud,module,variable,type,covered,refused_reason,gap_kind` |
| `outputs.csv` | one row per output: `cloud,module,output,covered` |
| `resource-types.csv` | one row per Terraform resource type each module creates, with its class: `cloud,module,resource_type,class,kind` |
| `gcp-resource-kinds.csv` | the Google Cloud classification the inventory computes (`task inventory`); an input to this page |
| `total.svg`, `gcp.svg`, `aws.svg`, `azure.svg`, `bars/*.svg` | the bars in the README |

## What is compared

Every module in [`upstream/modules.yaml`](../../upstream/modules.yaml), at
the release it is pinned to: all 91 Cloud Foundation Fabric modules, the 40
most-downloaded terraform-aws-modules and the 37 most-downloaded Azure
Verified Modules. The generator downloads each repository's tarball at the
pinned tag (a GET, once, cached in `.cache/upstream`) and parses the
module's `.tf` files with HashiCorp's HCL parser (`tools/tfmod`).

## How it counts

**Variables.** A module's variables are the `variable` blocks in the `.tf`
files of its root directory (fabric splits them over `variables-*.tf`).
**A variable is one unit, however many attributes its object type has.**
`project`'s `shared_vpc_service_config` is one variable, although it is an
object of six attributes of which four are refused; `lifecycle_rules` is
one, although each rule is an object of two nested objects. This keeps the
count checkable from the module's `variables.tf`, but it means a covered
variable can still refuse some of its fields. Such a variable is `partial`
in `variables.csv` (its `refused_reason` says which fields), counts as
covered, and is tallied in the module's `notes`. The `type` column shows the
declared type with an object's attribute names (first six) so a reader sees
how big the unit is.

**Covered.** A chart covers a variable unless its `upstream.yaml` lists it
under `refused`. The chart keeps every module variable in `values.yaml`, so
tfvars convert one to one (`docs/design.md`, "What Config Connector cannot
express is refused, by name"), and refuses the ones it cannot carry with a
message that names the gap. Two checks keep the list honest: the generator
fails if a refused name is not a variable of the module at the pinned tag,
and `task coverage-verify` (part of `task test`) renders each chart with
every wholly refused variable set and checks the render stops with "is not
supported". A variable the chart does not list at all counts as not covered
(its schema refuses it). A module without a chart has no covered variables.

**`gap_kind`** says why a variable is not (fully) covered:

| `gap_kind` | Meaning |
| --- | --- |
| `gap` | Config Connector has no kind or field for it |
| `alpha` | only a `v1alpha1` kind exists, or it needs `allow_alpha: true` |
| `not-ported` | Config Connector has a stable kind; the chart does not map it yet |
| `by-design` | Bundt replaces it (`$context` lookups, reusing a resource, `factories_config`) |
| `no-chart` | the module has no chart yet |

**Additions.** A chart's values can include more than the module's
variables: `namePrefix` (every chart: Bundt's uniqueness prefix,
`docs/design.md`, "namePrefix"), `allow_alpha`, `deletion_policy`. They are
not Terraform variables, so they are never counted as missing or covered; the
module's `notes` list them ("adds ..."), and the generator fails for a chart
that lacks `namePrefix`.

**Outputs.** A chart covers an output when its Package (`package.yaml`)
declares an output of that name. The charts follow the builder's decision
that outputs are selective, so they do not provide fabric's whole-object
outputs (`bucket`, `network`, ...).

**Resource types.** The distinct resource types the module creates,
without Terraform helpers (`random_*`, `tls_*`, `terraform_data`,
`time_sleep`, ...) and, for Azure, the usage telemetry. For Azure modules
that declare raw ARM resources, an `azapi_resource` is named by its
literal ARM type (`azapi_resource:Microsoft.Network/virtualNetworks`).
For fabric modules the types come from the inventory (all `.tf` files below
the module, submodules included), classified against Config Connector
v1.160.0:

| `class` | Meaning |
| --- | --- |
| `stable` | a `v1beta1` Config Connector kind |
| `alpha` | only a `v1alpha1` kind |
| `extensions` | a gap kind that config-connector-extensions provides |
| `none` | no kind |
| `unclassified` | AWS and Azure types are not mapped to ACK and ASO kinds yet (`docs/aws.md` and `docs/azure.md` do it by hand for the top modules), so their `resource_types_with_stable_kind` and `resource_types_missing` are empty |

`resource_types_missing` is the types without a stable kind (`alpha`,
`extensions` and `none`).

**Status.**

| Status | Rule |
| --- | --- |
| `ported` | a chart exists and refuses nothing |
| `partial` | a chart exists and refuses some variables, or accepts some only in part |
| `blocked` | no chart, and at least one resource type has no stable kind |
| `not started` | no chart, and every resource type has a stable kind (or the kinds are not classified yet: all AWS and Azure modules) |

So `blocked` is strict: a module whose only gap is one alpha side resource is
blocked, though the pilot charts show such a module can be ported with the
gap refused. The `notes` column names the types.

## Limits

- AWS and Azure modules are tracked at their repository root: variables and
  outputs are the root module's. A few modules are only their submodules
  (`iam`, `cloudwatch`): their root declares nothing, and their rows say so.
  Their resource types include the submodules'.
- Percentages are of variables, not of behaviour. A covered variable may
  still render fewer objects than the module creates; the charts' READMEs
  list what each one renders and refuses.
- The generator reads what the pins say. It does not know about changes
  upstream since then: `docs/upstream-status.md` will.
