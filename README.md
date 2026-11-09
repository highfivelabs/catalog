# catalog

Bundt's seed catalog: Packages that teams instantiate as components.
Today it holds the first Google Cloud Packages, Helm charts of Config
Connector objects ported from Cloud Foundation Fabric's Terraform modules,
so a team moving from those modules keeps its variables, its names and
its outputs.

| Path | What |
| --- | --- |
| `docs/design.md` | how a fabric module becomes a Package: values, IAM, references, deletion, scope, kro or Helm, versioning, testing, the pilot's results, questions |
| `docs/gcp-inventory.md` | every fabric module against Config Connector v1.160.0, ranked, and the gaps for config-connector-extensions |
| `charts/gcp/<module>/` | one chart per ported module, with its Bundt Package (`package.yaml`), README and tests |
| `upstream/modules.yaml` | every open-source Terraform module the catalog tracks (91 fabric modules, 40 terraform-aws-modules, 37 Azure Verified Modules): repository, path, pinned release and commit, licence, registry and module pages, and the chart that ports it |
| `charts/<cloud>/<chart>/upstream.yaml` | where one chart came from: the module, release, commit, licence and date synced |
| `lib/_kcc.tpl` | helpers every chart carries a copy of (`hack/sync-lib.sh`) |
| `tools/catalogtool` | Config Connector CRDs to kubeconform schemas; Package checks; outputs evaluated against live objects |
| `Taskfile.yml` | the entry points: `task test`, `test-live`, `test-mock`, `inventory`, `upstream-check`, `tools-test` (`task --list`) |
| `hack/test.sh` | render tests (offline, seconds), behind `task test` |
| `hack/mock-apply.sh`, `hack/live-apply.sh` | the fake-cloud and real-project applies (an offload VM, never a laptop), behind `task test-mock` and `task test-live` |
| `hack/inventory/run.sh` | regenerates the inventory's tables, behind `task inventory` |
| `UPSTREAM.md` | the fabric and Config Connector commits everything is pinned to, the tracked modules' licences, and how to move a pin |

```sh
task test                    # all charts; needs task, helm, kubeconform, go, git
task test CHART=gcs          # one chart
task test-update CHART=gcs   # accept a chart's new renders
```

Charts: `iam-service-account`, `gcs`, `net-vpc`, `project` (partial). Every
chart links to the open-source module it ports and records the release it
was ported from (`upstream.yaml`), so changes upstream are easy to find and
pull in.

Licensed under Apache-2.0 (`LICENSE`); the charts are derived from Cloud
Foundation Fabric, Copyright Google LLC, Apache-2.0 (`NOTICE`).
