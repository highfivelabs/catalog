# The Terraform offramp

A prototype of a no-op, day-one import from Terraform into Bundt on Google
Cloud: from a Terraform state, or from a scan of a folder or organization,
to Config Connector objects that adopt each resource as it is, and to the
Bundt documents that hold them. The design, the live results and the
questions for the builder are in Bundt, `drafts/tf-offramp/README.md`
(branch `tf-offramp`).

| Path | What |
| --- | --- |
| `fixtures/folders` | shape 1: folders, folder IAM, organization policies, a hierarchical firewall policy |
| `fixtures/platform-project` | shape 2: a platform project (project-factory, baseline accounts, IAM) with one app inside it (`app.tf`) |
| `fixtures/shared-vpc` | shape 3: a network, subnets with secondary ranges, firewall rules, a network firewall policy, subnet IAM |
| `fixtures/gke` | shape 4: kubernetes-engine `beta-private-cluster` (two Spot node pools) or `beta-autopilot-private-cluster`; `gke-cluster.values.yaml` is its module block as the catalog's gke-cluster chart's values |
| `cmd/offramp`, `internal/offramp` | the converter |
| `hack/scan.sh` | the scan: Cloud Asset Inventory, else the services' list calls |
| `hack/live.sh` | the live proof of one shape |
| `hack/validate.sh` | `terraform fmt`, `init` and `validate` of every fixture |

## The converter

```sh
go build -o ../bin/offramp ./cmd/offramp

# From a state. --kcc is a Config Connector checkout at the release the
# cluster runs (its config/crds/resources and config/servicemappings).
../bin/offramp state --kcc ~/src/k8s-config-connector --state terraform.tfstate \
  --out out --name shared-vpc --team platform --env prod --target infra

# From a scan: the assets, the names to export, Config Connector's export,
# then the same grouping.
hack/scan.sh --scope folders/123 --billing-project my-project >assets.json
../bin/offramp names --assets assets.json >names.txt
while read -r n; do config-connector export "$n" --iam-format policymember --output "export/$(echo "$n" | md5sum | cut -c1-8).yaml"; done <names.txt
../bin/offramp krm --krm export --out out-scan

# What one has that the other lacks, field by field.
../bin/offramp compare out/krm/all.yaml out-scan/krm/all.yaml
```

`--iam-format policymember` matters: `config-connector export`'s default is
an `IAMPolicy` per resource, which owns the whole policy and which Bundt
never applies.

Output (`--out`): `krm/all.yaml` (every object), `packages/<package>/manifests/`
(each component's objects, its Package's files), `bundt/prereqs.yaml` (Team,
Target), `bundt/catalog.yaml` (Packages and the Template), `bundt/record.yaml`
(Environment, Stack, Instance) and `report.md` (what became what, and every
finding). The output shape is a draft; the design names its open questions.

## Tests

`task offramp-test` (gofmt, vet, `go test`). `task offramp-validate` checks
the fixtures on an offload VM. `task offramp-live SHAPE=shared-vpc` runs the
live proof in hfl-dev-514205 as `cce-live-tests@`; the other shapes need the
grants the design lists.
