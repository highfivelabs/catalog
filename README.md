# catalog

Bundt's seed catalog: Packages that teams instantiate as components.
Today it holds the first Google Cloud Packages, Helm charts of Config
Connector objects ported from Cloud Foundation Fabric's Terraform modules,
and the first AWS Packages, Helm charts of AWS Controllers for Kubernetes
(ACK) objects ported from terraform-aws-modules, so a team moving from
those modules keeps its variables, its names and its outputs.

| Path | What |
| --- | --- |
| `docs/design.md` | how a fabric module becomes a Package: values, IAM, references, deletion, scope, kro or Helm, versioning, testing, the pilot's results, questions |
| `docs/gcp-inventory.md` | every fabric module against Config Connector v1.160.0, ranked, and the gaps for config-connector-extensions |
| `docs/aws.md` | the top terraform-aws-modules against ACK, ranked, the gaps for ack-extensions, and how the AWS charts differ from the Google Cloud ones (section 8) |
| `docs/coverage/` | how much of each tracked open-source module the catalog carries: CSVs per module, variable, output and resource type, SVG bars, and the method (`task coverage`) |
| `docs/migrating-from-terraform.md`, `examples/` | moving a Terraform module call to the catalog: the mapping, `catalogtool convert` (`task convert`), a worked example for each chart with its plan, and adopting resources that already exist |
| `docs/upstream-status.md`, `.github/workflows/upstream-watch.yml` | which tracked modules have a newer release than their pin, and what changed (`task upstream-watch`); a daily workflow keeps one tracking issue; `task upstream-bump` records a release as taken |
| `charts/gcp/<module>/`, `charts/aws/<module>/` | one chart per ported module, with its Bundt Package (`package.yaml`), README and tests |
| `charts/azure/<module>/` | one chart per ported Azure Verified Module, of Azure Service Operator objects (`docs/azure.md`, "8. Charts") |
| `upstream/modules.yaml` | every open-source Terraform module the catalog tracks (91 fabric modules, terraform-google-modules' kubernetes-engine beta-private-cluster, 40 terraform-aws-modules, 37 Azure Verified Modules): repository, path, pinned release and commit, licence, registry and module pages, and the chart that ports it |
| `charts/<cloud>/<chart>/upstream.yaml` | where one chart came from: the module, release, commit, licence and date synced |
| `lib/_kcc.tpl`, `lib/_ack.tpl`, `lib/_aso.tpl` | helpers every Google Cloud, AWS (ACK) and Azure chart carries a copy of (`hack/sync-lib.sh`) |
| `upstream/aws-kinds.yaml`, `crds/ack-extensions/` | Terraform AWS resource types mapped to ACK and ack-extensions kinds (read by `task coverage`); the ack-extensions CRDs the AWS charts render |
| `tools/catalogtool` | Config Connector CRDs to kubeconform schemas; Package checks; outputs evaluated against live objects |
| `Taskfile.yml` | the entry points: `task check`, `test`, `test-live`, `test-mock`, `test-mock-aws`, `inventory`, `upstream-check`, `coverage`, `coverage-check`, `coverage-verify`, `convert`, `examples-test`, `upstream-watch`, `upstream-bump`, `tools-test` (`task --list`) |
| `hack/test.sh`, `hack/ack.sh` | render tests (offline, seconds), behind `task test`; `hack/ack.sh` fetches the CRDs of the ACK controllers `UPSTREAM.md` pins |
| `hack/mock-apply.sh`, `hack/mock-apply-aws.sh`, `hack/live-apply.sh` | the fake-cloud (Google Cloud, AWS) and real-project applies (an offload VM, never a laptop), behind `task test-mock`, `task test-mock-aws` and `task test-live` |
| `hack/azure-live.sh` | the Azure charts applied to the Azure sandbox with Azure Service Operator on kind (an offload VM, keyless federation), behind `task test-live-azure` |
| `hack/inventory/run.sh` | regenerates the inventory's tables, behind `task inventory` |
| `UPSTREAM.md` | the fabric and Config Connector commits everything is pinned to, the tracked modules' licences, and how to move a pin |

```sh
task test                    # all charts; needs task, helm, kubeconform, go, git
task test CHART=gcs          # one chart
task test-update CHART=gcs   # accept a chart's new renders
task check                   # what CI runs: gofmt, vet, Go tests, task test, examples, coverage current, shellcheck, actionlint
```

Charts: `iam-service-account`, `gcs`, `net-vpc`, `net-cloudnat` (a Cloud
NAT and its router), `project` (partial),
`gke-cluster` (partial), a GKE cluster in Standard or Autopilot mode ported
from terraform-google-modules' kubernetes-engine `beta-private-cluster` and
its Autopilot twin, `secret-manager` (partial: global secrets, their
IAM and tag bindings; no versions or regional secrets), and
`cloudsql-instance` (partial: no password-bearing users yet), a Cloud SQL
instance with its replicas, databases and IAM users. On AWS, ported from
terraform-aws-modules to ACK objects: `vpc` (partial: no IPv6, flow logs
or VPN gateway yet), a VPC with its subnets, route tables, gateways,
network ACLs and subnet groups, `security-group` (partial: rules
without per-rule tags), `kms` (partial: no external keys), a key with the module's key
policy, aliases and grants, `s3-bucket` (partial: no lifecycle rules or
replication yet), a bucket with its configurations and policy. On Azure, ported
from Azure Verified Modules to Azure Service Operator objects:
`avm-res-resources-resourcegroup` (partial) and
`avm-res-network-virtualnetwork` (partial: subnets, peerings) and
`avm-res-storage-storageaccount` (partial: the account, containers, queues,
tables and shares) and `avm-res-keyvault-vault` (partial: the vault and its keys;
no secrets yet). Every chart links to
the open-source module it ports
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

**177 modules tracked**: 5 ported, 39 partial, 62 blocked, 71 not started. Green is ported, amber partial (some variables refused with a message that names the gap), dark grey blocked (a resource type of the module has no stable kind: none, or only an alpha one), light grey not started.

| Source | Modules | Bar | Variables covered |
| --- | ---: | --- | ---: |
| Google Cloud: Cloud Foundation Fabric and terraform-google-modules | 98 | ![gcp](docs/coverage/gcp.svg) | 476 of 1478 (32.2%) |
| AWS: terraform-aws-modules | 42 | ![aws](docs/coverage/aws.svg) | 289 of 2348 (12.3%) |
| Azure: Azure Verified Modules | 37 | ![azure](docs/coverage/azure.svg) | 156 of 1170 (13.3%) |
| **All** | **177** | | **921 of 4996 (18.4%)** |

### Google Cloud: Cloud Foundation Fabric and terraform-google-modules

4 ported, 24 partial, 61 blocked, 9 not started.

**Ported and partial**

| Module | Variables covered | Outputs | Resource types with a stable kind | Status |
| --- | --- | ---: | ---: | --- |
| [`project`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/project) ([chart](charts/gcp/project)) | ![project](docs/coverage/bars/gcp-project.svg) 33 of 58 | 9 of 27 | 41 of 49 | partial |
| [`iam-service-account`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/iam-service-account) ([chart](charts/gcp/iam-service-account)) | ![iam-service-account](docs/coverage/bars/gcp-iam-service-account.svg) 24 of 28 | 5 of 6 | 9 of 9 | partial |
| [`net-vpc`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpc) ([chart](charts/gcp/net-vpc)) | ![net-vpc](docs/coverage/bars/gcp-net-vpc.svg) 24 of 29 | 13 of 23 | 12 of 19 | partial |
| [`net-vpc-firewall`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpc-firewall) ([chart](charts/gcp/net-vpc-firewall)) | ![net-vpc-firewall](docs/coverage/bars/gcp-net-vpc-firewall.svg) 7 of 8 | 0 of 2 | 1 of 1 | partial |
| [`net-cloudnat`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-cloudnat) ([chart](charts/gcp/net-cloudnat)) | ![net-cloudnat](docs/coverage/bars/gcp-net-cloudnat.svg) 15 of 16 | 5 of 6 | 2 of 2 | partial |
| [`dns`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/dns) ([chart](charts/gcp/dns)) | ![dns](docs/coverage/bars/gcp-dns.svg) 8 of 9 | 4 of 6 | 3 of 3 | partial |
| [`kms`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/kms) ([chart](charts/gcp/kms)) | ![kms](docs/coverage/bars/gcp-kms.svg) 9 of 10 | 4 of 7 | 8 of 8 | partial |
| [`gcs`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gcs) ([chart](charts/gcp/gcs)) | ![gcs](docs/coverage/bars/gcp-gcs.svg) 30 of 36 | 5 of 7 | 8 of 12 | partial |
| [`artifact-registry`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/artifact-registry) ([chart](charts/gcp/artifact-registry)) | ![artifact-registry](docs/coverage/bars/gcp-artifact-registry.svg) 15 of 17 | 3 of 4 | 4 of 4 | partial |
| [`secret-manager`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/secret-manager) ([chart](charts/gcp/secret-manager)) | ![secret-manager](docs/coverage/bars/gcp-secret-manager.svg) 3 of 4 | 1 of 5 | 6 of 10 | partial |
| [`cloudsql-instance`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloudsql-instance) ([chart](charts/gcp/cloudsql-instance)) | ![cloudsql-instance](docs/coverage/bars/gcp-cloudsql-instance.svg) 31 of 35 | 14 of 17 | 4 of 4 | partial |
| [`gke-nodepool`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gke-nodepool) ([chart](charts/gcp/gke-nodepool)) | ![gke-nodepool](docs/coverage/bars/gcp-gke-nodepool.svg) 20 of 20 | 4 of 4 | 2 of 2 | partial |
| [`pubsub`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/pubsub) ([chart](charts/gcp/pubsub)) | ![pubsub](docs/coverage/bars/gcp-pubsub.svg) 13 of 14 | 3 of 6 | 7 of 7 | partial |
| [`vpc-sc`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/vpc-sc) ([chart](charts/gcp/vpc-sc)) | ![vpc-sc](docs/coverage/bars/gcp-vpc-sc.svg) 10 of 12 | 3 of 6 | 5 of 5 | partial |
| [`net-vpc-peering`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpc-peering) ([chart](charts/gcp/net-vpc-peering)) | ![net-vpc-peering](docs/coverage/bars/gcp-net-vpc-peering.svg) 7 of 7 | 0 of 2 | 1 of 1 | ported |
| [`cloud-identity-group`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloud-identity-group) ([chart](charts/gcp/cloud-identity-group)) | ![cloud-identity-group](docs/coverage/bars/gcp-cloud-identity-group.svg) 6 of 6 | 2 of 2 | 2 of 2 | ported |
| [`net-lb-int`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-lb-int) ([chart](charts/gcp/net-lb-int)) | ![net-lb-int](docs/coverage/bars/gcp-net-lb-int.svg) 14 of 15 | 8 of 13 | 6 of 6 | partial |
| [`service-directory`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/service-directory) ([chart](charts/gcp/service-directory)) | ![service-directory](docs/coverage/bars/gcp-service-directory.svg) 8 of 8 | 4 of 7 | 5 of 5 | partial |
| [`bigtable-instance`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/bigtable-instance) ([chart](charts/gcp/bigtable-instance)) | ![bigtable-instance](docs/coverage/bars/gcp-bigtable-instance.svg) 11 of 11 | 2 of 4 | 4 of 4 | partial |
| [`gke-hub`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gke-hub) ([chart](charts/gcp/gke-hub)) | ![gke-hub](docs/coverage/bars/gcp-gke-hub.svg) 7 of 8 | 1 of 1 | 3 of 3 | partial |
| [`source-repository`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/source-repository) ([chart](charts/gcp/source-repository)) | ![source-repository](docs/coverage/bars/gcp-source-repository.svg) 7 of 7 | 3 of 3 | 4 of 4 | partial |
| [`kubernetes-engine-beta-private-cluster`](https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/tree/v47.0.0/modules/beta-private-cluster) ([chart](charts/gcp/gke-cluster)) | ![kubernetes-engine-beta-private-cluster](docs/coverage/bars/gcp-kubernetes-engine-beta-private-cluster.svg) 137 of 162 | 30 of 36 | 0 of 0 | partial |
| [`network-firewall-rules`](https://github.com/terraform-google-modules/terraform-google-network/tree/v18.3.1/modules/firewall-rules) ([chart](charts/gcp/firewall-rules)) | ![network-firewall-rules](docs/coverage/bars/gcp-network-firewall-rules.svg) 5 of 5 | 2 of 2 | 0 of 0 | ported |
| [`network-network-firewall-policy`](https://github.com/terraform-google-modules/terraform-google-network/tree/v18.3.1/modules/network-firewall-policy) ([chart](charts/gcp/network-firewall-policy)) | ![network-network-firewall-policy](docs/coverage/bars/gcp-network-network-firewall-policy.svg) 6 of 8 | 3 of 3 | 0 of 0 | partial |
| [`network-hierarchical-firewall-policy`](https://github.com/terraform-google-modules/terraform-google-network/tree/v18.3.1/modules/hierarchical-firewall-policy) ([chart](charts/gcp/hierarchical-firewall-policy)) | ![network-hierarchical-firewall-policy](docs/coverage/bars/gcp-network-hierarchical-firewall-policy.svg) 6 of 6 | 3 of 3 | 0 of 0 | partial |
| [`folders`](https://github.com/terraform-google-modules/terraform-google-folders/tree/v5.2.0) ([chart](charts/gcp/folders)) | ![folders](docs/coverage/bars/gcp-folders.svg) 8 of 8 | 7 of 10 | 0 of 0 | ported |
| [`iam-folders-iam`](https://github.com/terraform-google-modules/terraform-google-iam/tree/v8.3.0/modules/folders_iam) ([chart](charts/gcp/folders-iam)) | ![iam-folders-iam](docs/coverage/bars/gcp-iam-folders-iam.svg) 4 of 4 | 3 of 3 | 0 of 0 | partial |
| [`org-policy-v2`](https://github.com/terraform-google-modules/terraform-google-org-policy/tree/v7.4.0/modules/org_policy_v2) ([chart](charts/gcp/org-policy-v2)) | ![org-policy-v2](docs/coverage/bars/gcp-org-policy-v2.svg) 8 of 8 | 3 of 3 | 0 of 0 | partial |

**Blocked: a resource type has no stable kind (first 10 of 61, by rank)**

| Module | Variables covered | Outputs | Resource types with a stable kind | Status |
| --- | --- | ---: | ---: | --- |
| [`folder`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/folder) | ![folder](docs/coverage/bars/gcp-folder.svg) 0 of 31 | 0 of 9 | 16 of 24 | blocked |
| [`organization`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/organization) | ![organization](docs/coverage/bars/gcp-organization.svg) 0 of 35 | 0 of 23 | 25 of 35 | blocked |
| [`gke-cluster-standard`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gke-cluster-standard) | ![gke-cluster-standard](docs/coverage/bars/gcp-gke-cluster-standard.svg) 0 of 25 | 0 of 15 | 2 of 6 | blocked |
| [`gke-cluster-autopilot`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gke-cluster-autopilot) | ![gke-cluster-autopilot](docs/coverage/bars/gcp-gke-cluster-autopilot.svg) 0 of 21 | 0 of 15 | 2 of 6 | blocked |
| [`bigquery-dataset`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/bigquery-dataset) | ![bigquery-dataset](docs/coverage/bars/gcp-bigquery-dataset.svg) 0 of 24 | 0 of 12 | 4 of 7 | blocked |
| [`cloud-run-v2`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloud-run-v2) | ![cloud-run-v2](docs/coverage/bars/gcp-cloud-run-v2.svg) 0 of 21 | 0 of 12 | 9 of 13 | blocked |
| [`billing-account`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/billing-account) | ![billing-account](docs/coverage/bars/gcp-billing-account.svg) 0 of 11 | 0 of 2 | 8 of 10 | blocked |
| [`logging-bucket`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/logging-bucket) | ![logging-bucket](docs/coverage/bars/gcp-logging-bucket.svg) 0 of 12 | 0 of 2 | 7 of 9 | blocked |
| [`net-firewall-policy`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-firewall-policy) | ![net-firewall-policy](docs/coverage/bars/gcp-net-firewall-policy.svg) 0 of 13 | 0 of 1 | 6 of 11 | blocked |
| [`project-factory`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/project-factory) | ![project-factory](docs/coverage/bars/gcp-project-factory.svg) 0 of 8 | 0 of 16 | 0 of 1 | blocked |

**Not started**

| Module | Variables covered | Outputs | Resource types with a stable kind | Status |
| --- | --- | ---: | ---: | --- |
| [`net-vpc-factory`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpc-factory) | ![net-vpc-factory](docs/coverage/bars/gcp-net-vpc-factory.svg) 0 of 4 | 0 of 3 | 0 of 0 | not started |
| [`net-lb-ext`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-lb-ext) | ![net-lb-ext](docs/coverage/bars/gcp-net-lb-ext.svg) 0 of 11 | 0 of 12 | 4 of 4 | not started |
| [`alloydb`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/alloydb) | ![alloydb](docs/coverage/bars/gcp-alloydb.svg) 0 of 33 | 0 of 30 | 4 of 4 | not started |
| [`net-vpn-static`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/net-vpn-static) | ![net-vpn-static](docs/coverage/bars/gcp-net-vpn-static.svg) 0 of 9 | 0 of 9 | 5 of 5 | not started |
| [`dataproc`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/dataproc) | ![dataproc](docs/coverage/bars/gcp-dataproc.svg) 0 of 9 | 0 of 2 | 3 of 3 | not started |
| [`datafusion`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/datafusion) | ![datafusion](docs/coverage/bars/gcp-datafusion.svg) 0 of 14 | 0 of 6 | 4 of 4 | not started |
| [`data-catalog-policy-tag`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/data-catalog-policy-tag) | ![data-catalog-policy-tag](docs/coverage/bars/gcp-data-catalog-policy-tag.svg) 0 of 12 | 0 of 2 | 6 of 6 | not started |
| [`projects-data-source`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/projects-data-source) | ![projects-data-source](docs/coverage/bars/gcp-projects-data-source.svg) 0 of 5 | 0 of 2 | 0 of 0 | not started |
| [`cloud-config-container`](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/cloud-config-container) | ![cloud-config-container](docs/coverage/bars/gcp-cloud-config-container.svg) 0 of 0 | 0 of 0 | 0 of 0 | not started |

### AWS: terraform-aws-modules

0 ported, 8 partial, 1 blocked, 33 not started.

**Ported and partial**

| Module | Variables covered | Outputs | Resource types with a stable kind | Status |
| --- | --- | ---: | ---: | --- |
| [`s3-bucket`](https://github.com/terraform-aws-modules/terraform-aws-s3-bucket/tree/v5.17.0) ([chart](charts/aws/s3-bucket)) | ![s3-bucket](docs/coverage/bars/aws-s3-bucket.svg) 27 of 78 | 8 of 21 | 38 of 45 | partial |
| [`vpc`](https://github.com/terraform-aws-modules/terraform-aws-vpc/tree/v6.7.3) ([chart](charts/aws/vpc)) | ![vpc](docs/coverage/bars/aws-vpc.svg) 109 of 236 | 53 of 119 | 24 of 35 | partial |
| [`kms`](https://github.com/terraform-aws-modules/terraform-aws-kms/tree/v4.2.2) ([chart](charts/aws/kms)) | ![kms](docs/coverage/bars/aws-kms.svg) 30 of 41 | 4 of 9 | 3 of 6 | partial |
| [`security-group`](https://github.com/terraform-aws-modules/terraform-aws-security-group/tree/v6.0.0) ([chart](charts/aws/security-group)) | ![security-group](docs/coverage/bars/aws-security-group.svg) 10 of 14 | 5 of 5 | 4 of 5 | partial |
| [`acm`](https://github.com/terraform-aws-modules/terraform-aws-acm/tree/v6.3.1) ([chart](charts/aws/acm)) | ![acm](docs/coverage/bars/aws-acm.svg) 23 of 24 | 7 of 7 | 2 of 3 | partial |
| [`ec2-instance`](https://github.com/terraform-aws-modules/terraform-aws-ec2-instance/tree/v6.4.1) ([chart](charts/aws/ec2-instance)) | ![ec2-instance](docs/coverage/bars/aws-ec2-instance.svg) 53 of 83 | 20 of 30 | 8 of 12 | partial |
| [`iam-role`](https://github.com/terraform-aws-modules/terraform-aws-iam/tree/v6.8.2/modules/iam-role) ([chart](charts/aws/iam-role)) | ![iam-role](docs/coverage/bars/aws-iam-role.svg) 31 of 31 | 7 of 7 | 4 of 4 | partial |
| [`iam-policy`](https://github.com/terraform-aws-modules/terraform-aws-iam/tree/v6.8.2/modules/iam-policy) ([chart](charts/aws/iam-policy)) | ![iam-policy](docs/coverage/bars/aws-iam-policy.svg) 6 of 7 | 4 of 4 | 1 of 1 | partial |

**Blocked: a resource type has no stable kind**

| Module | Variables covered | Outputs | Resource types with a stable kind | Status |
| --- | --- | ---: | ---: | --- |
| [`iam`](https://github.com/terraform-aws-modules/terraform-aws-iam/tree/v6.8.2) | ![iam](docs/coverage/bars/aws-iam.svg) 0 of 0 | 0 of 0 | 11 of 17 | blocked |

**Not started (first 10 of 33, by rank)**

| Module | Variables covered | Outputs | Resource types | Status |
| --- | --- | ---: | ---: | --- |
| [`eks`](https://github.com/terraform-aws-modules/terraform-aws-eks/tree/v21.29.0) | ![eks](docs/coverage/bars/aws-eks.svg) 0 of 108 | 0 of 41 | 30 | not started |
| [`lambda`](https://github.com/terraform-aws-modules/terraform-aws-lambda/tree/v8.13.0) | ![lambda](docs/coverage/bars/aws-lambda.svg) 0 of 141 | 0 of 36 | 21 | not started |
| [`rds`](https://github.com/terraform-aws-modules/terraform-aws-rds/tree/v7.2.2) | ![rds](docs/coverage/bars/aws-rds.svg) 0 of 111 | 0 of 34 | 10 | not started |
| [`rds-aurora`](https://github.com/terraform-aws-modules/terraform-aws-rds-aurora/tree/v10.4.2) | ![rds-aurora](docs/coverage/bars/aws-rds-aurora.svg) 0 of 114 | 0 of 33 | 21 | not started |
| [`sqs`](https://github.com/terraform-aws-modules/terraform-aws-sqs/tree/v5.2.2) | ![sqs](docs/coverage/bars/aws-sqs.svg) 0 of 42 | 0 of 10 | 4 | not started |
| [`route53`](https://github.com/terraform-aws-modules/terraform-aws-route53/tree/v6.5.1) | ![route53](docs/coverage/bars/aws-route53.svg) 0 of 22 | 0 of 16 | 16 | not started |
| [`ecs`](https://github.com/terraform-aws-modules/terraform-aws-ecs/tree/v7.6.1) | ![ecs](docs/coverage/bars/aws-ecs.svg) 0 of 60 | 0 of 20 | 18 | not started |
| [`alb`](https://github.com/terraform-aws-modules/terraform-aws-alb/tree/v10.5.1) | ![alb](docs/coverage/bars/aws-alb.svg) 0 of 50 | 0 of 11 | 14 | not started |
| [`dynamodb-table`](https://github.com/terraform-aws-modules/terraform-aws-dynamodb-table/tree/v5.5.2) | ![dynamodb-table](docs/coverage/bars/aws-dynamodb-table.svg) 0 of 39 | 0 of 8 | 4 | not started |
| [`eventbridge`](https://github.com/terraform-aws-modules/terraform-aws-eventbridge/tree/v4.3.3) | ![eventbridge](docs/coverage/bars/aws-eventbridge.svg) 0 of 83 | 0 of 34 | 18 | not started |

### Azure: Azure Verified Modules

1 ported, 7 partial, 0 blocked, 29 not started.

**Ported and partial**

| Module | Variables covered | Outputs | Resource types | Status |
| --- | --- | ---: | ---: | --- |
| [`avm-res-network-virtualnetwork`](https://github.com/Azure/terraform-azurerm-avm-res-network-virtualnetwork/tree/v0.23.0) ([chart](charts/azure/avm-res-network-virtualnetwork)) | ![avm-res-network-virtualnetwork](docs/coverage/bars/azure-avm-res-network-virtualnetwork.svg) 19 of 22 | 5 of 6 | 5 | partial |
| [`avm-res-network-networksecuritygroup`](https://github.com/Azure/terraform-azurerm-avm-res-network-networksecuritygroup/tree/v0.6.0) ([chart](charts/azure/avm-res-network-networksecuritygroup)) | ![avm-res-network-networksecuritygroup](docs/coverage/bars/azure-avm-res-network-networksecuritygroup.svg) 9 of 13 | 3 of 3 | 1 | partial |
| [`avm-res-storage-storageaccount`](https://github.com/Azure/terraform-azurerm-avm-res-storage-storageaccount/tree/v0.11.0) ([chart](charts/azure/avm-res-storage-storageaccount)) | ![avm-res-storage-storageaccount](docs/coverage/bars/azure-avm-res-storage-storageaccount.svg) 49 of 63 | 7 of 11 | 2 | partial |
| [`avm-res-keyvault-vault`](https://github.com/Azure/terraform-azurerm-avm-res-keyvault-vault/tree/v0.13.0) ([chart](charts/azure/avm-res-keyvault-vault)) | ![avm-res-keyvault-vault](docs/coverage/bars/azure-avm-res-keyvault-vault.svg) 24 of 34 | 5 of 8 | 5 | partial |
| [`avm-res-resources-resourcegroup`](https://github.com/Azure/terraform-azurerm-avm-res-resources-resourcegroup/tree/v0.5.0) ([chart](charts/azure/avm-res-resources-resourcegroup)) | ![avm-res-resources-resourcegroup](docs/coverage/bars/azure-avm-res-resources-resourcegroup.svg) 7 of 10 | 3 of 4 | 2 | partial |
| [`avm-res-network-routetable`](https://github.com/Azure/terraform-azurerm-avm-res-network-routetable/tree/v0.6.0) ([chart](charts/azure/avm-res-network-routetable)) | ![avm-res-network-routetable](docs/coverage/bars/azure-avm-res-network-routetable.svg) 10 of 11 | 3 of 4 | 6 | partial |
| [`avm-res-network-natgateway`](https://github.com/Azure/terraform-azurerm-avm-res-network-natgateway/tree/v0.3.2) ([chart](charts/azure/avm-res-network-natgateway)) | ![avm-res-network-natgateway](docs/coverage/bars/azure-avm-res-network-natgateway.svg) 17 of 18 | 2 of 3 | 4 | partial |
| [`avm-res-network-publicipaddress`](https://github.com/Azure/terraform-azurerm-avm-res-network-publicipaddress/tree/v0.2.1) ([chart](charts/azure/avm-res-network-publicipaddress)) | ![avm-res-network-publicipaddress](docs/coverage/bars/azure-avm-res-network-publicipaddress.svg) 21 of 21 | 4 of 4 | 4 | ported |

**Not started (first 10 of 29, by rank)**

| Module | Variables covered | Outputs | Resource types | Status |
| --- | --- | ---: | ---: | --- |
| [`avm-res-compute-virtualmachine`](https://github.com/Azure/terraform-azurerm-avm-res-compute-virtualmachine/tree/v0.21.0) | ![avm-res-compute-virtualmachine](docs/coverage/bars/azure-avm-res-compute-virtualmachine.svg) 0 of 74 | 0 of 13 | 20 | not started |
| [`avm-res-managedidentity-userassignedidentity`](https://github.com/Azure/terraform-azurerm-avm-res-managedidentity-userassignedidentity/tree/v0.6.0) | ![avm-res-managedidentity-userassignedidentity](docs/coverage/bars/azure-avm-res-managedidentity-userassignedidentity.svg) 0 of 9 | 0 of 6 | 4 | not started |
| [`avm-res-operationalinsights-workspace`](https://github.com/Azure/terraform-azurerm-avm-res-operationalinsights-workspace/tree/v0.5.1) | ![avm-res-operationalinsights-workspace](docs/coverage/bars/azure-avm-res-operationalinsights-workspace.svg) 0 of 31 | 0 of 3 | 20 | not started |
| [`avm-res-network-privatednszone`](https://github.com/Azure/terraform-azurerm-avm-res-network-privatednszone/tree/v0.6.0) | ![avm-res-network-privatednszone](docs/coverage/bars/azure-avm-res-network-privatednszone.svg) 0 of 19 | 0 of 12 | 12 | not started |
| [`avm-res-network-loadbalancer`](https://github.com/Azure/terraform-azurerm-avm-res-network-loadbalancer/tree/v0.5.0) | ![avm-res-network-loadbalancer](docs/coverage/bars/azure-avm-res-network-loadbalancer.svg) 0 of 23 | 0 of 7 | 13 | not started |
| [`avm-res-containerregistry-registry`](https://github.com/Azure/terraform-azurerm-avm-res-containerregistry-registry/tree/v0.9.0) | ![avm-res-containerregistry-registry](docs/coverage/bars/azure-avm-res-containerregistry-registry.svg) 0 of 35 | 0 of 12 | 10 | not started |
| [`avm-res-network-firewallpolicy`](https://github.com/Azure/terraform-azurerm-avm-res-network-firewallpolicy/tree/v0.3.4) | ![avm-res-network-firewallpolicy](docs/coverage/bars/azure-avm-res-network-firewallpolicy.svg) 0 of 22 | 0 of 2 | 5 | not started |
| [`avm-res-containerservice-managedcluster`](https://github.com/Azure/terraform-azurerm-avm-res-containerservice-managedcluster/tree/v0.9.0) | ![avm-res-containerservice-managedcluster](docs/coverage/bars/azure-avm-res-containerservice-managedcluster.svg) 0 of 73 | 0 of 26 | 3 | not started |
| [`avm-res-dbforpostgresql-flexibleserver`](https://github.com/Azure/terraform-azurerm-avm-res-dbforpostgresql-flexibleserver/tree/v0.2.3) | ![avm-res-dbforpostgresql-flexibleserver](docs/coverage/bars/azure-avm-res-dbforpostgresql-flexibleserver.svg) 0 of 40 | 0 of 6 | 11 | not started |
| [`avm-res-cognitiveservices-account`](https://github.com/Azure/terraform-azurerm-avm-res-cognitiveservices-account/tree/v0.11.1) | ![avm-res-cognitiveservices-account](docs/coverage/bars/azure-avm-res-cognitiveservices-account.svg) 0 of 41 | 0 of 11 | 9 | not started |

Every module, variable and output: [`modules.csv`](docs/coverage/modules.csv), [`variables.csv`](docs/coverage/variables.csv), [`outputs.csv`](docs/coverage/outputs.csv), [`resource-types.csv`](docs/coverage/resource-types.csv). `task coverage` regenerates this section and those files; `task coverage-check` fails when they are out of date.
<!-- coverage:end -->

Licensed under Apache-2.0 (`LICENSE`); the charts are derived from Cloud
Foundation Fabric, Copyright Google LLC, Apache-2.0 (`NOTICE`).
