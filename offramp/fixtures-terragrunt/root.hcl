# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# The estate's root configuration, included by every unit through
# find_in_parent_folders("root.hcl"), the way most Terragrunt estates are
# laid out: one remote state bucket, the provider generated into every
# unit, and the inputs every unit shares. Each environment's env.hcl
# names its project and the prefix of its resources.

locals {
  env        = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  project_id = local.env.locals.project_id
  prefix     = local.env.locals.prefix
  region     = "us-central1"
}

remote_state {
  backend = "gcs"
  config = {
    bucket   = "${local.project_id}-tfstate"
    prefix   = path_relative_to_include()
    project  = local.project_id
    location = "US"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "google" {
      project = "${local.project_id}"
      region  = "${local.region}"
    }
    provider "google-beta" {
      project = "${local.project_id}"
      region  = "${local.region}"
    }
  EOF
}

inputs = {
  project_id = local.project_id
  region     = local.region
}
