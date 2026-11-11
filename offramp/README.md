# The Terraform offramp

A prototype of a no-op, day-one import from Terraform into Bundt on Google
Cloud. It starts from a Terraform state, or from a scan of a folder or
organization. It produces Config Connector objects that adopt each resource
as it is, and the Bundt documents that hold them. Where a module call's
module has a catalog chart, the call becomes an Instance of that chart, with
the call's arguments as its values unchanged. It does so only after the
chart's render is checked against the state.

The design, the live results and the questions for the builder are in Bundt,
`drafts/tf-offramp/README.md` (branch `tf-offramp`).

| Path | What |
| --- | --- |
| `fixtures/` | four Terraform root modules built only from published modules pinned to exact releases (below); they may move to the `terraform-offramp-demo` repository, so every task takes `FIXTURES` |
| `fixtures-terragrunt/` | a Terragrunt estate: units whose source is an open-source module, and units whose source is the team's own wrapper module (below) |
| `cmd/offramp`, `internal/offramp` | the converter, the graduation to charts, `offramp synth`, the Terragrunt reader |
| `hack/scan.sh` | the scan: Cloud Asset Inventory, else the services' own list calls |
| `hack/live.sh` | the live proof of one shape |
| `hack/validate.sh` | `terraform fmt`, `init` and `validate` of every fixture; keeps each fixture's `modules.json` |
| `internal/offramp/testdata/` | Config Connector's CRDs and service mappings for the kinds the fixtures use; `modules/` (each fixture's `modules.json`), `live/` (states from live runs), `synthetic/` (states from `offramp synth`) |

## The fixtures: module calls and their charts

Every resource comes from a module call. Calls use terraform-google-modules,
the family the builder uses. They use Cloud Foundation Fabric where the
catalog's existing chart ports Fabric (`net-vpc`, `project`,
`iam-service-account`, `gcs`), so every call has a chart that ports the same
module at the same release.

| Shape | Call | Module and release | Catalog chart | Status |
| --- | --- | --- | --- | --- |
| shared-vpc | `vpc` | fabric `net-vpc` v60.0.0 | `net-vpc` | exists (0.3.1 renders flow log defaults) |
| shared-vpc | `firewall_rules` | tgm `network//modules/firewall-rules` 18.3.1 | `firewall-rules` | built here |
| shared-vpc | `network_firewall_policy` | tgm `network//modules/network-firewall-policy` 18.3.1 | `network-firewall-policy` | built here (rules are a v1alpha1 kind: `allow_alpha`) |
| folders | `root`, `environments`, `teams` | tgm `folders` 5.2.0 | `folders` | built here |
| folders | `auditor` | tgm `iam//modules/folders_iam` 8.3.0 | `folders-iam` | built here |
| folders | `skip_default_network`, `resource_locations`, `require_os_login` | tgm `org-policy//modules/org_policy_v2` 7.4.0 | `org-policy-v2` | built here |
| folders | `hierarchical_firewall` | tgm `network//modules/hierarchical-firewall-policy` 18.3.1 | `hierarchical-firewall-policy` | built here |
| platform-project | `project` | fabric `project` v60.0.0 | `project` | exists; the render lacks fabric's default service agents and their grants (not ported), so the call stays a frozen Package |
| platform-project | `platform_deployer`, `platform_ci`, `checkout` | fabric `iam-service-account` v60.0.0 | `iam-service-account` | exists |
| platform-project | `checkout_assets` | fabric `gcs` v60.0.0 | `gcs` | exists |
| platform-project | `checkout_secrets` | fabric `secret-manager` v60.0.0 | none | gap: no chart, a frozen Package |
| gke | `network` | fabric `net-vpc` v60.0.0 | `net-vpc` | exists |
| gke | `gke_standard` (`gke_autopilot` with `autopilot = true`) | tgm `kubernetes-engine//modules/beta-private-cluster` (`beta-autopilot-private-cluster`) 47.0.0 | `gke-cluster` (PR #16; `mode: autopilot`) | exists on its branch; its render sets `datapathProvider` and `initialNodeCount` where the planned state holds neither, so the call stays frozen until a live run settles it |

Only shared-vpc runs live: the live-test account lacks the other shapes'
grants (register items O33 and O34). The other three are validated
(`task offramp-validate`) and converted offline from synthetic states.

## The converter

```sh
go build -o ../bin/offramp ./cmd/offramp

# From a state. --kcc is a Config Connector checkout at the release the
# cluster runs (its config/crds/resources and config/servicemappings).
# --root graduates the root module's calls to catalog charts: it reads the
# module blocks (catalogtool convert), takes each call's source and version
# from .terraform/modules/modules.json when terraform init has run (or
# --modules-json), renders the chart, and compares the render with the
# objects converted from the state.
../bin/offramp state --kcc ~/src/k8s-config-connector --state terraform.tfstate \
  --root path/to/root-module --tfvars path/to/terraform.tfvars \
  --out out --name shared-vpc --team platform --env prod --target infra

# A synthetic state for a root module that cannot be applied: Terraform
# plans it offline, repeatedly; only what the cloud assigns is made up.
../bin/offramp synth --root fixtures/folders --tfvars folders.tfvars --out folders.tfstate

# From a scan: the assets, the names to export, Config Connector's export,
# then the same grouping (no graduation: a scan has no module calls).
hack/scan.sh --scope folders/123 --billing-project my-project >assets.json
../bin/offramp names --assets assets.json >names.txt
while read -r n; do config-connector export "$n" --iam-format policymember --output "export/$(echo "$n" | md5sum | cut -c1-8).yaml"; done <names.txt
../bin/offramp krm --krm export --out out-scan

# What one has that the other lacks, field by field.
../bin/offramp compare out/krm/all.yaml out-scan/krm/all.yaml
```

The output (`--out`) holds:

- `krm/all.yaml`: every object, frozen.
- `krm/adopt.yaml`: what Bundt delivers on the import. That is the chart's
  render for each graduated call and the frozen objects for every other
  call. Every object carries `deletion-policy: abandon` and
  `state-into-spec: absent`.
- `packages/<package>/manifests/`: the frozen Packages.
- `graduation/<component>/`: the values, the render, the state's objects and
  their differences.
- `bundt/prereqs.yaml`, `bundt/catalog.yaml` and `bundt/record.yaml`. A
  graduated call is a Template component naming the chart's Package, with
  the call's literal arguments as inputs. Its per-environment arguments are
  the Instance's `spec.components.<c>.values`.
- `report.md`: what became what, the "Module calls and catalog charts"
  table, and every finding.

### Graduation: the equivalence check

For each call whose module a chart ports:

1. The call's arguments become the chart's values unchanged.
2. The import adds `deletion_policy: ABANDON`. Where the chart names a
   resource by a cloud-assigned ID (a folder's number, a hierarchical
   firewall policy's ID), it also adds `resource_ids` from the state. Where
   the call needs an alpha kind, it adds `allow_alpha: true`.
3. Another call's output (`module.vpc.id`) becomes
   `${components.vpc.outputs.id}`. A function applied to one becomes CEL
   (`trimprefix(module.root.id, "folders/")`). To check the render, the
   expression is evaluated against the producer's chart outputs. Those
   outputs are computed from its render, with each object's status taken
   from the state.
4. The chart is rendered with `helm template` and compared with the
   resource-level conversion, resource by resource, with references
   compared by name.
5. A field the render leaves out does not count as a difference. With
   `state-into-spec: absent`, Config Connector neither sets nor changes it,
   and the report lists it as left to the cloud.
6. Only a call with no differences graduates. Any other call keeps its
   frozen Package and lists why. A graduated call that reads a frozen
   call's output gets the resolved value instead.

`go test ./...` runs this for every fixture (`TestEquivalence`): against the
live shared-vpc state, and against synthetic states for all four shapes.

## Terragrunt estates

`offramp terragrunt` reads a Terragrunt estate: every `terragrunt.hcl`
under `--estate` that no other unit includes is a unit, a Terraform root
module with its own state.

```sh
../bin/offramp terragrunt --kcc ~/src/k8s-config-connector --estate live/prod \
  --states pulled-states --out out --name prod --team platform --env prod
```

**Nothing runs.** Neither Terragrunt nor Terraform: each file is parsed
with HCL and evaluated with the functions that need only the files.

- **Read.** `include` (labelled or not, `expose`, `merge_strategy`
  shallow, deep or no_merge) with the included file evaluated in the
  unit's context, and `locals`. `inputs` merged over the included ones.
  `terraform { source }` (`tfr://`, `git::`, GitHub, the registry, a local
  path with Terragrunt's `//`). `dependency` and `dependencies`.
  `remote_state` and `generate`.
- **Functions.** `find_in_parent_folders`, `read_terragrunt_config`,
  `path_relative_to_include` and `path_relative_from_include`,
  `get_terragrunt_dir`, `get_parent_terragrunt_dir`, `get_repo_root` and
  its two path functions, `read_tfvars_file`, and `get_env`, which reads
  `--getenv NAME=VALUE`, else the default, and notes which. Also
  Terraform's functions that need no run, including `file`,
  `yamldecode` and `jsondecode`.
- **Never guessed.** `run_cmd`, `sops_decrypt_file`, the `get_aws_*`
  functions, `get_platform`, `get_terraform_command`, `timestamp`,
  `uuid`, and a `get_env` with no default and no `--getenv` cannot be
  evaluated from the files. Neither can a function, condition or loop over
  a dependency's output. The input, local or source that needs one is left
  out, and an `unevaluated` finding names the expression and why. A local
  that fails fails only what reads it.
- **Listed, not run.** `generate` blocks (the provider and backend files)
  are listed with their paths. Hooks and `extra_arguments` are noted.
  `mock_outputs` are never used.
- **Where the state is.** `remote_state` gives each unit's state location
  (`gs://<bucket>/<prefix>/default.tfstate` for gcs). The offramp reads
  the state from `--states DIR` (`DIR/<unit path>/terraform.tfstate`, from
  `terragrunt state pull`) or `--state UNIT=FILE`. A unit with no state
  is a `gap` finding that says where its state lives.

**Two cases.** A unit's source is one of two things:

1. **An open-source module the catalog tracks**, such as
   `tfr:///terraform-google-modules/network/google//modules/firewall-rules?version=18.3.1`.
   The module is the unit's root. The unit is converted as one call of
   that module, its inputs the arguments. Like a module call, it graduates
   to the module's chart when the render matches the unit's state. An
   input the chart has no value for is noted: Terraform ignores an input
   the module does not declare, and the chart ports every variable.
2. **The team's own root module**, a wrapper: a local path, or a remote
   source mapped to a checkout with `--source-map URL=DIR`. It may call
   open-source modules (Cloud Foundation Fabric's project module,
   terraform-google-modules' beta-private-cluster). The offramp descends
   into it. Each module call inside is converted and checked against its
   chart, as in a plain root module, with the unit's inputs as the
   wrapper's variables. The calls become components `<unit>-<call>`. The
   wrapper's own resources (no module makes them) stay a frozen Package,
   component `<unit>`, each listed as an `unmapped` finding.

A remote source that is neither is a `gap`: its resources stay one frozen
Package.

**Between units.** The estate is one Template. A `dependency` output
becomes a reference to the producing component's output:
`dependency.vpc.outputs.name` is `${components.vpc.outputs.name}`. For a
wrapper, the reference goes through the wrapper's `output` block to the
call output it passes on. An output a wrapper computes itself has no
component, so it is reported. `dependency` and `dependencies` become
`dependsOn`. Each object's `offramp.hfl.dev/source` is
`<unit path>:<Terraform address>`, the state the hand-off removes it from.

**The fixtures** (`fixtures-terragrunt/`, tested by `TestTerragruntEquivalence`):

| Unit | Source | Case | Result |
| --- | --- | --- | --- |
| `network/vpc` | fabric `net-vpc` v60.0.0 over `git::` | module | graduates to `net-vpc` |
| `network/firewall-rules` | tgm `firewall-rules` 18.3.1 over `tfr://`; `dependency.vpc.outputs.name` | module | graduates to `firewall-rules`, `network_name: ${components.vpc.outputs.name}` |
| `network/network-firewall-policy` | tgm `network-firewall-policy` 18.3.1 over `git::`; `dependency.vpc.outputs.id` | module | graduates to `network-firewall-policy` |
| `gke/gke-platform` | `modules//gke-platform`, a wrapper of fabric `net-vpc` and tgm `beta-private-cluster` 47.0.0, plus a firewall rule, a service account and a project grant of its own | wrapper | `network` graduates; `cluster` stays frozen (`datapathProvider`, as in `fixtures/gke`); the three own resources are `unmapped` |
| `platform/project` | `fixtures//platform-project`, a wrapper of fabric `project`, `iam-service-account`, `gcs` and `secret-manager` | wrapper | as `fixtures/platform-project`: four calls graduate, `project` stays frozen (`ServiceIdentity`), `secret-manager` has no chart |

The network units' states are the live shared-vpc run's, split per unit.
The others are synthetic (`internal/offramp/testdata/terragrunt/README.md`).
`TestTerragruntMatchesRenderJSON` checks the static reading against
`terragrunt render-json`.

## Tests

- `task offramp-test`: gofmt, vet and `go test`, including the equivalence
  check of every fixture. It needs helm.
- `task offramp-validate`: checks the fixtures on an offload VM and keeps
  each fixture's `modules.json`.
- `task offramp-live SHAPE=shared-vpc`: runs the live proof in
  hfl-dev-514205 as `cce-live-tests@`, adopting `krm/adopt.yaml`.

Each takes `FIXTURES`, the directory of root modules relative to the
repository (default `offramp/fixtures`).
