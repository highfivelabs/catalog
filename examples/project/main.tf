# A project module call as a team has it today, after the examples in
# modules/project/README.md of Cloud Foundation Fabric (Apache-2.0,
# Copyright Google LLC).

variable "billing_account_id" {
  type = string
}

variable "folder_id" {
  type = string
}

variable "prefix" {
  type = string
}

variable "devs_group" {
  type = string
}

module "project" {
  source          = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project?ref=v60.0.0"
  billing_account = var.billing_account_id
  name            = "project"
  parent          = var.folder_id
  prefix          = var.prefix
  services = [
    "container.googleapis.com",
    "stackdriver.googleapis.com",
  ]
  iam = {
    "roles/viewer" = ["group:${var.devs_group}"]
  }
  org_policies = {
    "compute.disableGuestAttributesAccess" = {
      rules = [{ enforce = true }]
    }
  }
}
