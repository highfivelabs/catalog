# Synthetic states

Not a Terraform apply's output. Each `terraform.tfstate` here was made by
`offramp synth` from the fixture of the same name and its
`terraform.tfvars`: Terraform 1.17.1 planned the root module offline (a
token that is not one, a fake GKE server config and service-agent reads),
repeatedly, and the plan's values were written as a state. Terraform
evaluated the modules, so every value they compute from their inputs is
Terraform's own; only what the cloud assigns (folder numbers, a policy's
ID, self links, a project number) is made up, deterministically. Fields the
cloud fills with server-side defaults are absent, unlike in a real state.

The shapes whose permissions are missing (folders, platform-project, gke:
register items O33 and O34) are tested against these. shared-vpc is also
tested against a real state, `../live/shared-vpc-modules/`.

Regenerate one with:

    offramp synth --root offramp/fixtures/<shape> --tfvars <this dir>/<shape>/terraform.tfvars \
      --terraform terraform --project ofr-test-project --out <this dir>/<shape>/terraform.tfstate
