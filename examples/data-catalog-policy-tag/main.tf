# A data-catalog-policy-tag module call as a team has it today, after the
# examples in modules/data-catalog-policy-tag/README.md of Cloud Foundation
# Fabric (Apache-2.0, Copyright Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

module "cmn-dc" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/data-catalog-policy-tag?ref=v60.0.0"
  name       = "my-datacatalog-policy-tags"
  project_id = var.project_id
  location   = "eu"
  tags = {
    low    = {}
    medium = {}
    high = {
      iam = {
        "roles/datacatalog.categoryFineGrainedReader" = ["group:high-readers@example.com"]
      }
    }
  }
  iam = {
    "roles/datacatalog.categoryAdmin" = ["group:data-admins@example.com"]
  }
}
