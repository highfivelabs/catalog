# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0

output "network_id" {
  value = module.vpc.id
}

output "subnet_ids" {
  value = module.vpc.subnet_ids
}

output "firewall_policy_id" {
  value = module.network_firewall_policy.fw_policy[0].id
}
