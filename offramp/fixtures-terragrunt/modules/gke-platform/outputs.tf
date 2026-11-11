# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0

output "network_name" {
  value = module.network.name
}

output "cluster_name" {
  value = module.cluster.name
}

output "workload_service_account" {
  value = google_service_account.workload.email
}
