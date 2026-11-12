# An alloydb module call as a team has it today, after the examples in
# modules/alloydb/README.md of Cloud Foundation Fabric (Apache-2.0,
# Copyright Google LLC), pinned the way a team pins it.

module "alloydb" {
  source         = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/alloydb?ref=v60.0.0"
  project_id     = var.project_id
  project_number = var.project_number
  cluster_name   = "db"
  instance_name  = "db"
  location       = "europe-west8"
  network_config = {
    psa_config = {
      network = "projects/my-project/global/networks/my-network"
    }
  }
  automated_backup_configuration = {
    enabled = true
  }
  read_pool = {
    ro = { node_count = 2 }
  }
  users = {
    "app@example.com" = { type = "ALLOYDB_IAM_USER", roles = ["alloydbiamuser"] }
  }
}

variable "project_id" {
  type = string
}

variable "project_number" {
  type = string
}
