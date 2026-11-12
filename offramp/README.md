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
| `cmd/offramp`, `internal/offramp` | the converter, the graduation to charts, `offramp synth` |
| `hack/scan.sh` | the scan: Cloud Asset Inventory, else the services' own list calls |
| `hack/live.sh` | the live proof of one shape |
| `hack/validate.sh` | `terraform fmt`, `init` and `validate` of every fixture; keeps each fixture's `modules.json` |
| `internal/offramp/testdata/` | Config Connector's CRDs and service mappings for the kinds the fixtures use; `modules/` (each fixture's `modules.json`), `live/` (states from live runs), `synthetic/` (states from `offramp synth`) |

## The fixtures: module calls and their charts

Every resource comes from a module call. Calls use terraform-google-modules,
the family in use. They use Cloud Foundation Fabric where the
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

## Tests

- `task offramp-test`: gofmt, vet and `go test`, including the equivalence
  check of every fixture. It needs helm.
- `task offramp-validate`: checks the fixtures on an offload VM and keeps
  each fixture's `modules.json`.
- `task offramp-live SHAPE=shared-vpc`: runs the live proof in the
  live-test project (`GCP_PROJECT`) as `GCP_CCE_LIVE_SA`, adopting
  `krm/adopt.yaml`; the other shapes need the grants the design lists.

Each takes `FIXTURES`, the directory of root modules relative to the
repository (default `offramp/fixtures`).
