# A secret-manager module call as a team has it today, after the examples in
# modules/secret-manager/README.md of Cloud Foundation Fabric (Apache-2.0,
# Copyright Google LLC), pinned the way a team pins it. The secrets' data
# (versions) stays out: the chart refuses it.

variable "project_id" {
  type = string
}

variable "app_sa" {
  type = string
}

module "secret-manager" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/secret-manager?ref=v60.0.0"
  project_id = var.project_id
  secrets = {
    test-auto = {
      iam = {
        "roles/secretmanager.secretAccessor" = ["serviceAccount:${var.app_sa}"]
      }
    }
    test-user = {
      global_replica_locations = {
        europe-west1 = null
        europe-west3 = null
      }
      labels = {
        app = "checkout"
      }
    }
  }
}
