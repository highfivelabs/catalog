# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0

output "cluster" {
  value = var.autopilot ? module.gke_autopilot[0].name : module.gke_standard[0].name
}

output "endpoint" {
  value     = var.autopilot ? module.gke_autopilot[0].endpoint : module.gke_standard[0].endpoint
  sensitive = true
}
