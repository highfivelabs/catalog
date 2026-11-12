# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0

output "project_id" {
  value = module.project.project_id
}

output "service_accounts" {
  value = {
    deployer = module.platform_deployer.email
    ci       = module.platform_ci.email
    checkout = module.checkout.email
  }
}
