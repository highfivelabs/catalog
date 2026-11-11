# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Shape 4: GKE, built only from published open-source modules, each pinned
# to an exact release. A small VPC for the cluster, then either a Standard
# private cluster with two Spot node pools or an Autopilot private
# cluster, chosen by var.autopilot. Zonal and Spot so a live run costs
# cents.
#
#   module.network        fabric net-vpc v60.0.0                         charts/gcp/net-vpc
#   module.gke_standard   kubernetes-engine//modules/beta-private-cluster 47.0.0
#                                                                         charts/gcp/gke-cluster
#   module.gke_autopilot  kubernetes-engine//modules/beta-autopilot-private-cluster 47.0.0
#                                                                         charts/gcp/gke-cluster (mode: autopilot)
#
# The network is Cloud Foundation Fabric's because the catalog's network
# chart ports fabric's net-vpc; the cluster is terraform-google-modules',
# the family the builder uses.
#
# Needs roles/container.admin on the project and the Container API
# enabled; with create_service_account (the module's default) also
# roles/resourcemanager.projectIamAdmin. The live-test account holds
# neither (register items O33, O34): this shape is validated and converted
# offline only.

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
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v60.0.0"

  project_id   = var.project_id
  name         = "${var.prefix}-gke"
  routing_mode = "REGIONAL"
  subnets = [{
    name          = local.subnet
    region        = var.region
    ip_cidr_range = "10.40.0.0/24"
    secondary_ip_ranges = {
      pods     = { ip_cidr_range = "10.41.0.0/20" }
      services = { ip_cidr_range = "10.42.0.0/24" }
    }
  }]
}

module "gke_standard" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/beta-private-cluster"
  version = "47.0.0"
  count   = var.autopilot ? 0 : 1

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
  version = "47.0.0"
  count   = var.autopilot ? 1 : 0

  project_id        = var.project_id
  name              = "${var.prefix}-ap"
  region            = var.region
  network           = module.network.name
  subnetwork        = local.subnet
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
