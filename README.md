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
| `hack/test.sh` | render tests (offline, seconds) |
| `hack/mock-apply.sh` | the fake-cloud apply (an offload VM, never a laptop) |
| `hack/inventory/run.sh` | regenerates the inventory's tables |
| `UPSTREAM.md` | the fabric and Config Connector commits everything is pinned to |

```sh
hack/test.sh                 # all charts; needs helm, kubeconform, go, git
UPDATE=1 hack/test.sh gcs    # accept a chart's new renders
```

Charts: `iam-service-account`, `gcs`, `net-vpc`, `project` (partial).

Licensed under Apache-2.0 (`LICENSE`); the charts are derived from Cloud
Foundation Fabric, Copyright Google LLC, Apache-2.0 (`NOTICE`).
