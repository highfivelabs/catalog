# Examples: Terraform to Bundt

A Terraform module call as a team has it today, and the Bundt documents that
replace it, for every ported chart. Read `docs/migrating-from-terraform.md`.

```sh
task convert -- examples/gcs/main.tf --tfvars examples/gcs/terraform.tfvars          # bundt.yaml
task convert -- examples/gcs/main.tf --tfvars examples/gcs/terraform.tfvars --plan   # plan.txt
task examples-test                                                                    # check them all
```

| Directory | Files |
| --- | --- |
| `artifact-registry/`, `cloudsql-instance/`, `dns/`, `gcs/`, `iam-service-account/`, `kms/`, `net-cloudnat/`, `net-vpc-firewall/`, `net-vpc-peering/`, `net-vpc/`, `project/`, `pubsub/`, `secret-manager/` | one module call each |
| `wiring/` | two calls, one using the other's output |
| `names/` | `namePrefix: ${instance.name}` on every component, and the plans of two Instances (`convert.args`, `convert-prod.args`) |
| `gaps/` | what the converter says about what it cannot carry |

Each holds `main.tf` and `terraform.tfvars` (Terraform), `bundt.yaml` (the
Template, Stack and Instance), `messages.txt` (the converter's messages),
`plan.txt` (the plan preview) and `rendered.yaml` (the Config Connector
objects). The Terraform is modelled on the module READMEs of Cloud
Foundation Fabric (Apache-2.0, Copyright Google LLC; see `NOTICE`).
