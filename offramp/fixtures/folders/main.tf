# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Shape 1: a hierarchy of folders, built only from terraform-google-modules,
# each pinned to an exact release. A root folder under the parent, three
# environment folders under it and two team folders under prod; folder
# admins (authoritative per role, as the folders module grants them) and
# one additive grant; organization policies (one boolean, one list, one
# with a condition) on the root; a hierarchical firewall policy owned by
# the root and attached to prod and nonprod.
#
#   module.root, .environments, .teams  folders 5.2.0                          charts/gcp/folders
#   module.auditor                      iam//modules/folders_iam 8.3.0          charts/gcp/folders-iam
#   module.skip_default_network,
#   .resource_locations,
#   .require_os_login                   org-policy//modules/org_policy_v2 7.4.0 charts/gcp/org-policy-v2
#   module.hierarchical_firewall        network//modules/hierarchical-firewall-policy 18.3.1
#                                                                               charts/gcp/hierarchical-firewall-policy
#
# The firewall policy's associations are keyed by the folder IDs, unknown
# until the folders exist, so a first apply needs
# `-target=module.environments` (Terraform's own advice for a for_each
# over unknown keys); later applies need nothing special.
#
# Needs, on the parent folder: roles/resourcemanager.folderAdmin,
# roles/compute.orgFirewallPolicyAdmin and orgSecurityResourceAdmin;
# roles/orgpolicy.policyAdmin on the organization. The live-test account
# holds none of them (register items O33, O34): this shape is validated and
# converted offline only.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.0, < 9"
    }
  }
}

provider "google" {
  # Folder, organization policy and firewall policy calls bill to this
  # project (user_project_override), so the account needs
  # serviceusage.services.use on it.
  billing_project       = var.billing_project
  user_project_override = true
}

module "root" {
  source  = "terraform-google-modules/folders/google"
  version = "5.2.0"

  parent              = var.parent
  names               = ["root"]
  prefix              = var.prefix
  deletion_protection = false
}

module "environments" {
  source  = "terraform-google-modules/folders/google"
  version = "5.2.0"

  parent              = module.root.id
  names               = ["shared", "prod", "nonprod"]
  prefix              = var.prefix
  deletion_protection = false

  set_roles          = true
  folder_admin_roles = ["roles/resourcemanager.folderViewer", "roles/browser"]
  per_folder_admins = {
    prod = { members = var.prod_admins, roles = ["roles/resourcemanager.folderViewer"] }
  }
  all_folder_admins = var.all_folder_admins
}

module "teams" {
  source  = "terraform-google-modules/folders/google"
  version = "5.2.0"

  parent              = module.environments.ids["prod"]
  names               = ["team-a", "team-b"]
  prefix              = "${var.prefix}-prod"
  deletion_protection = false
}

# An additive grant beside the folders module's authoritative ones.
module "auditor" {
  source  = "terraform-google-modules/iam/google//modules/folders_iam"
  version = "8.3.0"

  folders = [module.root.id]
  mode    = "additive"
  bindings = {
    "roles/iam.securityReviewer" = [var.auditor]
  }
}

module "skip_default_network" {
  source  = "terraform-google-modules/org-policy/google//modules/org_policy_v2"
  version = "7.4.0"

  policy_root    = "folder"
  policy_root_id = trimprefix(module.root.id, "folders/")
  constraint     = "compute.skipDefaultNetworkCreation"
  policy_type    = "boolean"
  rules          = [{ enforcement = true }]
}

module "resource_locations" {
  source  = "terraform-google-modules/org-policy/google//modules/org_policy_v2"
  version = "7.4.0"

  policy_root    = "folder"
  policy_root_id = trimprefix(module.root.id, "folders/")
  constraint     = "gcp.resourceLocations"
  policy_type    = "list"
  rules          = [{ enforcement = true, allow = ["in:us-locations"] }]
}

module "require_os_login" {
  source  = "terraform-google-modules/org-policy/google//modules/org_policy_v2"
  version = "7.4.0"

  policy_root    = "folder"
  policy_root_id = trimprefix(module.root.id, "folders/")
  constraint     = "compute.requireOsLogin"
  policy_type    = "boolean"
  rules = [
    {
      enforcement = true
      conditions  = []
    },
    {
      enforcement = false
      conditions = [{
        title       = "break-glass"
        description = "Projects tagged break-glass may skip OS Login"
        expression  = "resource.matchTag('${var.org_id}/break-glass', 'true')"
        location    = ""
      }]
    },
  ]
}

module "hierarchical_firewall" {
  source  = "terraform-google-modules/network/google//modules/hierarchical-firewall-policy"
  version = "18.3.1"

  parent_node = module.root.id
  policy_name = "${var.prefix}-baseline"
  description = "offramp fixture: baseline rules for every project below"
  # Folder numbers: the module writes folders/<n> itself.
  target_folders = [
    trimprefix(module.environments.ids["prod"], "folders/"),
    trimprefix(module.environments.ids["nonprod"], "folders/"),
  ]

  rules = [
    {
      priority  = 1000
      direction = "INGRESS"
      action    = "allow"
      rule_name = "allow-iap"
      match = {
        src_ip_ranges  = ["35.235.240.0/20"]
        layer4_configs = [{ ip_protocol = "tcp", ports = ["22", "3389"] }]
      }
    },
    {
      priority  = 2000
      direction = "INGRESS"
      action    = "goto_next"
      rule_name = "delegate-internal"
      match = {
        src_ip_ranges  = ["10.0.0.0/8"]
        layer4_configs = [{ ip_protocol = "all" }]
      }
    },
    {
      priority  = 65000
      direction = "INGRESS"
      action    = "deny"
      rule_name = "deny-rest"
      match = {
        src_ip_ranges  = ["0.0.0.0/0"]
        layer4_configs = [{ ip_protocol = "all" }]
      }
    },
  ]
}
