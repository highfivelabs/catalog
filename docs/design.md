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

## Summary

1. **One Helm chart per fabric module, one Package per chart.** The chart
   renders Config Connector objects. Its values are the module's
   Terraform variables (same names, types, defaults and validations, in
   `values.schema.json`), so a module block becomes a values file one to
   one. Its Package's outputs are the module's outputs, CEL over the live
   objects.
2. **Nothing is dropped silently.** A variable Config Connector cannot
   express stays in the schema and stops the render with a message naming
   the gap.
3. **Helm by default; kro only for wiring that must happen at runtime
   inside one Package and that no Config Connector reference can carry.**
   None of the 91 modules needs it today (section "kro or Helm").
4. **IAM**: additive variables become `IAMPolicyMember`, authoritative
   ones `IAMPartialPolicy`, never `IAMPolicy`. Role-authoritative IAM is
   the largest gap, 43 modules (gap 1 in the inventory).
5. **References**: Config Connector references inside a chart, Bundt's
   `valueFrom` between charts.
6. **Deletion**: Config Connector's default (delete), as Bundt decided;
   `deletion_policy: ABANDON` keeps the resources.
7. **Organization and folder Packages run only where the platform team's
   identity does**, never in a team's namespace.
8. **Tests in three layers**: render (every change, offline), a fake cloud
   (an offload VM), a real project (pilot only, cleaned up).

The pilot ports iam-service-account, gcs, net-vpc and the core of
project, and proves render and the fake cloud end to end ("Pilot").

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
listed in the inventory), alpha (a `v1alpha1` kind; see "Questions"), and
"not ported yet" (Config Connector has it; the pilot did not map it).

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
(packages.md R8). The binding is not specified yet; the charts assume
this one, and the pilot evaluates it (`tools/catalogtool outputs`):

- each object whose annotation `hfl.dev/id` is set is bound as
  `resources.<id>` (or `resources["subnet:europe-west1/apps"]`);
- the CEL environment has the standard library plus `strings`, `lists`
  and two-variable comprehensions (`transformMapEntry`), which map
  outputs such as net-vpc's `subnet_ids` need.

| fabric output | Package output |
| --- | --- |
| `iam-service-account.email` | `resources.service_account.status.email` |
| `gcs.url` | `resources.bucket.status.url` |
| `net-vpc.subnet_ids` | `resources.transformMapEntry(k, v, v.kind == 'ComputeSubnetwork' && !has(v.spec.purpose), {k.substring(7): 'projects/' + … + v.spec.resourceID})` |
| `project.number` | `resources.project.status.number` |

Differences from Terraform:

- Fabric computes many outputs from inputs, so dependents need not wait
  (`email` is known before the account exists). In Bundt every output is
  read from live objects, so a dependent waits until the producer is
  ready, which Bundt does anyway ("Dependents wait until ready",
  drafts/delivery).
- Outputs that are whole Terraform objects (`gcs.bucket`,
  `iam-service-account.service_account`, `net-vpc.subnets`) are not
  ported: a Package output is a value another component's input takes.
- Outputs of something the chart did not make (`bucket_create: false`,
  `vpc_reuse`) have no value.
- A few outputs have no source: `net-vpc.network_id` (ComputeNetwork does
  not report the numeric ID; a field gap).

Whether `inputs` should be bound too (fabric outputs computed from inputs,
such as `project_id` when the project is reused) is a question.

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
one plan line and one blast radius. Recommended: a generator that reads
the factory's YAML tree and writes Bundt documents, one Instance per
project (of a `gcp-project-baseline` Template: project, its service
accounts, buckets, budget), and folders as components of a platform
Stack; Bundt then plans, approves and deletes per project. See
"Questions".

**Not Packages**: `cloud-config-container` (cloud-init text for VMs, a
helper not a resource) and `projects-data-source` (a read). The
`__experimental_deprecated` modules are left out.

## IAM

| fabric variable | Config Connector | Semantics |
| --- | --- | --- |
| `iam` `{ROLE: [MEMBERS]}`, `iam_by_principals` `{PRINCIPAL: [ROLES]}` (merged, as fabric merges them), `iam_bindings` `{KEY: {role, members, condition}}` | one `IAMPartialPolicy` per resource, a binding per role (and condition) | fabric: authoritative per role, members added out of band are removed. Here: the listed members are kept; others are left alone; deleting the component removes only the listed members |
| `iam_bindings_additive` `{KEY: {member, role, condition}}`, `iam_by_principals_additive` | one `IAMPolicyMember` each | the same: additive |
| roles granted *to* a service account elsewhere (`iam_project_roles`, `iam_storage_bindings`, ...) | one `IAMPolicyMember` each, `memberFrom.serviceAccountRef` naming the chart's account | the same; the member is resolved by Config Connector, no email crosses the plan |
| IAM on a resource IAMPolicyMember cannot reference (regional secrets, managed folders, log views, 32 types) | none | a gap (inventory, gap 2) |

- **Never `IAMPolicy`.** It owns the whole policy: on a project it would
  remove every grant made elsewhere (Bundt's fixed L2 check refuses it on
  a project), on a bucket the legacy owner and reader bindings. It also
  must not be mixed with the other two kinds on one resource.
- **The authoritative gap.** `IAMPartialPolicy` is the closest kind, and
  differs in one way that matters for security: a member someone adds by
  hand to a role the chart manages stays. Gap 1 proposes
  `IAMPolicyBinding` in config-connector-extensions (one role on one
  resource, its members exactly), which would make fabric's `iam` exact.
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

Three layers. Only the first runs on a laptop.

1. **Render**, `hack/test.sh`, every change, a few seconds: shared helper
   copies match; `helm lint`; the Package document matches the chart and
   every output compiles as CEL; each test case renders to its golden
   file; every render validates with `kubeconform -strict` against JSON
   schemas made from Config Connector v1.160.0's CRDs, every object closed
   (`additionalProperties: false`), so a misspelt or missing field fails;
   each `*.fail.yaml` is refused with its expected message.
2. **Fake cloud**, `hack/mock-apply.sh`, on an offload VM: the
   config-connector-extensions fake cloud (a kind cluster with Config
   Connector's CRDs; Config Connector's own manager on the host, every
   Google API answered by mockgcp). Each chart's `mock.values.yaml` is
   applied server-side; every object must become Ready; the Package's
   outputs are evaluated against the live objects; every object is
   deleted at once and must be gone. Limits: mockgcp's coverage (no liens,
   no Shared VPC), no Config Connector webhooks (so the project annotation
   is explicit), and Config Connector at config-connector-extensions' pin
   (ahead of v1.160.0).
3. **Live**, pilot only, after the fake cloud passes: project
   `hfl-dev-514205` only, from an offload VM acting as a service account
   (never a downloaded key), tiny resources named per run, deleted
   straight after, and a check that nothing is left.

Not covered yet: upgrades between chart versions (comparing two versions'
renders for replaced resources and renamed objects, which is the major
version test above), and Bundt itself (its kro, hooks and outputs land in
later levels).

## Pilot

Four charts (`UPSTREAM.md`, "What is ported"):

| Chart | Fabric module (size) | Ported | Refused (gap, alpha, not ported) |
| --- | --- | --- | --- |
| `iam-service-account` | M | all of it | reuse, tag bindings, context |
| `gcs` | L | all but the gaps | object retention, hierarchical namespace, rpo, objects, managed folders (alpha), KMS autokeys |
| `net-vpc` | L | network, every subnet kind, the subnet factory, subnet IAM, routes, googleapis routes, peering, Shared VPC host, DNS policy, PSA, the global firewall policy association | BGP fields, internal ranges, network attachments, policy-based routes, service connection policies (alpha), regional firewall policy associations, PSA route export and peered domains (alpha) |
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

1. **Package names.** Recommended: `gcp-<module>` for the Package and the
   fabric module's name for the chart; the prefix avoids clashes with the
   AWS and Azure catalogs. Alternatively one name for both.
2. **The outputs binding.** Recommended: objects bound as
   `resources.<hfl.dev/id>`, with CEL's strings, lists and two-variable
   comprehension extensions (needed for map outputs). Settles how
   packages.md R8 reads "the rendered resources". Also: bind `inputs`?
   Recommended yes, for outputs fabric computes from inputs.
3. **Alpha kinds.** Recommended: charts refuse them by default and allow
   them behind a per-chart `allow_alpha: true` value, so foundational
   features (deny policies, SCC mute configs, internal ranges) are usable
   by teams who accept the risk.
4. **Factories.** Recommended: a generator from fabric's factory YAML to
   Bundt documents (one Instance per project), not a chart that loops.
5. **Authoritative IAM.** Recommended: build `IAMPolicyBinding` in
   config-connector-extensions (gap 1) before teams migrate IAM-heavy
   modules; until then `IAMPartialPolicy`, with the difference stated in
   each chart's README.
6. **kro.** Recommended: Helm as the default engine, kro only by the test
   above, and the runtime-value gaps closed as reference fields in
   config-connector-extensions instead.
7. **Where org-level Packages run.** Recommended: a capability
   (`hfl.dev/gcp-scope`) that only the platform team's Environment
   provides.
