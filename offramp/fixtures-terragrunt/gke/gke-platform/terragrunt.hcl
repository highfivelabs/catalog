# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Case (b): the unit's source is the team's own root module
# (modules/gke-platform), which wraps open-source modules. The offramp
# descends into it and maps each module call inside to its chart; the
# wrapper's own resources stay a frozen Package, each listed.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  # Terragrunt's double slash: copy modules/, run in modules/gke-platform.
  source = "${get_parent_terragrunt_dir("root")}/modules//gke-platform"
}

inputs = {
  prefix     = include.root.locals.prefix
  owner      = "platform"
  nodes_cidr = "10.40.0.0/24"
}
