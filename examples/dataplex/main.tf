# A dataplex module call as a team has it today, after the example in
# modules/dataplex/README.md of Cloud Foundation Fabric (Apache-2.0,
# Copyright Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

module "dataplex" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dataplex?ref=v60.0.0"
  name       = "terraform-lake"
  prefix     = "test"
  project_id = var.project_id
  region     = "europe-west2"
  iam = {
    "roles/dataplex.viewer" = ["group:analysts@example.com"]
  }
  zones = {
    landing = {
      type      = "RAW"
      discovery = true
      assets = {
        gcs_1 = {
          resource_name          = "gcs_bucket"
          cron_schedule          = "15 15 * * *"
          discovery_spec_enabled = true
          resource_spec_type     = "STORAGE_BUCKET"
        }
      }
    },
    curated = {
      type      = "CURATED"
      discovery = false
      iam = {
        "roles/dataplex.dataReader" = ["group:analysts@example.com"]
      }
      assets = {}
    }
  }
}
