# Migrating from Terraform

What it looks like to move a Terraform module call to the catalog: the
variable names and shapes stay as they are, so the conversion is mechanical,
and what cannot be carried is named, not dropped. Today four fabric modules
have charts (`gcs`, `iam-service-account`, `net-vpc`, `project`; the last is
partial). `docs/coverage` says how much of every other module there is.

## The mapping

| Terraform | Bundt |
| --- | --- |
| a `module "x" { source = ...//modules/gcs?ref=v60.0.0 }` block | a component `x` of a **Template**, naming the Package `gcp-gcs` at the chart's version |
| arguments that are literals | the component's `inputs`, in the Template |
| arguments that read `var.*` (or a local that does), with the values from `terraform.tfvars` | the **Instance**'s `spec.components.x.values`: what differs per environment |
| `module.a.some_output` in another module's argument | the expression `${components.a.outputs.some_output}`, which also orders the components |
| `depends_on = [module.a]` | `dependsOn: [a]` on the Template component |
| `count`, `for_each` | no loop in a Template: one component or one Instance per item (a Package's job, or a generator: `docs/design.md`, "Factories, worked") |
| `providers = {...}` | none: the Environment's Target supplies the cloud account |
| `$context:` lookups, `var.context` | `${...}` expressions and `valueFrom` |
| the module's `prefix` (fabric), `name_prefix` (AWS) | the same variable, with the same meaning: `prefix` stays `prefix` and is never turned into `namePrefix` |
| nothing: a second copy of the root module in the same project asks for the same names | `namePrefix: ${instance.name}` on each component (below) |

The variable names, types and defaults are the module's (`values.yaml` and
`values.schema.json` of each chart). A variable the chart cannot carry is
still in its values and refused when set, with a message that names the gap
(`docs/design.md`, "What Config Connector cannot express is refused, by
name").

## `catalogtool convert`

```sh
task convert -- examples/gcs/main.tf --tfvars examples/gcs/terraform.tfvars
task convert -- examples/gcs/main.tf --tfvars examples/gcs/terraform.tfvars --plan   # also renders the charts
task convert -- prod.tfvars --chart gcs                                              # a tfvars file as one chart's values
```

It reads the module blocks of a Terraform file (with its `variable` and
`locals` blocks, and tfvars files for `var.*`), finds the chart for each
`source` (fabric's `modules/<name>`, from a git URL or a local copy), and
writes a Template, a Stack and an Instance to stdout. The Template is named
for the file's directory (`--name`), the Stack's team and the Instance's
environment are placeholders (`--team`, `--env`). It validates the effective
values (the chart's defaults, the inputs, the Instance's values) against the
chart's `values.schema.json`, and writes to stderr one line for each thing
it could not carry, then exits 3:

```text
gap: module.archive.rpo: refused by the chart (gap): StorageBucket has no rpo field (Config Connector PR #13713)
gap: module.archive.managed_folders: needs an alpha Config Connector kind: add allow_alpha: true ...
gap: module.scratch.count: Bundt components are not looped: make one component (or one Instance) for each item ...
gap: module.logs: gcp/logging-bucket (v60.0.0) has no chart yet: ...
note: module.archive: the source pins v59.0.0; the chart was ported from v60.0.0 ...
```

`gap` is something that was not carried (or that the chart will refuse),
`invalid` is a value that breaks the chart's schema, `note` is carried but
worth knowing. What a refused variable's `kind` means (gap, alpha,
not-ported, by-design) is in `docs/coverage/README.md`; the refusals are in
each chart's `upstream.yaml`.

`--name-prefix '${instance.name}'` adds `namePrefix: ${instance.name}` to the
inputs of every component whose chart takes one (all of them), so that two
Instances of the Template in one project get distinct cloud names.

What it does not do: evaluate Terraform. It evaluates the expressions it can
(literals, `var`, `local`, `module.*` outputs and the common functions:
`merge`, `format`, `join`, `lookup`, ...), and says so for the rest
(resources, data sources, `path.*`, `count.index`). An argument whose
expression it cannot resolve is left out, with a message, not guessed.
The `project` chart has no `values.schema.json` yet, so only its variable
names are checked.

## The examples

Each directory under `examples/` holds a Terraform module call as a team has
it (after the module's own README example, pinned to `v60.0.0`), and what is
made from it. `task examples-test` regenerates and checks them; the
converter's output for each is a Go test (`task tools-test`).

| Example | Shows |
| --- | --- |
| `examples/gcs` | a bucket with IAM and a lifecycle rule; `var.*` arguments become the Instance's values |
| `examples/iam-service-account` | a service account with IAM on it and roles granted on the project; a map key built from `var.project_id` |
| `examples/net-vpc` | subnets with secondary ranges, a route, Shared VPC host and service projects |
| `examples/project` | a project with services, IAM and an organization policy (the chart is partial) |
| `examples/wiring` | `module.reader.iam_email` becomes `${components.reader.outputs.iam_email}` |
| `examples/names` | `namePrefix: ${instance.name}` on three components (a network, a service account, a bucket) and the plans of two Instances (`plan.txt`, `plan-prod.txt`) with distinct cloud names |
| `examples/gaps` | arguments the charts refuse, a variable with no value, `count`, a module with no chart |

In each: `main.tf` and `terraform.tfvars` (the Terraform), `bundt.yaml` (the
Template, Stack and Instance), `messages.txt` (what the converter said, when
it said anything), `plan.txt` (the plan preview) and `rendered.yaml` (the
Config Connector objects the charts render, validated with `kubeconform
-strict` against Config Connector v1.160.0).

**Read `plan.txt` for what it is.** It lists what Bundt's plan holds for
those documents: a `create` for each document and live component
(`specs/record/plans.md` R2), with the Config Connector objects each
component's chart renders under it, and a blocking finding where the chart
refuses a value. It is written by the converter from the real renders; it is
not captured from a running Bundt, and it has no diffs. Expressions such as
`${components.reader.outputs.iam_email}` are shown as written: Bundt
resolves them when the component they name is ready.

## Unique names: `namePrefix`

Terraform names come from the module's `name` and `prefix`; two copies of a
root module in one project meet at the cloud as a 409. Every chart has an
optional `namePrefix` (not a Terraform variable): when set, the cloud names
the chart gives start with `<namePrefix>-`, in front of the module's own
`prefix`. A Template passes `namePrefix: ${instance.name}` to each component
(Bundt's expression context has `instance.name`), and two Instances of one
Stack in one project stay apart. Empty, which is the default and what a
converted module call has, nothing changes: the names are the module's, which
is what adopting an existing resource needs (below). Set it for new
environments, not for resources Terraform already made.
`docs/design.md`, "namePrefix", has the rules and the limits.

## Adopting resources that already exist

The goal is the first plan being empty of changes to the cloud: the objects
take over what Terraform made, and nothing is modified or deleted. What is
verified (from Google's Config Connector documentation, read on 2026-11-09)
and what is not:

**Verified.**

- Config Connector acquires a resource that already exists: "If a resource
  with the same name already exists, Config Connector acquires that resource
  and starts managing it"
  ([Managing and deleting resources](https://docs.cloud.google.com/config-connector/docs/how-to/managing-deleting-resources)).
  The name is the cloud resource's, which the charts set from `spec.resourceID`
  (the bucket `test-my-bucket`, the network, the service account ID), built
  from the same `prefix` and `name` the module used. So give the component
  the module's own `name`, `prefix` and `project_id` and the objects
  `rendered.yaml` shows name the existing resources.
- `spec.resourceID` is for acquisition: the release notes say to find it from
  the last part of `status.externalRef` or with gcloud, and to leave it unset
  when creating a new resource. (The charts set it always, to the name the
  module computes.)
- Deleting a Config Connector object deletes the cloud resource by default;
  the annotation `cnrm.cloud.google.com/deletion-policy: abandon` before the
  delete keeps it. A chart's `deletion_policy: ABANDON` renders that
  annotation on its cloud resources (`docs/design.md`, "Deletion").
- The `cnrm.cloud.google.com/state-into-spec` annotation decides whether
  Config Connector writes the live values of fields you did not set into the
  object's `spec`. It is immutable; `absent` is the default for new resources
  since Config Connector 1.123.1
  ([Ignore unspecified fields](https://docs.cloud.google.com/config-connector/docs/concepts/ignore-unspecified-fields)).
  The charts do not set it, so a cluster at 1.123.1 or later gets `absent`.

**Not verified here; try it on a copy first.**

- Whether the first reconcile leaves an acquired resource's fields that the
  chart does not set alone. A manifest that differs from the live resource
  is applied as an update, and a field Config Connector has no field for
  cannot be preserved: a StorageBucket acquisition has been reported to
  remove the bucket's encryption-enforcement restriction mode
  ([k8s-config-connector #14236](https://github.com/GoogleCloudPlatform/k8s-config-connector/issues/14236);
  open when read, not reproduced). The catalog's defaults are fabric's so
  that what the module sets stays set (`docs/design.md`, "From Terraform"),
  but nothing here has been run against an existing, Terraform-made
  resource. The pilot's live runs created and deleted their own.
- Immutable fields: if the chart's value differs from the existing
  resource's, the update fails. Config Connector's troubleshooting guide says
  to compare `gcloud ... describe` with the YAML and correct the mismatch.
- That authoritative IAM adopts quietly: `iam` becomes an `IAMPartialPolicy`,
  which keeps its members and no longer removes others (the one place
  behaviour differs from fabric, `docs/design.md`, "IAM").

**The order that follows.**

1. **Plan in Terraform.** `terraform plan` should be empty: you are adopting
   the state Terraform believes in.
2. **Convert** the module call (`task convert`), resolve every `gap`, and
   keep the module's `name`, `prefix` and `project_id`, and leave `namePrefix`
   empty: a prefix would name new resources.
3. **Protect the resources first.** Set `deletion_policy: ABANDON` in the
   component's inputs (and `cloudResources: keep` on the Instance's component,
   `specs/record/instances.md` R36), so that backing out later cannot delete
   what Terraform made.
4. **Plan and read it.** The plan lists the objects to create; render them
   (`rendered.yaml`) and compare each with `gcloud ... describe` for the
   fields that matter (labels, locations, versioning, lifecycle, encryption,
   IAM).
5. **Take Terraform's hands off before Bundt's apply, not after.** Both
   managing one resource at once means two controllers writing it. Remove the
   module from Terraform's state without destroying anything:
   `terraform state rm 'module.bucket'` (a documented command that edits the
   state only; the resources stay). Then delete the module block. Terraform's
   `removed` block with `lifecycle { destroy = false }` does the same through
   code review; this page has not verified it.
6. **Approve the Bundt plan.** Config Connector acquires each resource. Check
   the objects become Ready and `terraform plan` of the rest of the stack
   still shows nothing for them.
7. **Remove `ABANDON`** in a later plan, once you are content that Bundt
   should be able to delete the resources, as the rest of the catalog does.

What to do with the Terraform state afterwards: nothing but the `state rm`
above; the state file keeps describing the rest of the stack. If a module
used a remote state that other stacks read through `terraform_remote_state`,
those outputs go away with it: take them from the component's outputs, or
write them as values.
