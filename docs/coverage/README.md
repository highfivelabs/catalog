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
| `blocked-kinds.md` | the Config Connector kinds the blocked Google Cloud modules lack, ranked by how many modules each would unblock (for config-connector-extensions) |
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
| `gap` | Config Connector (on AWS: ACK or ack-extensions; on Azure: Azure Service Operator or aso-extensions) has no kind or field for it, or none a chart can wire in one render (a field that takes another resource's ID with no reference field) |
| `alpha` | only a `v1alpha1` kind exists, or it needs `allow_alpha: true` (on AWS: only an ack-extensions kind or a preview controller's) |
| `not-ported` | Config Connector (on AWS: ACK; on Azure: ASO or aso-extensions) has a stable kind; the chart does not map it yet |
| `by-design` | Bundt replaces it (`$context` lookups, reusing a resource, `factories_config`) |
| `no-chart` | the module has no chart yet |

**Additions.** A chart's values can include more than the module's
variables: `names`, `namePrefix`, `labels` and `tags` (every chart: whole
cloud names, the optional prefix, Kubernetes labels and cloud labels;
`docs/design.md`, "Names, labels and tags"), `allow_alpha`,
`deletion_policy`. They are not Terraform variables, so they are never
counted as missing or covered; the module's `notes` list them ("adds ..."),
and the generator fails for a chart that lacks any of the first four. A
module whose own variable has one of these names (fabric's `labels`, the
project module's `tags`) keeps it, with the catalog's meaning, and is not
listed as adding it.

**Outputs.** A chart covers an output when its Package (`package.yaml`)
declares an output of that name. The charts follow the decision that
outputs are selective, so they do not provide fabric's whole-object
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
| `extensions` | a kind config-connector-extensions provides at the commit `UPSTREAM.md` pins ("Gap kinds commit"), for a type Config Connector has no kind for or only an alpha one; `kind` names its group and version (`v1alpha1` ones need `allow_alpha`). `task inventory` reads that commit's CRDs, the Terraform types its generated kinds port and its IAM resource table |
| `none` | no kind |
| `unclassified` | an AWS or Azure module with a type not listed in `upstream/aws-kinds.yaml` (or `azure-kinds.yaml`): its types are not mapped to kinds yet, so its `resource_types_with_stable_kind` and `resource_types_missing` are empty |

AWS types are classified by `upstream/aws-kinds.yaml`, kept by hand from
`docs/aws.md`: `stable` is a kind of a GA (v1.x) ACK controller or a field
of one (ACK puts many Terraform side resources inline), `extensions` an
ack-extensions kind, `alpha` a preview (v0.x) controller's kind, `none` no
kind. A module is classified only when the file lists every one of its
types.

`resource_types_missing` is the types without a stable kind (`alpha`,
`extensions` and `none`).

**Status.**

| Status | Rule |
| --- | --- |
| `ported` | a chart exists and refuses nothing |
| `partial` | a chart exists and refuses some variables, or accepts some only in part |
| `blocked` | no chart, and at least one resource type has no stable kind |
| `not started` | no chart, and every resource type has a stable kind (or the kinds are not classified yet: most AWS and Azure modules) |

So `blocked` is strict: a module whose only gap is one alpha side resource is
blocked, though the pilot charts show such a module can be ported with the
gap refused. The `notes` column names the types.

## Factories without a chart

Two Google Cloud modules are composite factories: they read a tree of
YAML files and call other modules once per file. `docs/design.md`
("Submodules and factories", "Factories, worked") decides they are not one
chart: Bundt renders from inputs alone, a Template has no loops, and one
chart making fifty projects would be one component, one plan line and one
blast radius. A generator that writes one Instance per file of the tree,
from the charts below, is accepted in principle and not built. Their rows
stay `not started` or `blocked` and are not ported:

| Module | What it composes | Its own resource types | Judged |
| --- | --- | --- | --- |
| `net-vpc-factory` | `net-vpc` and `net-vpc-firewall`, per file | none | a factory wrapper: every resource it makes belongs to `net-vpc` or `net-vpc-firewall`, which have charts. A chart would add no variable or resource the catalog lacks |
| `project-factory` (2026-11-12) | `project` (and its IAM), `folder` (four levels, and their IAM), `gcs`, `iam-service-account`, `bigquery-dataset`, `billing-account` (budgets), `data-catalog-policy-tag`, `dataplex-aspect-types`, `kms`, `logging-bucket`, `pubsub` | `google_network_security_dns_threat_detector` (config-connector-extensions' `NetworkSecurityDNSThreatDetector`) and two `terraform_data` preconditions | a factory wrapper, like `net-vpc-factory`. Its eight variables (`folders`, `projects`, `data_defaults`, `data_merges`, `data_overrides`, `factories_config`, `context`, `notification_channels`) are the tree and its defaults, whose values are the composed modules' variables: a chart would re-expose those charts' values under one object per project and add no coverage of its own. The one resource it makes itself, a project's DNS threat detector, is a candidate for the `project` chart (a `dns_threat_detector` value, as the factory's file has it) rather than a reason for a factory chart. Its row stays `blocked` on that kind |

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
