# A gke-cluster-standard module call as a team has it today, after the
# examples in modules/gke-cluster-standard/README.md of Cloud Foundation
# Fabric (Apache-2.0, Copyright Google LLC), pinned the way a team pins it.

module "cluster-1" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gke-cluster-standard?ref=v60.0.0"
  project_id = var.project_id
  name       = "cluster-1"
  location   = "europe-west1-b"
  vpc_config = {
    network    = "projects/my-project/global/networks/vpc"
    subnetwork = "projects/my-project/regions/europe-west1/subnetworks/gke"
    secondary_range_names = {
      pods     = "pods"
      services = "services"
    }
  }
  access_config = {
    ip_access = {
      authorized_ranges = {
        internal-vms = "10.0.0.0/8"
      }
    }
    master_ipv4_cidr_block = "192.168.0.0/28"
  }
  max_pods_per_node = 32
  labels = {
    environment = "dev"
  }
}

variable "project_id" {
  type = string
}
