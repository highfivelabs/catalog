# A bucket module call as a team has it today, after the example in
# modules/gcs/README.md of Cloud Foundation Fabric (Apache-2.0, Copyright
# Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

variable "prefix" {
  type = string
}

variable "readers_group" {
  type = string
}

module "bucket" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v60.0.0"
  project_id = var.project_id
  prefix     = var.prefix
  name       = "my-bucket"
  location   = "EU"
  versioning = true
  labels = {
    cost-center = "devops"
  }
  iam = {
    "roles/storage.objectViewer" = ["group:${var.readers_group}"]
  }
  lifecycle_rules = {
    expire-old-objects = {
      action    = { type = "Delete" }
      condition = { age = 365 }
    }
  }
}
