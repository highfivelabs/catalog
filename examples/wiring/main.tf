# Two module calls where one uses the other's output: a service account that
# may read a bucket. Terraform wires them with module.<name>.<output> and an
# implicit dependency; Bundt wires components with an expression on the other
# component's outputs, which also orders them.

variable "project_id" {
  type = string
}

variable "prefix" {
  type = string
}

module "reader" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=v60.0.0"
  project_id = var.project_id
  name       = "bucket-reader"
}

module "bucket" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v60.0.0"
  project_id = var.project_id
  prefix     = var.prefix
  name       = "shared-data"
  location   = "EU"
  iam_bindings_additive = {
    reader = {
      role   = "roles/storage.objectViewer"
      member = module.reader.iam_email
    }
  }
}
