# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Case (a), from GitHub over git: terraform-google-modules'
# network-firewall-policy, attached to the vpc unit's network by its ID.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "git::https://github.com/terraform-google-modules/terraform-google-network.git//modules/network-firewall-policy?ref=v18.3.1"
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    id = "projects/mock/global/networks/mock"
  }
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

inputs = {
  policy_name     = "${local.env.locals.prefix}-policy"
  description     = "offramp fixture: global network firewall policy"
  target_vpcs_map = { shared = dependency.vpc.outputs.id }

  rules = [
    {
      priority  = 1000
      direction = "INGRESS"
      action    = "allow"
      rule_name = "allow-health-checks"
      match = {
        src_ip_ranges  = ["35.191.0.0/16", "130.211.0.0/22"]
        layer4_configs = [{ ip_protocol = "tcp", ports = ["80", "443"] }]
      }
    },
    {
      priority  = 2000
      direction = "EGRESS"
      action    = "deny"
      rule_name = "deny-telnet"
      match = {
        dest_ip_ranges = ["0.0.0.0/0"]
        layer4_configs = [{ ip_protocol = "tcp", ports = ["23"] }]
      }
    },
  ]
}
