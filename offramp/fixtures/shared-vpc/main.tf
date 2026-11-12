# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Shape 3: a shared VPC, built only from published open-source modules,
# each pinned to an exact release. A network with two subnets (one with
# secondary ranges for GKE, one with flow logs), subnet-level IAM (an
# authoritative binding on the GKE subnet, additive members on the apps
# subnet), classic firewall rules, and a global network firewall policy
# attached to the network.
#
# Each module call has a catalog chart that ports the same module at the
# same release, so the call's arguments are the chart's values unchanged:
#
#   module.vpc                      fabric net-vpc v60.0.0                  charts/gcp/net-vpc
#   module.firewall_rules           terraform-google-modules network
#                                   //modules/firewall-rules 18.3.1         charts/gcp/firewall-rules
#   module.network_firewall_policy  terraform-google-modules network
#                                   //modules/network-firewall-policy 18.3.1 charts/gcp/network-firewall-policy
#
# The network is Cloud Foundation Fabric's because the catalog's network
# chart ports fabric's net-vpc; the firewall modules are
# terraform-google-modules', the family in use.
#
# Shared VPC host enablement (`shared_vpc_host = true`) needs
# roles/compute.xpnAdmin on the folder or organization, which the live-test
# account does not hold; it is a variable so the shape runs without it.

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.10.0, < 9"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  gke_subnet  = "${var.prefix}-gke"
  apps_subnet = "${var.prefix}-apps"
}

module "vpc" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v60.0.0"

  project_id      = var.project_id
  name            = "${var.prefix}-shared"
  description     = "offramp fixture: shared VPC"
  routing_mode    = "GLOBAL"
  shared_vpc_host = var.shared_vpc_host

  subnets = [
    {
      name          = local.gke_subnet
      region        = var.region
      ip_cidr_range = "10.10.0.0/24"
      description   = "GKE nodes"
      secondary_ip_ranges = {
        pods     = { ip_cidr_range = "10.20.0.0/20" }
        services = { ip_cidr_range = "10.30.0.0/24" }
      }
      # Authoritative for the role: google_compute_subnetwork_iam_binding.
      iam = {
        "roles/compute.networkUser" = var.gke_subnet_users
      }
    },
    {
      name          = local.apps_subnet
      region        = var.region
      ip_cidr_range = "10.10.1.0/24"
      description   = "application VMs and serverless connectors"
      flow_logs_config = {
        aggregation_interval = "INTERVAL_10_MIN"
        flow_sampling        = 0.5
        metadata             = "INCLUDE_ALL_METADATA"
      }
      # Additive: one google_compute_subnetwork_iam_member each.
      iam_bindings_additive = {
        for i, m in var.apps_subnet_users : "network-user-${i}" => {
          member = m
          role   = "roles/compute.networkUser"
        }
      }
    },
  ]
}

module "firewall_rules" {
  source  = "terraform-google-modules/network/google//modules/firewall-rules"
  version = "18.3.1"

  project_id   = var.project_id
  network_name = module.vpc.name

  ingress_rules = [
    {
      name          = "${var.prefix}-allow-iap-ssh"
      description   = "SSH through Identity-Aware Proxy"
      source_ranges = ["35.235.240.0/20"]
      target_tags   = ["ssh"]
      allow         = [{ protocol = "tcp", ports = ["22"] }]
    },
    {
      name          = "${var.prefix}-allow-internal"
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
      name               = "${var.prefix}-deny-smtp"
      priority           = 900
      destination_ranges = ["0.0.0.0/0"]
      deny               = [{ protocol = "tcp", ports = ["25"] }]
    },
  ]
}

module "network_firewall_policy" {
  source  = "terraform-google-modules/network/google//modules/network-firewall-policy"
  version = "18.3.1"

  project_id  = var.project_id
  policy_name = "${var.prefix}-policy"
  description = "offramp fixture: global network firewall policy"
  # A map, not target_vpcs: the module keys target_vpcs by the network's
  # ID, unknown until the network exists, which for_each refuses.
  target_vpcs_map = { shared = module.vpc.id }

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
