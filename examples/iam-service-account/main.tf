# A service account module call as a team has it today, after the example in
# modules/iam-service-account/README.md of Cloud Foundation Fabric
# (Apache-2.0, Copyright Google LLC).

variable "project_id" {
  type = string
}

variable "group_email" {
  type = string
}

module "vm-default" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=v60.0.0"
  project_id = var.project_id
  name       = "vm-default"
  # authoritative roles granted *on* the service account to other identities
  iam = {
    "roles/iam.serviceAccountUser" = ["group:${var.group_email}"]
  }
  # non-authoritative roles granted *to* the service account on other resources
  iam_project_roles = {
    "${var.project_id}" = [
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
    ]
  }
}
