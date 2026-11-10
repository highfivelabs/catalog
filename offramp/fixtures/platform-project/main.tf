# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Shape 2: a project set up as a platform, with one application already
# inside it, in one root module and one state, as teams usually have it.
#
# The platform's part (this file): the project from project-factory with
# its APIs and its default service account deprivileged; baseline service
# accounts (deployer, CI, observability) with their project roles; the
# platform admins' grants. The application's part is app.tf. Telling them
# apart is the converter's and the quiz's job (the design, "The boundary").
#
# Needs, on the parent folder, roles/resourcemanager.projectCreator, and on
# the billing account roles/billing.user. The live-test account holds
# neither (see the design, "Grants").

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.0, < 9"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 8.0, < 9"
    }
  }
}

module "project" {
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 18.4"

  name = "${var.prefix}-platform"
  # A known project ID (no random suffix): the service-accounts and iam
  # modules key their for_each by it, which must be known at plan time.
  random_project_id = false
  folder_id         = var.folder_id
  billing_account   = var.billing_account
  deletion_policy   = "DELETE"

  activate_apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com",
  ]
  disable_services_on_destroy = false
  default_service_account     = "deprivilege"
  create_project_sa           = false
  auto_create_network         = false

  labels = {
    owner = "platform"
    tier  = "platform"
  }
}

module "platform_service_accounts" {
  source  = "terraform-google-modules/service-accounts/google"
  version = "~> 5.1"

  project_id   = module.project.project_id
  names        = ["platform-deployer", "platform-ci", "platform-observability"]
  display_name = "platform baseline"
  description  = "offramp fixture: a platform baseline account"
  project_roles = [
    "${module.project.project_id}=>roles/logging.logWriter",
    "${module.project.project_id}=>roles/monitoring.metricWriter",
  ]
}

module "platform_iam" {
  source  = "terraform-google-modules/iam/google//modules/projects_iam"
  version = "~> 8.3"

  projects = [module.project.project_id]
  mode     = "additive"
  bindings = {
    "roles/viewer"                          = var.platform_admins
    "roles/iam.serviceAccountAdmin"         = var.platform_admins
    "roles/resourcemanager.projectIamAdmin" = var.platform_admins
  }
}

# The deployer may act as every account in the project; CI may act as the
# deployer only.
resource "google_service_account_iam_member" "ci_uses_deployer" {
  service_account_id = module.platform_service_accounts.service_accounts_map["platform-deployer"].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${module.platform_service_accounts.service_accounts_map["platform-ci"].email}"
}
