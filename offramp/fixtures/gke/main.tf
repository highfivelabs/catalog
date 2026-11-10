# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Shape 4: GKE. A small VPC for the cluster, then either a Standard private
# cluster with two Spot node pools (terraform-google-modules'
# kubernetes-engine `beta-private-cluster`, which the builder uses) or an
# Autopilot private cluster (`beta-autopilot-private-cluster`), chosen by
# var.autopilot. Zonal and Spot so a live run costs cents.
#
# Version: the builder linked kubernetes-engine 5.0.0 (2019, Terraform
# 0.12, google provider 2.x). The current major is 47 (v47.0.0); the
# catalog's gke-cluster chart ports v47.0.0, so the fixture pins ~> 47.0.
# Between them: node_pools became list(map(any)) with many more keys,
# release channels, Workload Identity by default, Dataplane V2, Gateway
# API, deletion_protection (provider 5+), and google 7.39+ is required.
#
# Needs roles/container.admin on the project and the Container API
# enabled; with create_service_account (the module's default) also
# roles/resourcemanager.projectIamAdmin, since the module grants the node
# account project roles. The live-test account holds neither (see the
# design, "Grants"); live runs pass create_service_account = false.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.39, < 9"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.39, < 9"
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
  subnet = "${var.prefix}-gke"
}

module "network" {
  source  = "terraform-google-modules/network/google"
  version = "~> 18.3"

  project_id   = var.project_id
  network_name = "${var.prefix}-gke"
  routing_mode = "REGIONAL"
  subnets = [{
    subnet_name           = local.subnet
    subnet_ip             = "10.40.0.0/24"
    subnet_region         = var.region
    subnet_private_access = "true"
  }]
  secondary_ranges = {
    (local.subnet) = [
      { range_name = "pods", ip_cidr_range = "10.41.0.0/20" },
      { range_name = "services", ip_cidr_range = "10.42.0.0/24" },
    ]
  }
}

module "gke_standard" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/beta-private-cluster"
  version = "~> 47.0"
  count   = var.autopilot ? 0 : 1

  project_id        = var.project_id
  name              = "${var.prefix}-std"
  regional          = false
  region            = var.region
  zones             = ["${var.region}-a"]
  network           = module.network.network_name
  subnetwork        = module.network.subnets_names[0]
  ip_range_pods     = "pods"
  ip_range_services = "services"

  enable_private_nodes    = true
  enable_private_endpoint = false
  master_ipv4_cidr_block  = "172.16.0.0/28"
  master_authorized_networks = [
    { cidr_block = "10.40.0.0/24", display_name = "nodes" },
  ]

  release_channel          = "REGULAR"
  deletion_protection      = false
  remove_default_node_pool = true
  create_service_account   = var.create_service_account
  grant_registry_access    = false
  gateway_api_channel      = "CHANNEL_STANDARD"
  enable_cost_allocation   = true
  gce_pd_csi_driver        = true
  network_policy           = false
  dns_cache                = false

  cluster_resource_labels = { owner = "platform" }

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
    {
      name               = "apps"
      machine_type       = "e2-standard-2"
      min_count          = 0
      max_count          = 3
      initial_node_count = 0
      spot               = true
      disk_size_gb       = 30
      disk_type          = "pd-standard"
      auto_upgrade       = true
      auto_repair        = true
    },
  ]
  node_pools_labels = {
    all  = {}
    apps = { workload = "apps" }
  }
  node_pools_taints = {
    all  = []
    apps = [{ key = "workload", value = "apps", effect = "NO_SCHEDULE" }]
  }
}

module "gke_autopilot" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/beta-autopilot-private-cluster"
  version = "~> 47.0"
  count   = var.autopilot ? 1 : 0

  project_id        = var.project_id
  name              = "${var.prefix}-ap"
  region            = var.region
  network           = module.network.network_name
  subnetwork        = module.network.subnets_names[0]
  ip_range_pods     = "pods"
  ip_range_services = "services"

  enable_private_nodes    = true
  enable_private_endpoint = false
  master_ipv4_cidr_block  = "172.16.0.16/28"

  release_channel         = "REGULAR"
  deletion_protection     = false
  create_service_account  = var.create_service_account
  cluster_resource_labels = { owner = "platform" }
}
