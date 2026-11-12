# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Case (a), from the Terraform Registry (tfr://): terraform-google-modules'
# firewall-rules, reading the network's name from the vpc unit's outputs.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "tfr:///terraform-google-modules/network/google//modules/firewall-rules?version=18.3.1"
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    name = "mock-network"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

locals {
  prefix = include.root.locals.prefix
}

inputs = {
  network_name = dependency.vpc.outputs.name

  ingress_rules = [
    {
      name          = "${local.prefix}-allow-iap-ssh"
      description   = "SSH through Identity-Aware Proxy"
      source_ranges = ["35.235.240.0/20"]
      target_tags   = ["ssh"]
      allow         = [{ protocol = "tcp", ports = ["22"] }]
    },
    {
      name          = "${local.prefix}-allow-internal"
      source_ranges = ["10.10.0.0/16", "10.20.0.0/20"]
      allow = [
        { protocol = "tcp" },
        { protocol = "udp" },
        { protocol = "icmp" },
      ]
    },
  ]

  egress_rules = [
    {
      name               = "${local.prefix}-deny-smtp"
      priority           = 900
      destination_ranges = ["0.0.0.0/0"]
      deny               = [{ protocol = "tcp", ports = ["25"] }]
    },
  ]
}
