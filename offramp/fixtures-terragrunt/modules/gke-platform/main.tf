# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# A team's own root module wrapping open-source modules, the second case a
# Terragrunt unit takes: the unit's source is this directory, not a
# published module. It calls Cloud Foundation Fabric's net-vpc and
# terraform-google-modules' beta-private-cluster (each with a catalog
# chart), and declares a few resources of its own that no module makes:
# the firewall rule a private cluster's control plane needs to reach
# admission webhooks, and a workload service account with its grant.
#
#   module.network   fabric net-vpc v60.0.0                               charts/gcp/net-vpc
#   module.cluster   kubernetes-engine//modules/beta-private-cluster 47.0.0  charts/gcp/gke-cluster
#   google_compute_firewall.master_webhooks, google_service_account.workload,
#   google_project_iam_member.workload_log_writer                         the wrapper's own

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.10.0, < 9"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 8.10.0, < 9"
    }
  }
}

locals {
  subnet = "${var.prefix}-gke"
}

module "network" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v60.0.0"

  project_id   = var.project_id
  name         = "${var.prefix}-gke"
  routing_mode = "REGIONAL"
  subnets = [{
    name          = local.subnet
    region        = var.region
    ip_cidr_range = var.nodes_cidr
    secondary_ip_ranges = {
      pods     = { ip_cidr_range = var.pods_cidr }
      services = { ip_cidr_range = var.services_cidr }
    }
  }]
}

module "cluster" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/beta-private-cluster"
  version = "47.0.0"

  project_id        = var.project_id
  name              = "${var.prefix}-std"
  regional          = false
  region            = var.region
  zones             = ["${var.region}-a"]
  network           = module.network.name
  subnetwork        = local.subnet
  ip_range_pods     = "pods"
  ip_range_services = "services"

  enable_private_nodes    = true
  enable_private_endpoint = false
  master_ipv4_cidr_block  = var.master_cidr
  master_authorized_networks = [
    { cidr_block = var.nodes_cidr, display_name = "nodes" },
  ]

  release_channel          = "REGULAR"
  deletion_protection      = false
  remove_default_node_pool = true
  create_service_account   = false
  grant_registry_access    = false
  gateway_api_channel      = "CHANNEL_STANDARD"
  enable_cost_allocation   = true
  gce_pd_csi_driver        = true
  network_policy           = false
  dns_cache                = false

  cluster_resource_labels = { owner = var.owner }

  node_pools = [
    {
      name               = "system"
      machine_type       = "e2-standard-2"
      min_count          = 1
      max_count          = 2
      initial_node_count = 1
      spot               = true
      disk_size_gb       = 30
      disk_type          = "pd-standard"
      auto_upgrade       = true
      auto_repair        = true
    },
  ]
}

# The wrapper's own resources: no module call makes them, so no chart maps
# them; the offramp keeps them as one frozen Package and lists each.

resource "google_compute_firewall" "master_webhooks" {
  project       = var.project_id
  name          = "${var.prefix}-gke-master-webhooks"
  network       = module.network.self_link
  direction     = "INGRESS"
  source_ranges = [var.master_cidr]
  allow {
    protocol = "tcp"
    ports    = ["8443", "9443", "15017"]
  }
}

resource "google_service_account" "workload" {
  project      = var.project_id
  account_id   = "${var.prefix}-workload"
  display_name = "GKE workloads of ${var.prefix}"
}

resource "google_project_iam_member" "workload_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.workload.email}"
}
