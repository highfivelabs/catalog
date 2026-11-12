# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Case (a): the unit's source is an open-source module itself, Cloud
# Foundation Fabric's net-vpc, so the module is the root of this unit's
# state and the unit maps to the catalog's net-vpc chart like a module
# call would. The same network as fixtures/shared-vpc's module.vpc.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "git::https://github.com/GoogleCloudPlatform/cloud-foundation-fabric.git//modules/net-vpc?ref=v60.0.0"
}

locals {
  prefix  = include.root.locals.prefix
  members = include.root.locals.env.locals.members
}

inputs = {
  name            = "${local.prefix}-shared"
  description     = "offramp fixture: shared VPC"
  routing_mode    = "GLOBAL"
  shared_vpc_host = false

  subnets = [
    {
      name          = "${local.prefix}-gke"
      region        = include.root.locals.region
      ip_cidr_range = "10.10.0.0/24"
      description   = "GKE nodes"
      secondary_ip_ranges = {
        pods     = { ip_cidr_range = "10.20.0.0/20" }
        services = { ip_cidr_range = "10.30.0.0/24" }
      }
      iam = {
        "roles/compute.networkUser" = local.members
      }
    },
    {
      name          = "${local.prefix}-apps"
      region        = include.root.locals.region
      ip_cidr_range = "10.10.1.0/24"
      description   = "application VMs and serverless connectors"
      flow_logs_config = {
        aggregation_interval = "INTERVAL_10_MIN"
        flow_sampling        = 0.5
        metadata             = "INCLUDE_ALL_METADATA"
      }
      iam_bindings_additive = {
        for i, m in local.members : "network-user-${i}" => {
          member = m
          role   = "roles/compute.networkUser"
        }
      }
    },
  ]
}
