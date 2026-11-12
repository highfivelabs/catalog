# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0

output "project_id" {
  value = module.project.project_id
}

output "service_accounts" {
  value = { for k, v in module.platform_service_accounts.service_accounts_map : k => v.email }
}

output "checkout_service_account" {
  value = google_service_account.checkout.email
}
