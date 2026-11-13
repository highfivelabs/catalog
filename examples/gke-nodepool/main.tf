# A gke-nodepool module call as a team has it today, after the examples in
# modules/gke-nodepool/README.md of Cloud Foundation Fabric (Apache-2.0,
# Copyright Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

module "cluster-1-nodepool-1" {
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gke-nodepool?ref=v60.0.0"
  project_id   = var.project_id
  cluster_name = "cluster-1"
  location     = "europe-west1-b"
  name         = "nodepool-1"
  service_account = {
    create = true
  }
  node_config = {
    machine_type = "n2-standard-2"
    spot         = true
  }
  nodepool_config = {
    autoscaling = {
      max_node_count = 3
      min_node_count = 0
    }
  }
  k8s_labels = { environment = "dev" }
  taints = {
    dedicated = { value = "batch", effect = "NO_SCHEDULE" }
  }
}
