# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Shape 2: a project set up as a platform, with one application already
# inside it, in one root module and one state, as teams usually have it.
# Built only from Cloud Foundation Fabric modules at v60.0.0, because the
# catalog's project, service account and bucket charts port fabric's.
#
#   module.project                 fabric project v60.0.0              charts/gcp/project
#   module.platform_deployer,
#   module.platform_ci             fabric iam-service-account v60.0.0  charts/gcp/iam-service-account
#   (app.tf) module.checkout       fabric iam-service-account v60.0.0  charts/gcp/iam-service-account
#   (app.tf) module.checkout_assets fabric gcs v60.0.0                 charts/gcp/gcs
#   (app.tf) module.checkout_secrets fabric secret-manager v60.0.0     charts/gcp/secret-manager
#
# The platform's part (this file): the project with its APIs and labels,
# the platform admins' additive grants, and baseline service accounts with
# their project roles. The application's part is app.tf. Telling them
# apart is the converter's and the quiz's job (the design, "The boundary").
#
# The default compute service account is kept: the catalog's project chart
# cannot deprivilege it (Config Connector has no kind for that; the
# design's "Gaps"), so `default_service_account` stays at "keep".
#
# Needs, on the parent folder, roles/resourcemanager.projectCreator, and on
# the billing account roles/billing.user. The live-test account holds
# neither (register items O33, O34): this shape is validated and converted
# offline only.

terraform {
  required_version = ">= 1.12.2"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.10.0, < 9"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 8.10.0, < 9"
    }
  }
}

locals {
  # The project's ID, known before it exists (fabric's project module takes
  # it from name and prefix). Map keys use it: a key cannot be a module
  # output, which is unknown until apply.
  project_id = "${var.prefix}-platform"
}

module "project" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project?ref=v60.0.0"

  name            = local.project_id
  parent          = var.folder_id
  billing_account = var.billing_account
  deletion_policy = "DELETE"
  services = [
    "artifactregistry.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ]
  labels = {
    owner = "platform"
    tier  = "platform"
  }
  iam_bindings_additive = merge([
    for role in ["roles/viewer", "roles/iam.serviceAccountAdmin", "roles/resourcemanager.projectIamAdmin"] : {
      for i, m in var.platform_admins : "${replace(role, "roles/", "")}-${i}" => { role = role, member = m }
    }
  ]...)
}

module "platform_deployer" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=v60.0.0"

  project_id   = module.project.project_id
  name         = "platform-deployer"
  display_name = "platform baseline"
  description  = "offramp fixture: a platform baseline account"
  iam_project_roles = {
    (local.project_id) = ["roles/logging.logWriter", "roles/monitoring.metricWriter"]
  }
  # CI may act as the deployer.
  iam_bindings_additive = {
    ci = { role = "roles/iam.serviceAccountUser", member = module.platform_ci.iam_email }
  }
}

module "platform_ci" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=v60.0.0"

  project_id   = module.project.project_id
  name         = "platform-ci"
  display_name = "platform baseline"
  description  = "offramp fixture: a platform baseline account"
  iam_project_roles = {
    (local.project_id) = ["roles/logging.logWriter", "roles/monitoring.metricWriter"]
  }
}
