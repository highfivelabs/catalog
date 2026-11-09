# Three module calls for one application, as Terraform has them: a network, a
# service account and a bucket that the account may read. In Terraform a
# second copy of this root module in the same project would ask Google Cloud
# for the same network, account and bucket names (a 409). In Bundt the
# Template gives every component the namePrefix ${instance.name} (see
# convert.args), so each Instance gets names of its own; the module's own
# prefix variable keeps its meaning and namePrefix goes in front of it.

variable "project_id" {
  type = string
}

variable "prefix" {
  type = string
}

module "vpc" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v60.0.0"
  project_id = var.project_id
  name       = "app-network"
  subnets = [
    {
      ip_cidr_range = "10.0.0.0/24"
      name          = "app"
      region        = "europe-west1"
    },
  ]
}

module "reader" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=v60.0.0"
  project_id = var.project_id
  name       = "reader"
}

module "bucket" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v60.0.0"
  project_id = var.project_id
  prefix     = var.prefix
  name       = "data"
  location   = "EU"
  iam_bindings_additive = {
    reader = {
      role   = "roles/storage.objectViewer"
      member = module.reader.iam_email
    }
  }
}
