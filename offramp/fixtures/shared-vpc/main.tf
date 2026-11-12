# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Shape 3: a shared VPC. A network with two subnets (one with secondary
# ranges for GKE), classic firewall rules, a global network firewall policy
# attached to the network, and subnet-level IAM: the grants that let
# service projects (or their deployers) use one subnet each.
#
# Shared VPC host enablement (`shared_vpc_host = true`) needs
# roles/compute.xpnAdmin on the folder or organization, which the live-test
# account does not hold; it is a variable so the shape runs without it
# (see the design, "Grants").

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.0, < 9"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 8.0, < 9"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

locals {
  gke_subnet  = "${var.prefix}-gke"
  apps_subnet = "${var.prefix}-apps"
}

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 18.3"

  project_id      = var.project_id
  network_name    = "${var.prefix}-shared"
  routing_mode    = "GLOBAL"
  shared_vpc_host = var.shared_vpc_host
  description     = "offramp fixture: shared VPC"

  subnets = [
    {
      subnet_name           = local.gke_subnet
      subnet_ip             = "10.10.0.0/24"
      subnet_region         = var.region
      subnet_private_access = "true"
      description           = "GKE nodes"
    },
    {
      subnet_name               = local.apps_subnet
      subnet_ip                 = "10.10.1.0/24"
      subnet_region             = var.region
      subnet_private_access     = "true"
      subnet_flow_logs          = "true"
      subnet_flow_logs_interval = "INTERVAL_10_MIN"
      subnet_flow_logs_sampling = "0.5"
      subnet_flow_logs_metadata = "INCLUDE_ALL_METADATA"
      description               = "application VMs and serverless connectors"
    },
  ]

  secondary_ranges = {
    (local.gke_subnet) = [
      { range_name = "pods", ip_cidr_range = "10.20.0.0/20" },
      { range_name = "services", ip_cidr_range = "10.30.0.0/24" },
    ]
  }

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
  version = "~> 18.3"

  project_id  = var.project_id
  policy_name = "${var.prefix}-policy"
  description = "offramp fixture: global network firewall policy"
  # A map, not target_vpcs: the module keys target_vpcs by the network's
  # ID, unknown until the network exists, which for_each refuses.
  target_vpcs_map = { shared = module.vpc.network_id }

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

# Subnet-level permissions: one additive grant per member on the apps
# subnet, and one authoritative binding (per role) on the GKE subnet.
resource "google_compute_subnetwork_iam_member" "apps_network_users" {
  for_each   = toset(var.apps_subnet_users)
  project    = var.project_id
  region     = var.region
  subnetwork = module.vpc.subnets["${var.region}/${local.apps_subnet}"].name
  role       = "roles/compute.networkUser"
  member     = each.value
}

resource "google_compute_subnetwork_iam_binding" "gke_network_users" {
  project    = var.project_id
  region     = var.region
  subnetwork = module.vpc.subnets["${var.region}/${local.gke_subnet}"].name
  role       = "roles/compute.networkUser"
  members    = var.gke_subnet_users
}
