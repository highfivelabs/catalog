# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# The application inside the platform project: "checkout". Its own runtime
# account with its project roles and the Workload Identity binding that
# lets its Kubernetes service account act as it, a bucket it owns, and a
# secret. Nothing in the state marks these as the app's rather than the
# platform's except the names, the labels and what they reference; that
# is the boundary the design's heuristics and quiz draw.

locals {
  checkout_bucket = "${local.project_id}-checkout-assets"
}

module "checkout" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/iam-service-account?ref=v60.0.0"

  project_id   = module.project.project_id
  name         = "checkout-runtime"
  display_name = "checkout runtime"
  iam_project_roles = {
    (local.project_id) = ["roles/cloudtrace.agent", "roles/monitoring.metricWriter"]
  }
  iam_storage_roles = {
    (local.checkout_bucket) = ["roles/storage.objectAdmin"]
  }
  iam_bindings_additive = {
    workload-identity = {
      role   = "roles/iam.workloadIdentityUser"
      member = "serviceAccount:${module.project.project_id}.svc.id.goog[checkout/checkout]"
    }
  }
  # The bucket grant needs the bucket.
  depends_on = [module.checkout_assets]
}

module "checkout_assets" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v60.0.0"

  project_id               = module.project.project_id
  name                     = local.checkout_bucket
  location                 = upper(var.region)
  public_access_prevention = "enforced"
  force_destroy            = true
  labels = {
    app = "checkout"
  }
}

# No catalog chart ports fabric's secret-manager yet: the converter keeps
# this call as a frozen Package of its Config Connector objects and lists
# it as a gap.
module "checkout_secrets" {
  source = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/secret-manager?ref=v60.0.0"

  project_id = module.project.project_id
  secrets = {
    checkout-db-password = {
      labels = { app = "checkout" }
      iam_bindings_additive = {
        runtime = {
          role   = "roles/secretmanager.secretAccessor"
          member = module.checkout.iam_email
        }
      }
    }
  }
}
