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
| `lib/_kcc.tpl` | helpers every chart carries a copy of (`hack/sync-lib.sh`) |
| `tools/catalogtool` | Config Connector CRDs to kubeconform schemas; Package checks; outputs evaluated against live objects |
| `Taskfile.yml` | the entry points: `task test`, `test-live`, `test-mock`, `inventory` (`task --list`) |
| `hack/test.sh` | render tests (offline, seconds), behind `task test` |
| `hack/mock-apply.sh`, `hack/live-apply.sh` | the fake-cloud and real-project applies (an offload VM, never a laptop), behind `task test-mock` and `task test-live` |
| `hack/inventory/run.sh` | regenerates the inventory's tables, behind `task inventory` |
| `UPSTREAM.md` | the fabric and Config Connector commits everything is pinned to |

```sh
task test                    # all charts; needs task, helm, kubeconform, go, git
task test CHART=gcs          # one chart
task test-update CHART=gcs   # accept a chart's new renders
```

Charts: `iam-service-account`, `gcs`, `net-vpc`, `project` (partial).

Licensed under Apache-2.0 (`LICENSE`); the charts are derived from Cloud
Foundation Fabric, Copyright Google LLC, Apache-2.0 (`NOTICE`).
