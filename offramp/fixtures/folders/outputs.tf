# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0

output "root" {
  value = module.root.id
}

output "environments" {
  value = module.environments.ids
}

output "teams" {
  value = module.teams.ids
}

output "firewall_policy" {
  value = module.hierarchical_firewall.fw_policy.name
}
