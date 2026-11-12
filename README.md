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
| `docs/coverage/` | how much of each tracked open-source module the catalog carries: CSVs per module, variable, output and resource type, SVG bars, and the method (`task coverage`) |
| `docs/migrating-from-terraform.md`, `examples/` | moving a Terraform module call to the catalog: the mapping, `catalogtool convert` (`task convert`), a worked example for each chart with its plan, and adopting resources that already exist |
| `docs/upstream-status.md`, `.github/workflows/upstream-watch.yml` | which tracked modules have a newer release than their pin, and what changed (`task upstream-watch`); a daily workflow keeps one tracking issue; `task upstream-bump` records a release as taken |
| `charts/gcp/<module>/` | one chart per ported module, with its Bundt Package (`package.yaml`), README and tests |
| `upstream/modules.yaml` | every open-source Terraform module the catalog tracks (91 fabric modules, terraform-google-modules' kubernetes-engine beta-private-cluster, 40 terraform-aws-modules, 37 Azure Verified Modules): repository, path, pinned release and commit, licence, registry and module pages, and the chart that ports it |
| `charts/<cloud>/<chart>/upstream.yaml` | where one chart came from: the module, release, commit, licence and date synced |
| `lib/_kcc.tpl` | helpers every chart carries a copy of (`hack/sync-lib.sh`) |
| `tools/catalogtool` | Config Connector CRDs to kubeconform schemas; Package checks; outputs evaluated against live objects |
| `Taskfile.yml` | the entry points: `task check`, `test`, `test-live`, `test-mock`, `inventory`, `upstream-check`, `coverage`, `coverage-check`, `coverage-verify`, `convert`, `examples-test`, `upstream-watch`, `upstream-bump`, `tools-test` (`task --list`) |
| `hack/test.sh` | render tests (offline, seconds), behind `task test` |
| `hack/mock-apply.sh`, `hack/live-apply.sh` | the fake-cloud and real-project applies (an offload VM, never a laptop), behind `task test-mock` and `task test-live` |
| `hack/inventory/run.sh` | regenerates the inventory's tables, behind `task inventory` |
| `UPSTREAM.md` | the fabric and Config Connector commits everything is pinned to, the tracked modules' licences, and how to move a pin |

```sh
task test                    # all charts; needs task, helm, kubeconform, go, git
task test CHART=gcs          # one chart
task test-update CHART=gcs   # accept a chart's new renders
task check                   # what CI runs: gofmt, vet, Go tests, task test, examples, coverage current, shellcheck, actionlint
```

Charts: `iam-service-account`, `gcs`, `net-vpc`, `project` (partial), and
`gke-cluster` (partial), a GKE cluster in Standard or Autopilot mode ported
from terraform-google-modules' kubernetes-engine `beta-private-cluster` and
its Autopilot twin. Every chart links to the open-source module it ports
and records the release it was ported from (`upstream.yaml`), so changes
upstream are easy to find and pull in. Every chart takes whole cloud names (`names.<resource>`; a name not
set derives from `name`), an optional `namePrefix`, and `labels` (Kubernetes)
and `tags` (cloud labels) that it puts on every object, so Bundt can supply
names and identity labels from a team's naming convention
(`docs/design.md`, "Names, labels and tags").

## Run CI locally

Every job in `.github/workflows/` is a `task` call; the steps around it
only check out the code and install tools. The same commands run here:

```sh
task ci:tools       # task, helm, kubeconform, actionlint at ci.yml's pins
                    # into ~/.local/hfl-tools; put that first on PATH
                    # (shellcheck: your package manager, as the runner's image)
task ci             # ci.yml's pull-request job (task check) at those pins
task upstream-watch # upstream-watch.yml's daily job, read-only
```

`upstream-watch.yml` then runs `task upstream-watch:issue`, which writes
this repository's tracking issue; run it by hand only to do that.

## The merge gate

GitHub Actions is off in the organization (2026-11-11); the
workflows in `.github/workflows/` stay, disabled. `ci.yml`'s pull-request
job runs before the push instead:

```sh
task hooks          # once per clone: core.hooksPath=hack/hooks
task ci             # by hand: HEAD (or SHA=...)
```

`task ci` (`hack/ci/gate.sh`) checks the commit out into a temporary
worktree and runs `task check` there, on this machine: it takes under a
minute (an offload VM takes longer than that to boot), and the offload
image lacks the linters it runs. It fails unless task and the tools
`ci.yml` pins (`*_VERSION`) are installed at those versions and
shellcheck is installed, and it runs Go at `ci.yml`'s `go-version-file`
(`GOTOOLCHAIN`), so nothing is skipped as "not installed". It uploads the
log to the offload bucket, prints its location (the bucket is private),
and posts the commit status `offload/ci` (success or failure, what ran,
in how long; no link and no environment identifiers, since the
repository's statuses are public) on the commit. The pre-push
hook (`hack/hooks/pre-push`) runs it for every branch commit pushed and
refuses the push on a failure; a commit that already has `offload/ci`
success is not run again.

**Merge only when the `offload/ci` status on the pull request's head is
success.** A new commit on the branch needs its own run.

### Environment identifiers

Project IDs, buckets and service accounts are not in the tree. Scripts read
them from the environment and fail, naming the variable, when one is
missing. Copy `.env.example` to `.env` (git-ignored; `Taskfile.yml` and
`hack/ci/gate.sh` load it) and fill in: `OFFLOAD_PROJECT` and
`OFFLOAD_BUCKET` for `task ci`; `GCP_PROJECT` (or the test estate's
`HFL_GCP_TEST_PROJECT`), `GCP_LIVE_SA` and `OFFLOAD_BUCKET` for
`task test-live`, which passes the project to the VM on the offload
command line.

<!-- coverage:start -->
## Coverage against the open-source modules

How much of the Terraform modules people use today the catalog carries, counted from each module's `variables.tf` and `outputs.tf` at the release pinned in [`upstream/modules.yaml`](upstream/modules.yaml). Method, columns and the full per-module data: [`docs/coverage/`](docs/coverage/README.md).

![All tracked modules](docs/coverage/total.svg)

**175 modules tracked**: 2 ported, 9 partial, 62 blocked, 102 not started. Green is ported, amber partial (some variables refused with a message that names the gap), dark grey blocked (a resource type of the module has no stable kind: none, or only an alpha one), light grey not started.

| Source | Modules | Bar | Variables covered |
| --- | ---: | --- | ---: |
| Google Cloud: Cloud Foundation Fabric and terraform-google-modules | 98 | ![gcp](docs/coverage/gcp.svg) | 269 of 1478 (18.2%) |
| AWS: terraform-aws-modules | 40 | ![aws](docs/coverage/aws.svg) | 0 of 2310 (0.0%) |
| Azure: Azure Verified Modules | 37 | ![azure](docs/coverage/azure.svg) | 0 of 1170 (0.0%) |
| **All** | **175** | | **269 of 4958 (5.4%)** |

### Google Cloud: Cloud Foundation Fabric and terraform-google-modules

2 ported, 9 partial, 62 blocked, 25 not started.

**Ported and partial**

| Module | Variables covered | Outputs | Resource types with a stable kind | Status |
| --- | --- | ---: | ---: | --- |
| [`project`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/project) ([chart](charts/gcp/project)) | ![project](docs/coverage/bars/gcp-project.svg) 21 of 58 | 6 of 27 | 41 of 49 | partial |
| [`iam-service-account`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/iam-service-account) ([chart](charts/gcp/iam-service-account)) | ![iam-service-account](docs/coverage/bars/gcp-iam-service-account.svg) 24 of 28 | 5 of 6 | 9 of 9 | partial |
| [`net-vpc`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpc) ([chart](charts/gcp/net-vpc)) | ![net-vpc](docs/coverage/bars/gcp-net-vpc.svg) 24 of 29 | 13 of 23 | 12 of 19 | partial |
| [`gcs`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gcs) ([chart](charts/gcp/gcs)) | ![gcs](docs/coverage/bars/gcp-gcs.svg) 30 of 36 | 5 of 7 | 8 of 12 | partial |
| [`kubernetes-engine-beta-private-cluster`](https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/tree/v47.0.0/modules/beta-private-cluster) ([chart](charts/gcp/gke-cluster)) | ![kubernetes-engine-beta-private-cluster](docs/coverage/bars/gcp-kubernetes-engine-beta-private-cluster.svg) 133 of 162 | 30 of 36 | 0 of 0 | partial |
| [`network-firewall-rules`](https://github.com/terraform-google-modules/terraform-google-network/tree/v18.3.1/modules/firewall-rules) ([chart](charts/gcp/firewall-rules)) | ![network-firewall-rules](docs/coverage/bars/gcp-network-firewall-rules.svg) 5 of 5 | 2 of 2 | 0 of 0 | ported |
| [`network-network-firewall-policy`](https://github.com/terraform-google-modules/terraform-google-network/tree/v18.3.1/modules/network-firewall-policy) ([chart](charts/gcp/network-firewall-policy)) | ![network-network-firewall-policy](docs/coverage/bars/gcp-network-network-firewall-policy.svg) 6 of 8 | 3 of 3 | 0 of 0 | partial |
| [`network-hierarchical-firewall-policy`](https://github.com/terraform-google-modules/terraform-google-network/tree/v18.3.1/modules/hierarchical-firewall-policy) ([chart](charts/gcp/hierarchical-firewall-policy)) | ![network-hierarchical-firewall-policy](docs/coverage/bars/gcp-network-hierarchical-firewall-policy.svg) 6 of 6 | 3 of 3 | 0 of 0 | partial |
| [`folders`](https://github.com/terraform-google-modules/terraform-google-folders/tree/v5.2.0) ([chart](charts/gcp/folders)) | ![folders](docs/coverage/bars/gcp-folders.svg) 8 of 8 | 7 of 10 | 0 of 0 | ported |
| [`iam-folders-iam`](https://github.com/terraform-google-modules/terraform-google-iam/tree/v8.3.0/modules/folders_iam) ([chart](charts/gcp/folders-iam)) | ![iam-folders-iam](docs/coverage/bars/gcp-iam-folders-iam.svg) 4 of 4 | 3 of 3 | 0 of 0 | partial |
| [`org-policy-v2`](https://github.com/terraform-google-modules/terraform-google-org-policy/tree/v7.4.0/modules/org_policy_v2) ([chart](charts/gcp/org-policy-v2)) | ![org-policy-v2](docs/coverage/bars/gcp-org-policy-v2.svg) 8 of 8 | 3 of 3 | 0 of 0 | partial |

**Blocked: a resource type has no stable kind (first 10 of 62, by rank)**

| Module | Variables covered | Outputs | Resource types with a stable kind | Status |
| --- | --- | ---: | ---: | --- |
| [`folder`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/folder) | ![folder](docs/coverage/bars/gcp-folder.svg) 0 of 31 | 0 of 9 | 16 of 24 | blocked |
| [`organization`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/organization) | ![organization](docs/coverage/bars/gcp-organization.svg) 0 of 35 | 0 of 23 | 25 of 35 | blocked |
| [`secret-manager`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/secret-manager) | ![secret-manager](docs/coverage/bars/gcp-secret-manager.svg) 0 of 4 | 0 of 5 | 6 of 10 | blocked |
| [`gke-cluster-standard`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gke-cluster-standard) | ![gke-cluster-standard](docs/coverage/bars/gcp-gke-cluster-standard.svg) 0 of 25 | 0 of 15 | 2 of 6 | blocked |
| [`gke-cluster-autopilot`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gke-cluster-autopilot) | ![gke-cluster-autopilot](docs/coverage/bars/gcp-gke-cluster-autopilot.svg) 0 of 21 | 0 of 15 | 2 of 6 | blocked |
| [`bigquery-dataset`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/bigquery-dataset) | ![bigquery-dataset](docs/coverage/bars/gcp-bigquery-dataset.svg) 0 of 24 | 0 of 12 | 4 of 7 | blocked |
| [`cloud-run-v2`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloud-run-v2) | ![cloud-run-v2](docs/coverage/bars/gcp-cloud-run-v2.svg) 0 of 21 | 0 of 12 | 9 of 13 | blocked |
| [`billing-account`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/billing-account) | ![billing-account](docs/coverage/bars/gcp-billing-account.svg) 0 of 11 | 0 of 2 | 8 of 10 | blocked |
| [`logging-bucket`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/logging-bucket) | ![logging-bucket](docs/coverage/bars/gcp-logging-bucket.svg) 0 of 12 | 0 of 2 | 7 of 9 | blocked |
| [`net-firewall-policy`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-firewall-policy) | ![net-firewall-policy](docs/coverage/bars/gcp-net-firewall-policy.svg) 0 of 13 | 0 of 1 | 6 of 11 | blocked |

**Not started (first 10 of 25, by rank)**

| Module | Variables covered | Outputs | Resource types with a stable kind | Status |
| --- | --- | ---: | ---: | --- |
| [`net-vpc-firewall`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpc-firewall) | ![net-vpc-firewall](docs/coverage/bars/gcp-net-vpc-firewall.svg) 0 of 8 | 0 of 2 | 1 of 1 | not started |
| [`net-cloudnat`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-cloudnat) | ![net-cloudnat](docs/coverage/bars/gcp-net-cloudnat.svg) 0 of 16 | 0 of 6 | 2 of 2 | not started |
| [`dns`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/dns) | ![dns](docs/coverage/bars/gcp-dns.svg) 0 of 9 | 0 of 6 | 3 of 3 | not started |
| [`kms`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/kms) | ![kms](docs/coverage/bars/gcp-kms.svg) 0 of 10 | 0 of 7 | 8 of 8 | not started |
| [`artifact-registry`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/artifact-registry) | ![artifact-registry](docs/coverage/bars/gcp-artifact-registry.svg) 0 of 17 | 0 of 4 | 4 of 4 | not started |
| [`cloudsql-instance`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloudsql-instance) | ![cloudsql-instance](docs/coverage/bars/gcp-cloudsql-instance.svg) 0 of 35 | 0 of 17 | 4 of 4 | not started |
| [`gke-nodepool`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gke-nodepool) | ![gke-nodepool](docs/coverage/bars/gcp-gke-nodepool.svg) 0 of 20 | 0 of 4 | 2 of 2 | not started |
| [`pubsub`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/pubsub) | ![pubsub](docs/coverage/bars/gcp-pubsub.svg) 0 of 14 | 0 of 6 | 7 of 7 | not started |
| [`vpc-sc`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/vpc-sc) | ![vpc-sc](docs/coverage/bars/gcp-vpc-sc.svg) 0 of 12 | 0 of 6 | 5 of 5 | not started |
| [`net-vpc-factory`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpc-factory) | ![net-vpc-factory](docs/coverage/bars/gcp-net-vpc-factory.svg) 0 of 4 | 0 of 3 | 0 of 0 | not started |

### AWS: terraform-aws-modules

0 ported, 0 partial, 0 blocked, 40 not started.

**Not started (first 10 of 40, by rank)**

| Module | Variables covered | Outputs | Resource types | Status |
| --- | --- | ---: | ---: | --- |
| [`iam`](https://github.com/terraform-aws-modules/terraform-aws-iam/tree/v6.8.2) | ![iam](docs/coverage/bars/aws-iam.svg) 0 of 0 | 0 of 0 | 17 | not started |
| [`s3-bucket`](https://github.com/terraform-aws-modules/terraform-aws-s3-bucket/tree/v5.17.0) | ![s3-bucket](docs/coverage/bars/aws-s3-bucket.svg) 0 of 78 | 0 of 21 | 45 | not started |
| [`vpc`](https://github.com/terraform-aws-modules/terraform-aws-vpc/tree/v6.7.3) | ![vpc](docs/coverage/bars/aws-vpc.svg) 0 of 236 | 0 of 119 | 35 | not started |
| [`eks`](https://github.com/terraform-aws-modules/terraform-aws-eks/tree/v21.29.0) | ![eks](docs/coverage/bars/aws-eks.svg) 0 of 108 | 0 of 41 | 30 | not started |
| [`kms`](https://github.com/terraform-aws-modules/terraform-aws-kms/tree/v4.2.2) | ![kms](docs/coverage/bars/aws-kms.svg) 0 of 41 | 0 of 9 | 6 | not started |
| [`lambda`](https://github.com/terraform-aws-modules/terraform-aws-lambda/tree/v8.13.0) | ![lambda](docs/coverage/bars/aws-lambda.svg) 0 of 141 | 0 of 36 | 21 | not started |
| [`security-group`](https://github.com/terraform-aws-modules/terraform-aws-security-group/tree/v6.0.0) | ![security-group](docs/coverage/bars/aws-security-group.svg) 0 of 14 | 0 of 5 | 5 | not started |
| [`rds`](https://github.com/terraform-aws-modules/terraform-aws-rds/tree/v7.2.2) | ![rds](docs/coverage/bars/aws-rds.svg) 0 of 111 | 0 of 34 | 10 | not started |
| [`rds-aurora`](https://github.com/terraform-aws-modules/terraform-aws-rds-aurora/tree/v10.4.2) | ![rds-aurora](docs/coverage/bars/aws-rds-aurora.svg) 0 of 114 | 0 of 33 | 21 | not started |
| [`acm`](https://github.com/terraform-aws-modules/terraform-aws-acm/tree/v6.3.1) | ![acm](docs/coverage/bars/aws-acm.svg) 0 of 24 | 0 of 7 | 3 | not started |

### Azure: Azure Verified Modules

0 ported, 0 partial, 0 blocked, 37 not started.

**Not started (first 10 of 37, by rank)**

| Module | Variables covered | Outputs | Resource types | Status |
| --- | --- | ---: | ---: | --- |
| [`avm-res-network-virtualnetwork`](https://github.com/Azure/terraform-azurerm-avm-res-network-virtualnetwork/tree/v0.23.0) | ![avm-res-network-virtualnetwork](docs/coverage/bars/azure-avm-res-network-virtualnetwork.svg) 0 of 22 | 0 of 6 | 5 | not started |
| [`avm-res-network-networksecuritygroup`](https://github.com/Azure/terraform-azurerm-avm-res-network-networksecuritygroup/tree/v0.6.0) | ![avm-res-network-networksecuritygroup](docs/coverage/bars/azure-avm-res-network-networksecuritygroup.svg) 0 of 13 | 0 of 3 | 1 | not started |
| [`avm-res-storage-storageaccount`](https://github.com/Azure/terraform-azurerm-avm-res-storage-storageaccount/tree/v0.11.0) | ![avm-res-storage-storageaccount](docs/coverage/bars/azure-avm-res-storage-storageaccount.svg) 0 of 63 | 0 of 11 | 2 | not started |
| [`avm-res-keyvault-vault`](https://github.com/Azure/terraform-azurerm-avm-res-keyvault-vault/tree/v0.13.0) | ![avm-res-keyvault-vault](docs/coverage/bars/azure-avm-res-keyvault-vault.svg) 0 of 34 | 0 of 8 | 5 | not started |
| [`avm-res-compute-virtualmachine`](https://github.com/Azure/terraform-azurerm-avm-res-compute-virtualmachine/tree/v0.21.0) | ![avm-res-compute-virtualmachine](docs/coverage/bars/azure-avm-res-compute-virtualmachine.svg) 0 of 74 | 0 of 13 | 20 | not started |
| [`avm-res-resources-resourcegroup`](https://github.com/Azure/terraform-azurerm-avm-res-resources-resourcegroup/tree/v0.5.0) | ![avm-res-resources-resourcegroup](docs/coverage/bars/azure-avm-res-resources-resourcegroup.svg) 0 of 10 | 0 of 4 | 2 | not started |
| [`avm-res-managedidentity-userassignedidentity`](https://github.com/Azure/terraform-azurerm-avm-res-managedidentity-userassignedidentity/tree/v0.6.0) | ![avm-res-managedidentity-userassignedidentity](docs/coverage/bars/azure-avm-res-managedidentity-userassignedidentity.svg) 0 of 9 | 0 of 6 | 4 | not started |
| [`avm-res-operationalinsights-workspace`](https://github.com/Azure/terraform-azurerm-avm-res-operationalinsights-workspace/tree/v0.5.1) | ![avm-res-operationalinsights-workspace](docs/coverage/bars/azure-avm-res-operationalinsights-workspace.svg) 0 of 31 | 0 of 3 | 20 | not started |
| [`avm-res-network-routetable`](https://github.com/Azure/terraform-azurerm-avm-res-network-routetable/tree/v0.6.0) | ![avm-res-network-routetable](docs/coverage/bars/azure-avm-res-network-routetable.svg) 0 of 11 | 0 of 4 | 6 | not started |
| [`avm-res-network-natgateway`](https://github.com/Azure/terraform-azurerm-avm-res-network-natgateway/tree/v0.3.2) | ![avm-res-network-natgateway](docs/coverage/bars/azure-avm-res-network-natgateway.svg) 0 of 18 | 0 of 3 | 4 | not started |

Every module, variable and output: [`modules.csv`](docs/coverage/modules.csv), [`variables.csv`](docs/coverage/variables.csv), [`outputs.csv`](docs/coverage/outputs.csv), [`resource-types.csv`](docs/coverage/resource-types.csv). `task coverage` regenerates this section and those files; `task coverage-check` fails when they are out of date.
<!-- coverage:end -->

Licensed under Apache-2.0 (`LICENSE`); the charts are derived from Cloud
Foundation Fabric, Copyright Google LLC, Apache-2.0 (`NOTICE`).
