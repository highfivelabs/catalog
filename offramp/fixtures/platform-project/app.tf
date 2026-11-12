# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# The application inside the platform project: "checkout". Its own runtime
# account, a bucket and a secret it owns, its project-level roles, and the
# Workload Identity binding that lets its Kubernetes service account act as
# it. Nothing in the state marks these as the app's rather than the
# platform's except the names, the labels and what they reference; that
# is the boundary the design's heuristics and quiz draw.

resource "google_service_account" "checkout" {
  project      = module.project.project_id
  account_id   = "checkout-runtime"
  display_name = "checkout runtime"
}

resource "google_project_iam_member" "checkout" {
  for_each = toset(["roles/cloudtrace.agent", "roles/monitoring.metricWriter"])
  project  = module.project.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.checkout.email}"
}

resource "google_service_account_iam_member" "checkout_workload_identity" {
  service_account_id = google_service_account.checkout.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${module.project.project_id}.svc.id.goog[checkout/checkout]"
}

resource "google_storage_bucket" "checkout_assets" {
  project                     = module.project.project_id
  name                        = "${module.project.project_id}-checkout-assets"
  location                    = upper(var.region)
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true
  labels = {
    app = "checkout"
  }
}

resource "google_storage_bucket_iam_member" "checkout_assets" {
  bucket = google_storage_bucket.checkout_assets.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.checkout.email}"
}

resource "google_secret_manager_secret" "checkout_db_password" {
  project   = module.project.project_id
  secret_id = "checkout-db-password"
  labels = {
    app = "checkout"
  }
  replication {
    auto {}
  }
  depends_on = [module.project]
}

resource "google_secret_manager_secret_iam_member" "checkout_db_password" {
  project   = module.project.project_id
  secret_id = google_secret_manager_secret.checkout_db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.checkout.email}"
}
