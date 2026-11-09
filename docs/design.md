# The Google Cloud catalog: design

Draft, 2026-11-09, for the builder. How Bundt's seed catalog of Packages
for Google Cloud is modelled, and the pilot that tests the model. The goal
is the builder's: "make the transition from tf for teams much simpler",
starting from the foundational layers of Cloud Foundation Fabric.

Read with: Bundt's `specs/catalog/packages.md` and `templates.md` (what a
Package and a Template are), `drafts/agreed/README.md` (providers, the
escape hatch), `drafts/delivery/README.md` (hooks, CRDs, the dependency
graph), `drafts/capabilities/README.md`; `docs/gcp-inventory.md` here
(every fabric module against Config Connector).

## Decisions

The builder's answers of 2026-11-09, applied in the sections below.

1. **Naming and shape.** `gcp-<module>` is the Package name. Follow
   fabric's own module naming closely, and its pattern: one core resource
   per module, with auxiliary and related resources (IAM, attachments)
   around it. "That's the same pattern we should follow here, and one that
   works well for composition." So a chart is named for its module, its
   core object is the first thing it renders (`bucket`, `network`,
   `project`, `service_account`), and everything else hangs off it. A new
   catalog entry is a module-shaped thing, not a stack of unrelated
   resources; what spans modules is a Template.
2. **Outputs are selective, as Terraform's are.** "We should strive to be
   more selective about what we output, similar to how Terraform does it."
   A Package outputs fabric's declared outputs and nothing more, never a
   whole object. Binding every rendered object as `resources.<id>`,
   whatever its kind, is only the mechanism that lets CEL select them:
   "By object of any type, and we can select them. That's even better."
   The component's values are bound too, as `inputs`.
3. **Alpha kinds only behind an opt-in value per chart** (`allow_alpha`).
   **Beta kinds are on by default.**
4. **Factories**: the generator is accepted in principle, and the builder
   wants to see it first: "I'd want to know what that looks like a little
   bit better." The worked example is in "Factories, worked". It is not
   built.
5. **Authoritative IAM**: the kind is `IAMRoleBinding`, being built in
   config-connector-extensions. The builder prefers non-authoritative IAM,
   so the additive `IAMPolicyMember` stays the default, `IAMPartialPolicy`
   serves the authoritative variables as designed, and `IAMRoleBinding`
   is used only where fabric's `iam_bindings` need it (section "IAM").
6. **Live runs**: the service account
   `catalog-live-tests@hfl-dev-514205.iam.gserviceaccount.com` is approved
   and made (no keys). Rules in "Testing".
7. **Entry points are `task`** (Taskfile.yml), as in every repo: `task
   test`, `task test-live`, `task inventory`.
8. **Factory findings accepted** (after the worked example): the generator
   moves a project's grant to its own service account to the account's
   side, rewrites entries keyed by principals that are expressions into
   additive bindings, and writes folder IDs as literals for now.
   Cross-Instance references are a gap the builder has planned in Bundt.
9. **A test provisioner** is the pattern for live tests that need real
   folders, projects, policies or identities ("Testing", "The test
   provisioner"). The privileged principal it needs waits on a test
   folder, and the builder creates it.

## Summary

1. **One Helm chart per fabric module, one Package per chart.** The chart
   renders Config Connector objects. Its values are the module's
   Terraform variables (same names, types, defaults and validations, in
   `values.schema.json`), so a module block becomes a values file one to
   one. Its Package's outputs are the module's declared outputs and
   nothing more, selected by CEL from the live objects and the values.
2. **Nothing is dropped silently.** A variable Config Connector cannot
   express stays in the schema and stops the render with a message naming
   the gap.
3. **Helm by default; kro only for wiring that must happen at runtime
   inside one Package and that no Config Connector reference can carry.**
   None of the 91 modules needs it today (section "kro or Helm").
4. **IAM**: additive variables become `IAMPolicyMember`, authoritative
   ones `IAMPartialPolicy`, never `IAMPolicy`. Role-authoritative IAM is
   the largest gap, 43 modules (gap 1 in the inventory); the kind that
   closes it is `IAMRoleBinding`.
5. **References**: Config Connector references inside a chart, Bundt's
   `valueFrom` between charts.
6. **Deletion**: Config Connector's default (delete), as Bundt decided;
   `deletion_policy: ABANDON` keeps the resources.
7. **Organization and folder Packages run only where the platform team's
   identity does**, never in a team's namespace.
8. **Alpha kinds are opt-in per chart** (`allow_alpha`); beta kinds are
   on.
9. **Tests in three layers**: render (every change, offline), a fake cloud
   (an offload VM), a real project (pilot only, cleaned up).

The pilot ports iam-service-account, gcs, net-vpc and the core of
project, and proves render, the fake cloud and (for three of the four) a
real project ("Pilot").

## A Package per module

### The chart

`charts/gcp/<module>/`:

| File | Holds |
| --- | --- |
| `Chart.yaml` | name (the fabric module's), version (the chart's own semver), `appVersion: fabric-v60.0.0`, the source module and commit as `sources` and `hfl.dev/source*` annotations, `hfl.dev/config-connector` (the release it is checked against) |
| `values.yaml` | every Terraform variable of the module, with its default |
| `values.schema.json` | the variables' types, enums and required fields, and the module's `validation` blocks where JSON Schema can say them; `additionalProperties: false`, so a misspelt value is refused |
| `templates/*.yaml` | one file per fabric `.tf` file it ports, each naming its source file |
| `templates/_kcc.tpl` | the shared helpers (a copy of `lib/_kcc.tpl`) |
| `package.yaml` | the Bundt Package document: name, version, `engine: helm`, `providers: [kcc]`, outputs |
| `README.md` | what is ported, what is refused and why, outputs, and how to come from Terraform |
| `tests/` | render cases (`*.values.yaml` with golden files), refusals (`*.fail.yaml`), and the fake-cloud case (`mock.values.yaml`) |

### Values mirror the Terraform variables

Same names (snake_case, as Terraform has them, not Helm's camelCase), same
defaults, same validations. A team's `module "x" { ... }` arguments become
the component's inputs with no renaming, and a converter (HCL to YAML) is
all a migration needs. Defaults that reach the cloud stay fabric's, even
odd ones (`display_name: Terraform-managed.`), because a resource adopted
from Terraform must not change on its first apply ("From Terraform").

Validations that JSON Schema cannot express (across fields, on computed
names) are template checks that fail with fabric's message:
`iam-service-account` checks the account ID is 6 to 30 characters, `gcs`
that autoclass needs `STANDARD`, `net-vpc` that a subnet has a range.
Validation happens when Bundt renders, at plan time, so a bad value is a
blocking finding on the plan (packages.md R16), never a failed apply.

### What Config Connector cannot express is refused, by name

Each module variable with no Config Connector field or kind is still in
the schema, defaulting to empty, and `kcc.unsupported` stops the render
when it is set:

```text
gcs: rpo is not supported: StorageBucket has no rpo field (Config
Connector PR #13713) (docs/gcp-inventory.md, "Gaps")
```

So a team learns at plan time, on the plan, that one setting does not
carry over, rather than finding it missing in the cloud. When a Config
Connector release (or a config-connector-extensions kind) closes the gap,
the chart's next minor version maps it.

Three kinds of refusal, each saying which it is: a gap (no kind or field;
listed in the inventory), alpha (a `v1alpha1` kind; see "Alpha kinds"),
and "not ported yet" (Config Connector has it; the pilot did not map it).

### Alpha kinds

Beta (`v1beta1`) kinds are always on. A feature that needs a `v1alpha1`
kind, whose schema Config Connector may change between releases, is
refused until the component sets the chart's `allow_alpha: true`:

```text
net-vpc: network_attachments needs the alpha Config Connector kind
ComputeNetworkAttachment: set allow_alpha: true to accept that its schema
may change (docs/design.md, "Alpha kinds")
```

`allow_alpha` is a value of the chart, so a Template or an Instance sets
it per component, a Stack for a whole team's use, and a Policy (L3) can
forbid it per Environment. A chart has the value once it ports an alpha
kind: `net-vpc` (network attachments, PSA route exchange, peered DNS
domains) and `gcs` (managed folders) have it; `iam-service-account` and
`project` do not yet. An alpha feature is render-tested against the kind's
schema and not applied to a cloud until a fake-cloud or live case covers
it, which each chart's README says. An alpha kind not ported yet is
refused even with `allow_alpha`.

### Names

- **Kubernetes names** come from the component's name, which Bundt passes
  as the release name (packages.md R13), plus the item's key:
  `<component>-subnet-europe-west1-production`. When the key holds
  characters a name cannot (`roles/logging.logWriter`), or the name would
  pass 63 characters, it ends with 8 hex characters of the key's sha256,
  so two keys never collide and a name never changes between renders.
- **Cloud names** are fabric's (`<prefix>-<name>`), in `spec.resourceID`.
  Bundt's fixed L2 check that cloud names carry the Instance's name
  (drafts/agreed, "Policies") is met by the Template, which sets
  `name: "${instance.name}-data"`; the chart does not force it, so a
  standalone component can adopt an existing name.
- Kubernetes names are an interface: renaming an object deletes the old
  one and its cloud resource ("Versioning").

### Project, labels, scope

- `project_id` set: every object carries
  `cnrm.cloud.google.com/project-id`. Unset: Config Connector takes the
  namespace's annotation, which Bundt's kcc `namespaceSetup` Package sets
  from the Environment's `spec.cloud.gcp.project`. Templates should leave
  it unset or write `${environment.cloud.gcp.project}`.
- fabric's `labels` become `metadata.labels`; Config Connector copies
  unprefixed labels to the cloud resource and skips prefixed ones, so
  Bundt's `hfl.dev/*` and ApplySet labels never reach the cloud.
- Every object carries `hfl.dev/id` (below) and the standard
  `app.kubernetes.io/*` labels.

### Outputs

A Package's outputs are CEL over its rendered resources' live status
(packages.md R8). The binding is not specified yet; the charts assume this
one, and the pilot evaluates it (`tools/catalogtool outputs`):

- each rendered object whose annotation `hfl.dev/id` is set is bound as
  `resources.<id>` (or `resources["subnet:europe-west1/apps"]`), **whatever
  its kind**: CEL selects what an output needs from them;
- the component's values, the chart's defaults under the component's
  inputs, are bound as `inputs`;
- the CEL environment is the standard library plus `strings`, `lists` and
  two-variable comprehensions (`transformMapEntry`), which map outputs
  such as net-vpc's `subnet_ids` need.

**Outputs are selective, as Terraform's are** (decision 2). A Package
outputs fabric's declared outputs, for what the chart ports, and nothing
more; it never outputs a whole object, and an output is never added
because an object has the field. What another component's input takes is
an ID, a self link, an email, a URL. Where fabric's declared output is a
map of whole objects, the chart outputs the one field consumers take, and
says so (net-vpc's `subnets_proxy_only`, `subnets_psc` and
`subnets_private_nat` are self links). Outputs that are whole Terraform
objects (`gcs.bucket`, `iam-service-account.service_account`,
`net-vpc.network` and `subnets`) are not outputs.

| fabric output | Package output |
| --- | --- |
| `iam-service-account.email` | `resources.service_account.status.email` |
| `gcs.url` | `inputs.bucket_create ? resources.bucket.status.url : 'gs://' + <bucket name from inputs>` |
| `gcs.name`, `project.project_id`, `net-vpc.name` | computed from `inputs`, as fabric computes them |
| `net-vpc.subnet_ids` | `resources.transformMapEntry(k, v, v.kind == 'ComputeSubnetwork' && !has(v.spec.purpose), {k.substring(7): 'projects/' + … + v.spec.resourceID})` |
| `project.number` | `resources.project.status.number` |

Differences from Terraform:

- Fabric computes some outputs from inputs, so dependents need not wait
  (`email` is known before the account exists). Binding `inputs` gives the
  same for the outputs that are plain functions of inputs (a bucket's name,
  a project's ID); the rest are read from live objects, so a dependent
  waits until the producer is ready, which Bundt does anyway ("Dependents
  wait until ready", drafts/delivery).
- An output of an object the chart did not make (`bucket_create: false`,
  `vpc_reuse`) has no value unless inputs give it.
- A few outputs have no source: `net-vpc.network_id` and
  `net-vpc.internal_ipv6_range` (ComputeNetwork does not report them; field
  gaps).

## Submodules and factories

**Repeated sub-resources** (`for_each` over subnets, routes, bindings) are
`range` over the same maps and lists, keyed as fabric keys them
(`<region>/<name>`), so keys and outputs line up.

**A module's factory** reads YAML files from a folder named in
`factories_config` (net-vpc's subnets, project's org policies, firewall
rules). A chart cannot read the caller's files: Bundt renders from inputs
alone. The files become data under `factories_data`, one entry per file,
each exactly the file's content:

```yaml
factories_data:
  subnets:
    factory-subnet:            # was subnets/factory-subnet.yaml
      region: europe-west4
      ip_cidr_range: 10.128.0.0/24
```

The chart applies fabric's factory defaults (a subnet's name defaults to
its file name, private Google access to true). net-vpc does this in the
pilot. A converter turns the folder into this map; teams keep their files
and their format.

**Composite factories**, `project-factory` and `net-vpc-factory`, create
whole hierarchies (folders, then projects, each with service accounts,
buckets, budgets) from a tree of YAML files. They are not one chart. A
Bundt Template has no loops (templates.md A11: generating structure is a
Package's job), and one chart creating fifty projects is one component,
one plan line and one blast radius. The builder accepted, in principle, a
generator that reads the factory's YAML tree and writes Bundt documents,
one Instance per project, and wants to see what that looks like first:
"Factories, worked" below is a real factory file, the documents the
generator would write from it, and how an edit becomes a plan. The
generator is not built.

**Not Packages**: `cloud-config-container` (cloud-init text for VMs, a
helper not a resource) and `projects-data-source` (a read). The
`__experimental_deprecated` modules are left out.

## Factories, worked

**Input.** A real fabric project factory file: `data/projects/dev-ta-app0-be.yaml`
from `modules/project-factory/README.md` at v60.0.0 (`f706bc3b`), with
lines removed and none changed, and the factory's `defaults` and `context`
beside it (the factory's own variables, here with one value each):

```yaml
# data/projects/dev-ta-app0-be.yaml (fabric's example, lines removed)
billing_account: 012345-67890A-BCDEF0
labels:
 app: app-0
 team: team-a
parent: $folder_ids:team-a/app-0
iam_by_principals:
  $iam_principals:service_accounts/dev-ta-app0-be/app-0-be:
    - roles/storage.objectViewer
service_accounts:
  app-0-be:
    display_name: "Backend instances."
    # assign roles on this project projects
    iam_self_roles:
      - roles/logging.logWriter
      - roles/monitoring.metricWriter
    # assign roles on this service account
    iam:
      roles/iam.serviceAccountUser:
        - $iam_principals:service_accounts/_self_/app-0-fe
  app-0-fe:
    display_name: "Frontend instances."
    iam_self_roles:
      - roles/logging.logWriter
      - roles/monitoring.metricWriter
buckets:
  app-0-bucket-a:
    location: europe-west8
    iam:
      roles/storage.objectViewer:
        - $iam_principals:service_agents/_self_/compute
  app-0-bucket-b:
    location: europe-west8
    logging_config:
      log_bucket: $storage_buckets:log-bucket
      log_object_prefix: log-prefix
services:
  - compute.googleapis.com
  - container.googleapis.com
  - storage.googleapis.com
```

```yaml
# the factory's other inputs (the generator's config, one file)
defaults: {prefix: hfl}                 # fabric: bucket names start with it
context:                                # fabric's `context` variable, as is
  storage_buckets: {log-bucket: hfl-central-logs}
folders: data/folders                   # data/folders/team-a/app-0/.config.yaml makes the folder
```

**The generator** reads the tree and writes documents. What each element
becomes:

| fabric factory element | Bundt |
| --- | --- |
| a `projects/<file>.yaml` | a Stack `<file>` of the platform team and one Instance of it, in the platform Environment; the Stack lists its components inline (the escape hatch, drafts/agreed), since a Template cannot loop over a file's service accounts and buckets |
| the file's project keys (`parent`, `billing_account`, `labels`, `services`, `iam*`, `org_policies`, `contacts`, ...) | the inputs of the component `project` (`gcp-project`) |
| `service_accounts.<n>` | a component `sa-<n>` (`gcp-iam-service-account`); `iam_self_roles` becomes `iam_project_roles` on the project's ID |
| `buckets.<n>` | a component `bucket-<n>` (`gcp-gcs`), with the factory's `prefix` |
| `$iam_principals:service_accounts/<this project>/<sa>`, `.../_self_/<sa>` | `"${components.sa-<sa>.outputs.iam_email}"`: an expression on a component of the same Instance, which also orders them |
| `$iam_principals:service_agents/_self_/<agent>` | `"serviceAccount:service-${components.project.outputs.number}@<agent domain>"`, the domain from fabric's `service-agents.yaml` |
| `$folder_ids:`, `$project_ids:` of something this factory makes | a literal written by the generator, read from the Instance that made it (the folders go first, in their own Instance); Bundt expressions cannot read another Instance's outputs |
| any other `$context:` lookup | the literal from the factory's `context` |
| a project's `iam*` entry whose principal is one of its own service accounts | moved to that account's `iam_project_roles`: the account's component needs the project's ID, so the project's component cannot also need the account's email, a cycle Bundt blocks |
| `iam_by_principals` (a map keyed by principal) with another principal that is an expression | rewritten as `iam_bindings_additive` entries with the principal as a value: a map's keys are never evaluated (templates.md A23), so a key cannot hold `${...}` |
| a project's `deletion_policy` and the factory's defaults for it | `cloudResources: keep` on the Instance's `project` and bucket components (instances.md R36), else Bundt's default, delete |
| the file's path and Git commit | the annotation `hfl.dev/factory` on the Stack and the Instance |

**Output**: for that one file, two documents. The Stack (components cut
to three of its five, same shape):

```yaml
apiVersion: hfl.dev/v1
kind: Stack
metadata:
  name: dev-ta-app0-be
  scope: platform
  annotations: {hfl.dev/factory: "data/projects/dev-ta-app0-be.yaml@4f2a9c1"}
spec:
  components:                          # inline; this shape is an assumption
    - name: project
      package: {name: gcp-project, version: 0.1.0}
      inputs:
        name: dev-ta-app0-be
        parent: folders/3456789012     # $folder_ids:team-a/app-0, from the folders Instance
        billing_account: 012345-67890A-BCDEF0
        labels: {app: app-0, team: team-a}
        services: [compute.googleapis.com, container.googleapis.com, storage.googleapis.com]
    - name: sa-app-0-be
      package: {name: gcp-iam-service-account, version: 0.1.0}
      inputs:
        project_id: "${components.project.outputs.project_id}"
        name: app-0-be
        display_name: Backend instances.
        iam_project_roles:             # iam_self_roles, and the project's own iam_by_principals entry for this account
          dev-ta-app0-be: [roles/logging.logWriter, roles/monitoring.metricWriter, roles/storage.objectViewer]
        iam:
          roles/iam.serviceAccountUser: ["${components.sa-app-0-fe.outputs.iam_email}"]
    - name: bucket-app-0-bucket-a
      package: {name: gcp-gcs, version: 0.1.0}
      inputs:
        project_id: "${components.project.outputs.project_id}"
        prefix: hfl
        name: app-0-bucket-a
        location: europe-west8
        iam:
          roles/storage.objectViewer:
            - "serviceAccount:service-${components.project.outputs.number}@compute-system.iam.gserviceaccount.com"
    # sa-app-0-fe and bucket-app-0-bucket-b: the same way;
    # bucket-b has logging_config.log_bucket: hfl-central-logs, from `context`
```

and the Instance:

```yaml
apiVersion: hfl.dev/v1
kind: Instance
metadata:
  name: dev-ta-app0-be
  scope: platform/gcp-org              # an Environment whose Target runs Config Connector with organization roles
  annotations: {hfl.dev/factory: "data/projects/dev-ta-app0-be.yaml@4f2a9c1"}
spec:
  stack: dev-ta-app0-be                # an inline Stack has no Template version; how an Instance names it is open
  components:
    project: {cloudResources: keep}
    bucket-app-0-bucket-a: {cloudResources: keep}
    bucket-app-0-bucket-b: {cloudResources: keep}
```

That file makes a project, two service accounts and two buckets: five live
components, `dev-ta-app0-be-project`, `-sa-app-0-be`, `-sa-app-0-fe`,
`-bucket-app-0-bucket-a` and `-bucket-b`. Bundt orders them by the
expressions: `project` first, then (ready) the others, the service accounts
and buckets side by side except `sa-app-0-be` after `sa-app-0-fe`.

**How an edit becomes a plan.** The factory repository holds the tree.
CI runs the generator on every change to it and submits **one plan scoped
to the platform team's factory Team** (plans.md R28: a plan with a scope
deletes what the scope holds and the plan does not), so a file that
disappears is deleted. That needs a Team of its own, `gcp-factory`, which
holds nothing a person made by hand. Reviewers read the plan beside the
pull request; approving it applies it.

1. **Add `run.googleapis.com` to `services`.** The generator rewrites one
   Stack; the plan has one change, an `update` of `dev-ta-app0-be-project`
   (`inputs.services` gains an entry), whose rendered diff shows one new
   `Service` object, and a `no change` for every other live component of
   every project. Nothing else moves.
2. **Remove `app-0-bucket-b`.** The Stack no longer lists it: one `delete`
   of `dev-ta-app0-be-bucket-app-0-bucket-b`. With `cloudResources: keep`
   on it, the object leaves Bundt and the bucket stays in Google Cloud
   (Terraform's equivalent is `terraform state rm`). Without `keep` the
   bucket is deleted, and a bucket with objects makes the delete fail
   rather than lose them (`force_destroy` is false).
3. **Rename the service account `app-0-fe` to `app-0-front`.** Components
   are named for their keys, so the plan shows a `delete` and a `create`:
   the account is replaced and every binding naming the old one is gone
   until the new one is ready. This is Terraform's behaviour without a
   `moved` block; the generator cannot tell a rename from a delete and an
   add, and the plan says what it will do.
4. **Delete the file.** The Stack and Instance are absent: `delete` of the
   Instance and its five live components. The project and the buckets
   stay (`keep`); the service accounts go.
5. **A new project file** is a `create` of one Stack and one Instance and
   five components, ordered as above.
6. **Move a project to another folder** (`parent`): one `update` of
   `project`, whose diff is the `Project`'s `folderRef`; Config Connector
   moves the project.

What this shows and what it does not:

- It needs from Bundt: an inline Stack (L2, the escape hatch), outputs
  readable as `${components.<name>.outputs.<o>}` inside an Instance (the
  spec has them), `cloudResources: keep` per component (the spec has it),
  and a Team-scoped plan (the spec has it).
- The builder accepted the three findings of the example: a project's
  grant to its own service account moves to the account's side (the cycle
  otherwise); a principal that is an expression cannot be a map key, so
  those entries become additive bindings; and folder IDs are literal
  values for now.
- **Cross-Instance references are a known gap, and the builder has
  planned the fix in Bundt**: contracts, exports and bindings (L3 or
  sooner, `asks/parked.md` and `drafts/capabilities`, "Central services").
  When an Instance can export an output and another bind to it, the
  folders Instance exports `team-a/app-0`'s ID and the project reads it;
  the generator's literal folder IDs, and its two-pass order, go away.
- It needs a decision from the builder: whether one Instance per project is
  the unit (recommended: a project is what a team asks for, reviews and
  deletes), and whether the folders may be an Instance of their own, whose
  outputs the generator copies into projects as literals until then.
- The generator itself is small: a YAML reader, the table above, and a
  document writer. fabric's context lookups are its only hard part, and
  they are a table.
- Gaps it meets in the pilot charts: none for this file. A file using
  `shared_vpc_service_config.service_agent_iam`, `pam_entitlements`, a
  `kms` block or `tags` meets a refusal naming the gap, as a module block
  would.

## IAM

| fabric variable | Config Connector | Semantics |
| --- | --- | --- |
| `iam` `{ROLE: [MEMBERS]}`, `iam_by_principals` `{PRINCIPAL: [ROLES]}` (merged, as fabric merges them) | one `IAMPartialPolicy` per resource, a binding per role | fabric: authoritative per role, members added out of band are removed. Here: the listed members are kept; others are left alone; deleting the component removes only the listed members |
| `iam_bindings` `{KEY: {role, members, condition}}` | `IAMPartialPolicy` today; one `IAMRoleBinding` each once config-connector-extensions ships it (decision 5) | with `IAMRoleBinding`, exact, as fabric's: the role's members on the resource are the listed ones |
| `iam_bindings_additive` `{KEY: {member, role, condition}}`, `iam_by_principals_additive` | one `IAMPolicyMember` each | the same: additive |
| roles granted *to* a service account elsewhere (`iam_project_roles`, `iam_storage_bindings`, ...) | one `IAMPolicyMember` each, `memberFrom.serviceAccountRef` naming the chart's account | the same; the member is resolved by Config Connector, no email crosses the plan |
| IAM on a resource IAMPolicyMember cannot reference (regional secrets, managed folders, log views, 32 types) | none | a gap (inventory, gap 2) |

- **Never `IAMPolicy`.** It owns the whole policy: on a project it would
  remove every grant made elsewhere (Bundt's fixed L2 check refuses it on
  a project), on a bucket the legacy owner and reader bindings. It also
  must not be mixed with the other two kinds on one resource.
- **The authoritative gap.** `IAMPartialPolicy` is the closest kind, and
  differs in one way that matters for security: a member someone adds by
  hand to a role the chart manages stays. Gap 1 is `IAMRoleBinding` in
  config-connector-extensions (the builder's name: one role, with its
  condition, on one resource, its members exactly), which makes fabric's
  `iam_bindings` exact. The builder prefers non-authoritative IAM, so the
  default stays additive (`IAMPolicyMember`), `iam` and `iam_by_principals`
  stay `IAMPartialPolicy`, and `IAMRoleBinding` serves `iam_bindings`
  only, in each chart's next minor version after the kind ships; a chart
  README says which it uses.
- **Principals from other components** come through Bundt:
  `members: ["serviceAccount:${components.runtime.outputs.email}"]`, or
  the `iam_email` output through `valueFrom`. fabric's `$iam_principals:`
  context lookups become these expressions.
- **Conditions** are supported on both kinds and carried as fabric writes
  them.

## References between resources

| Where | How | Why |
| --- | --- | --- |
| inside a chart | Config Connector references by name: `networkRef: {name: <component>}`, `memberFrom.serviceAccountRef` | Config Connector resolves them at runtime and waits for the referenced object; nothing crosses the plan |
| between charts (components) | Bundt `valueFrom` / `${components.<c>.outputs.<o>}` into an input, which the chart renders as `xRef: {external: "<id or self link>"}` | the output is the producer's public contract, not its object names; Bundt sees the edge and orders the components (dependency graph); it works across namespaces and Targets |
| to something outside Bundt | the input takes fabric's form (ID, self link, email) and renders `external` | as Terraform did |

A chart never refers to another component's Kubernetes object by name:
that would tie it to the other chart's internals (a rename in a minor
version breaks it), keep both in one namespace, and hide the dependency
from Bundt's graph. The outputs each chart exposes are therefore the
forms other charts' inputs take: IDs, self links, emails.

Example: a Template `landing-zone-project` with `project`
(`gcp-project`), `vpc` (`gcp-net-vpc`, `project_id: {valueFrom:
{component: project, output: project_id}}`) and `logs` (`gcp-gcs`, the
same). Bundt applies `project` first, waits until it is ready, then the
other two side by side.

## Deletion

Bundt's rule (asks/L2-answers.md Q1): deleting an Instance deletes its
cloud resources, and keeping them is the opt-in. Config Connector's
default is the same.

- Every chart takes `deletion_policy` (fabric's variable where the module
  has one, added where it does not): `DELETE` (default) renders nothing;
  `ABANDON` annotates the chart's cloud resources
  `cnrm.cloud.google.com/deletion-policy: abandon`. As in fabric, it
  applies to the resources, not to IAM grants on them, which are removed.
- `PREVENT` (fabric, Terraform 6) has no Config Connector equivalent and
  is refused. Its uses: a project lien (`lien_reason`, ported), a
  resource's own deletion protection where the API has one (Cloud SQL's
  `deletion_protection`, a value in those charts), and, for the rest, an
  L3 Bundt Policy that blocks a plan deleting a kind or a labelled object.
- The cloud's own guards stay: a bucket with objects is not deleted
  unless `force_destroy` (the `force-destroy` annotation); KMS keys are
  never destroyed, only their versions; services stay enabled on delete
  (`disable_on_destroy: false`, fabric's default, as an annotation).
- Bundt prunes a deleted component's objects together. The fake-cloud run
  deletes every object of a chart at once, IAM with the resource it is
  on, and checks all are gone ("Pilot").

## Organization, folders and Config Connector's scope

Config Connector objects live in namespaces, and in namespaced mode each
namespace's controller acts as one Google service account
(`ConfigConnectorContext`). That account's roles bound what a component
in the namespace can do, and the target of each object comes from the
`project-id`, `folder-id` or `organization-id` annotation (on the object,
else the namespace).

- **Team namespaces** get a project-scoped account: their Environments
  name a project (`spec.cloud.gcp.project`), Bundt's kcc `namespaceSetup`
  binds the account. Project-level charts (gcs, net-vpc in a team's own
  project, iam-service-account) run there.
- **Organization and folder charts** (organization, folder,
  billing-account, vpc-sc, org-level logging, project creation) need
  organization or folder roles. They run only in a platform namespace
  whose account has them, in an Environment the platform team owns.
- Bundt can enforce this with capabilities (drafts/capabilities): the
  Package `requires` `hfl.dev/gcp-scope: organization`, and only the
  platform Environment's Target provides it; a plan placing it elsewhere
  is blocked. At L3 a Policy can make the same rule per team.
- **A new project** made in the platform namespace is then a team's
  Environment: the project chart outputs its ID, and a follow-up plan
  creates the Environment naming it, the way a cluster Package yields a
  Target (drafts/agreed, "Self-service clusters").
- Cross-project objects are allowed when the account may: net-vpc's Shared
  VPC service attachment acts on the host project, so the host's charts
  run where the account has the host project.

## kro or Helm

The builder: "Unsure if we need or want kro but it's worth considering."
kro (kubernetes-sigs/kro, v0.9.4, pre-1.0, `v1alpha1` API) turns a
ResourceGraphDefinition into a new CRD; its controller expands each
instance of that CRD into resources at runtime, wiring them with CEL
(`${bucket.status.url}`), with `readyWhen`, `includeWhen`, `forEach`
collections, and a status projected onto the instance.

What kro offers, measured against what Bundt already does:

| kro strength | In Bundt with Helm |
| --- | --- |
| **Runtime CEL wiring between resources** of one graph | Config Connector references already wire resources at runtime inside a chart (`networkRef`, `memberFrom`), and Bundt's `${components...}` wires between components after apply. What remains: a *string* field that needs another object's live value with no reference field. The pilot found three: a service account's tag binding (its unique ID), grants to a new project's service agents (its number), a bucket key from a KMS key handle |
| **Status aggregated into one object** | A Package's outputs are CEL over the live objects, kept in the Instance's status (packages.md R8) |
| **Readiness of the whole** (`readyWhen`) | Bundt reads each object's `Ready`; dependents wait until ready |
| **A cluster API** (`kubectl get landingzones`) | Not needed: Bundt is the API |
| **Continuous re-derivation** when a live value changes | Deliberately absent: what is approved is what the cluster gets |

What Helm keeps that kro would cost:

1. **The plan shows every object.** Bundt renders a Helm chart at plan
   time; the approver, and Policies at L3, see each Config Connector
   object and its diff. A kro Package's plan holds the RGD and an
   instance; the objects are made later, in the cluster, from values
   nobody approved as objects. For cloud resources, where a changed field
   can replace a database, that is the review that matters.
2. **No controller and no CRD per Package.** kro is one more provider on
   every Target. Each RGD creates a cluster-scoped CRD, so every Package
   version is a CRD change under Bundt's one-owner rule
   (drafts/delivery D5): two teams on one cluster cannot run two versions
   of a Package unless each version is its own kind.
3. **Offline tests.** `helm template` plus kubeconform checks every
   render against Config Connector's schemas with no cluster; kro's
   expansion needs its controller.
4. **Porting effort.** Fabric modules are full of merges, defaults,
   lookups and `dynamic` blocks. Go templates with Sprig take them almost
   line by line (the pilot); kro's CEL has no equivalent of many Sprig
   functions, and optional fields inside a resource need CEL's optional
   syntax throughout.
5. **Ubiquity.** Helm is what teams and Bundt (hooks, CRDs, L2.2)
   already use; kro is pre-1.0.

**Verdict.** Helm is the default engine for the whole catalog. Use kro for
a Package only when all three hold: (a) a field must take another
object's live value, (b) no Config Connector reference can carry it, and
(c) splitting the Package into two components wired by `valueFrom` would
leave the user with something worse than one Package. None of the 91
modules meets all three today: each runtime value found can be a
reference field (gap 8, proposed for config-connector-extensions, which
fixes Helm, kro and plain Config Connector users at once) or a split
component. Revisit at L2.4, when Bundt's kro engine arrives, with a
concrete Package that meets the test.

## Versioning and the OCI layout

- **One chart per module**, pushed with `helm push` to
  `<registry>/catalog/gcp/<module>` (the chart's name is the module's);
  the Package `gcp-<module>` names it by digest
  (`spec.source: {oci, digest}`, packages.md R11), with
  `spec.version` equal to the chart's version. The prefix keeps Google
  Cloud's `kms` apart from AWS's.
- **Semver, the chart's own**, not fabric's:
  - major: a values file that worked no longer renders the same objects
    (a value renamed, removed or retyped), a cloud resource would be
    replaced (its `resourceID` or an immutable field changes), or a
    Kubernetes object is renamed (Bundt prunes the old name: with
    `DELETE`, the cloud resource goes);
  - minor: new values (a gap closed), new outputs, new optional objects;
  - patch: fixes that change no object a released version renders.
- **Tracking fabric**: `appVersion: fabric-vX.Y.Z` and the source
  annotations name the port's origin; `UPSTREAM.md` holds the pins. A new
  fabric release is diffed per module (`git diff old..new --
  modules/<m>`) and ported change by change; a release that touches no
  ported module needs no chart release. Fabric releases every two to six
  weeks, a major version each time it breaks an interface (v56 to v60 in
  2026-05 to 2026-11); a
  scheduled job could open the diff as a task.
- **Tracking Config Connector**: `hfl.dev/config-connector` names the
  release the chart is validated against. The Package should `require`
  Config Connector at that version or later (capabilities: the outpost
  reports installed API groups and versions), and Bundt's provider
  compatibility check (drafts/agreed) runs the render against the
  Target's CRD schemas, as `hack/test.sh` does against v1.160.0's.
- Templates (a landing zone, a project baseline) pin Package versions, as
  every Template does.

## From Terraform

What a team does to move a fabric module to a Bundt component:

1. Convert the module block's arguments to the component's inputs
   (HCL to YAML; same names). Replace `$context:` lookups and references
   to other modules' outputs with `${...}` expressions or `valueFrom`.
2. Plan. Refusals name anything that does not carry over.
3. Adopt instead of recreate: Config Connector acquires an existing
   resource whose `resourceID` matches, so the chart, given the same
   names, takes over the bucket or network in place. Set
   `deletion_policy: ABANDON` for the first apply, then
   `terraform state rm` the module, then remove `ABANDON`.
4. Check the plan's diff is empty of changes to cloud fields; the defaults
   are fabric's for this reason.

Authoritative IAM is the one place behaviour changes (members added by
hand are no longer removed), until gap 1 is closed.

## Testing

Three layers. Only the first runs on a laptop. The entry points are
tasks (`task --list`).

1. **Render**, `task test`, every change, a few seconds: shared helper
   copies match; `helm lint`; the Package document matches the chart and
   every output compiles as CEL; each test case renders to its golden
   file; every render validates with `kubeconform -strict` against JSON
   schemas made from Config Connector v1.160.0's CRDs, every object closed
   (`additionalProperties: false`), so a misspelt or missing field fails;
   each `*.fail.yaml` is refused with its expected message.
2. **Fake cloud**, `task test-mock` (`hack/mock-apply.sh`), on an offload
   VM: the config-connector-extensions fake cloud (a kind cluster with
   Config Connector's CRDs; Config Connector's own manager on the host,
   every Google API answered by mockgcp). Each chart's `mock.values.yaml`
   is applied server-side; every object must become Ready; the Package's
   outputs are evaluated against the live objects and the values; every
   object is deleted at once and must be gone. Limits: mockgcp's coverage
   (no liens, no Shared VPC, no subnet IAM), no Config Connector webhooks
   (so the project annotation is explicit), no deletion defender (the
   script does its part), and Config Connector at
   config-connector-extensions' pin (ahead of v1.160.0). Alpha features
   are not in the fake-cloud cases.
3. **Live**, `task test-live` (`hack/live-apply.sh`), pilot only, after the
   fake cloud passes: an offload VM acting as
   `catalog-live-tests@hfl-dev-514205.iam.gserviceaccount.com` (no keys;
   the builder approved it, 2026-11-09). The rules, enforced by the
   script: project `hfl-dev-514205` only, and every `gcloud` call passes
   `--project`; tiny resources (a service account, a bucket, a network with
   one /28 subnet and a route; no VMs, no databases, nothing billed while
   idle); every name starts with a run ID (`cat-<month day hour
   minute>-<4 hex>`) and every object that takes labels carries
   `catalog-run`; the test deletes what it makes and then checks Google
   Cloud no longer has it; a sweeper runs before and after (this run's
   resources, then any `cat-` leftover more than two hours old); at the end
   it lists what is left in the project, and the VM deletes itself. The
   `project` chart's live run waits for a test folder that does not exist
   yet, and for the provisioner below.

### The test provisioner

Some charts cannot be tested with tiny resources in one fixed project:
`project`, `folder`, `organization`, `billing-account`, `vpc-sc`, Shared
VPC attachment, anything with an organization policy or a service agent.
They need a real folder, projects with billing, policies at folder scope,
identities. The builder approved the pattern (2026-11-09): "if there needs
to be some outer provisioner in all cases that creates everything it needs
to and manages everything it needs to for some given test, that's a
perfectly good pattern. And if there's a privilege principal needed for
that, we can create that."

An **outer provisioner** creates everything one test needs, owns it for the
test, and tears it down. The chart under test never creates its own
surroundings, and never runs with the privilege needed to.

- **Two principals.** The provisioner runs as a privileged principal,
  `catalog-provisioner`, whose roles are confined to the test folder
  (folder admin, project creator, billing user on the test billing
  account, org-policy admin at folder scope), never organization-level
  IAM. The chart runs as the low-privilege `catalog-live-tests`, which the
  provisioner grants roles on what it created, and only that. Neither
  principal exists beyond what is already made: the builder creates the
  provisioner's principal when the test folder exists, and nothing here
  creates a principal or touches organization IAM.
- **A test declares its needs** in `tests/live.needs.yaml`, a description,
  not a script:

  ```yaml
  # charts/gcp/project/tests/live.needs.yaml
  needs:
    folder: {}                              # a folder made for this run under the test folder
    projects:
      host: {services: [compute.googleapis.com]}
      service: {}                           # created with the test billing account, under the run's folder
    org_policies:
      folder: {compute.skipDefaultNetworkCreation: {enforce: true}}
    service_accounts: [runner]              # in the first project
  values: live.values.yaml                  # may read ${needs.folder.id}, ${needs.projects.host.id}, ${needs.service_accounts.runner.email}
  ```

- **The provisioner** (`hack/live-provision.sh up|down RUN`) reads it,
  creates each thing with the run ID in its name and `catalog-run` in its
  labels, writes `needs.json` (the IDs) to the run's folder in the offload
  bucket, and on `down` deletes everything labelled with the run, then
  sweeps older leftovers, as the live script's sweeper does. It is the only
  code that creates folders, projects or policies; a chart's test that
  needs one without declaring it fails. Later it can itself be a Bundt
  Template of catalog Packages (`gcp-folder`, `gcp-project`, ...), applied
  by the privileged principal, so the catalog is tested with itself.
- **Invoked from `task test-live`**, which already runs the render tests
  and the fake cloud first. A chart with a `live.needs.yaml` gets, in
  order, `provision up`, the chart's live apply as `catalog-live-tests`,
  and `provision down`, which always runs:

  ```yaml
  # Taskfile.yml (sketch)
  test-live:
    deps: [test, cce-snapshot]
    cmds:
      - for: {var: CHARTS_WITH_NEEDS}
        task: live-with-needs
        vars: {CHART: "{{.ITEM}}"}
      - task: live-simple          # charts that need nothing, as today
  live-with-needs:
    vars: {RUN: "cat-{{now | date \"010215 04\"}}-{{randAlphaNum 4 | lower}}"}
    cmds:
      - '{{.OFFLOAD}} run --sa {{.PROVISIONER_SA}} -- hack/live-provision.sh up {{.RUN}} charts/gcp/{{.CHART}}'
      - defer: '{{.OFFLOAD}} run --sa {{.PROVISIONER_SA}} -- hack/live-provision.sh down {{.RUN}}'
      - '{{.OFFLOAD}} run --sa {{.LIVE_SA}} -- env RUN={{.RUN}} NEEDS=gs://.../{{.RUN}}/needs.json hack/live-apply.sh {{.CHART}}'
  ```

  The two offload VMs are separate because a VM acts as one service
  account; the provisioner's VM does not run while the chart's does, and
  `defer` runs the teardown even when the chart's run fails.
- **Limits** the provisioner keeps: the test folder is the only parent;
  the test billing account carries a budget alert; resources are the
  cheapest that exercise the chart (a project costs nothing idle); a run
  that dies leaves labelled objects that the next run's sweeper removes;
  and `offload ls` plus a list of the test folder's contents are checked
  at the end of every run, as for the current live run.

Not covered yet: upgrades between chart versions (comparing two versions'
renders for replaced resources and renamed objects, which is the major
version test above), and Bundt itself (its kro, hooks and outputs land in
later levels).

## Pilot

Four charts (`UPSTREAM.md`, "What is ported"):

| Chart | Fabric module (size) | Ported | Refused (gap, alpha, not ported) |
| --- | --- | --- | --- |
| `iam-service-account` | M | all of it | reuse, tag bindings, context |
| `gcs` | L | all but the gaps; managed folders behind `allow_alpha` | object retention, hierarchical namespace, rpo, objects, managed folder IAM, KMS autokeys |
| `net-vpc` | L | network, every subnet kind, the subnet factory, subnet IAM, routes, googleapis routes, peering, Shared VPC host, DNS policy, PSA, the global firewall policy association; network attachments, PSA route exchange and peered DNS domains behind `allow_alpha` | BGP fields, internal ranges, policy-based routes, service connection policies (alpha, not ported yet), regional firewall policy associations |
| `project` | XL | the project (or a reused one), services, IAM, organization policies (with dry run), lien, essential contacts, Shared VPC service attachment and network users | about two thirds of the module (logging, tags, quotas, alerts, ...) not ported yet; metadata, default network tier, default service accounts (gaps) |

## Pilot results

**Render** (`hack/test.sh`, 2026-11-09, laptop): 57 of 57 checks pass:
14 render cases match their golden files and validate with
`kubeconform -strict` against Config Connector v1.160.0's CRD schemas,
17 refusals stop with their expected messages, and the four Package
documents match their charts with every output compiling.

**Fake cloud** (`hack/mock-apply.sh`, offload VM
`off-catalog-1109091250-20677`, e2-standard-8, catalog commit `54fb283`,
config-connector-extensions `1de95478`, Config Connector at its pin
`672414b8` against mockgcp, 2026-11-09): **26 of 26 objects Ready, every
chart's outputs evaluated against the live objects, and all 26 deleted
together**, as Bundt prunes a component.

| Chart | Objects Ready and deleted | Outputs evaluated |
| --- | --- | --- |
| `gcs` | 6 of 6: bucket, its IAM (partial policy and member), topic, topic IAM, notification | `name`, `id`, `url`, `notification`, `topic` |
| `iam-service-account` | 4 of 4: account, IAM on it, an additive member, a role granted on the project | `email`, `iam_email`, `id`, `name`, `unique_id` |
| `net-vpc` | 9 of 9: network, three subnets (one regular, one proxy-only, one from the factory), four routes (three googleapis, one by IP), DNS policy | network and subnet maps |
| `project` | 7 of 7: project, two services, IAM (partial policy and member), an organization policy, an essential contact | `project_id`, `id`, `name`, `number`, `services` |

The first fake-cloud run (offload VM `off-catalog-1109083144-22594`,
commit `c461e94`) found what the second fixed:

- IAM on an external project failed without the reference's
  `apiVersion` ("failed to load ServiceMapping for GroupVersionKind /,
  Kind=Project"); every external IAM reference now names it.
- Nothing deleted: the fake cloud runs Config Connector's manager but not
  its deletion defender, which a real install runs as its own pod, so
  `hack/mock-apply.sh` does the defender's part. Reported to
  config-connector-extensions, with its `up.sh` applying
  `config/crds/kustomization.yaml` (moved aside in the scratch copy).

Not provable in the fake cloud, and covered only by render tests: subnet
IAM (mockgcp does not implement a subnetwork's `getIamPolicy`), liens and
Shared VPC (mockgcp has neither).

**Live**: not run. It waits for the builder to approve a service account
for it (`hack/live-apply.sh` is written, not run).

## Questions

Answered by the builder on 2026-11-09 (see "Decisions"): the Package
names (`gcp-<module>`), selective outputs and the `resources` and `inputs`
binding, alpha kinds opt-in per chart, the factory generator in principle,
the name `IAMRoleBinding`, and the live account. Not answered (the
builder did not rule on them, so they stay recommendations); none blocks
the pilot:

1. **kro.** Recommended: Helm as the default engine, kro only by the test
   in "kro or Helm", and the runtime-value gaps closed as reference fields
   in config-connector-extensions instead.
2. **Where org-level Packages run.** Recommended: a capability
   (`hfl.dev/gcp-scope`) that only the platform team's Environment
   provides.
3. **The factory generator** (after the builder has seen "Factories,
   worked"):
   - one Instance per project, of an inline Stack, as the unit.
     Recommended yes: a project is what a team asks for, reviews and
     deletes.
   - an inline Stack's shape, and how an Instance names it (it has no
     Template version). Bundt's L2 escape hatch decides it; the example
     assumes `spec.components` as a Template has it.
   - folders in an Instance of their own whose outputs the generator
     copies into projects as literals. Accepted for now; Bundt's planned
     contracts, exports and bindings remove it.
   - a Team of its own for the factory, so a Team-scoped plan can delete
     what vanished from the tree. Recommended yes.
4. **`IAMRoleBinding` in the charts.** Recommended: switch `iam_bindings`
   to it in each chart's next minor version after the kind ships, and
   keep `iam` and `iam_by_principals` on `IAMPartialPolicy` (the builder's
   preference for non-authoritative IAM).
