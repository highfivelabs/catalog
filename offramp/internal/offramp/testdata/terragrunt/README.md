# Terragrunt estate states

The states of the units of `offramp/fixtures-terragrunt`, by unit path,
and what Terragrunt itself made of three units.

- `network/<unit>/terraform.tfstate`: the live run ofr-11110114-2801's state
  (`../live/shared-vpc-modules/`, a real `terraform apply` in the
  live-test project, recorded as `my-dev-project`), split by module call
  and re-rooted: the resources of `module.vpc` are the `network/vpc` unit's, with the `module.vpc.` prefix
  removed from their addresses and their dependencies. That is what
  Terraform records when the module is the root of a unit's state, as it
  is under Terragrunt. Dependencies on another call's resources are dropped:
  across units, Terragrunt's dependency blocks give the order. Outputs are
  left empty.
- `gke/gke-platform/terraform.tfstate`: a synthetic state (`offramp synth`,
  see `../synthetic/README.md`) of the wrapper module
  `fixtures-terragrunt/modules/gke-platform` with the unit's inputs as
  `terraform.tfvars`. Made with Terraform 1.17.1:

      offramp synth --root offramp/fixtures-terragrunt/modules/gke-platform \
        --tfvars <this dir>/gke/gke-platform/terraform.tfvars \
        --terraform terraform --project ofr-test-project \
        --out <this dir>/gke/gke-platform/terraform.tfstate

- The `platform/project` unit reads `../synthetic/platform-project/`: its
  source is `fixtures/platform-project` and its inputs are that state's
  tfvars.
- `render-json/<unit>.json`: `terragrunt render-json` (Terragrunt v0.48.6)
  of the units with no dependency block (render-json would read a
  dependency's state), trimmed to the source, the remote state and the
  inputs, the estate's absolute path written `<estate>`. The offramp's
  static reading must give the same (`TestTerragruntMatchesRenderJSON`).
