# A Cloud SQL module call as a team has it today, after the examples in
# modules/cloudsql-instance/README.md of Cloud Foundation Fabric
# (Apache-2.0, Copyright Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

variable "network" {
  type = string
}

module "db" {
  source           = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloudsql-instance?ref=v60.0.0"
  project_id       = var.project_id
  name             = "db"
  region           = "europe-west8"
  database_version = "POSTGRES_16"
  tier             = "db-custom-2-7680"
  network_config = {
    connectivity = {
      psa_config = {
        private_network = var.network
      }
    }
  }
  backup_configuration = {
    enabled                        = true
    point_in_time_recovery_enabled = true
  }
  flags = {
    "cloudsql.iam_authentication" = "on"
  }
  databases = ["orders"]
  users = {
    "app@myproject.iam.gserviceaccount.com" = {
      type = "CLOUD_IAM_SERVICE_ACCOUNT"
    }
  }
  gcp_deletion_protection = false
}
