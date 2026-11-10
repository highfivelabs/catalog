# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Shape 1: a hierarchy of folders. A root folder under the parent, three
# environment folders under it and two team folders under prod; folder
# admins (authoritative per role, as the folders module grants them) and
# one additive grant; organization policies (one boolean, one list, one
# with a condition) on the root; a hierarchical firewall policy owned by
# the root and attached to prod and nonprod.
#
# Needs, on the parent folder: roles/resourcemanager.folderCreator (or
# folderAdmin), roles/orgpolicy.policyAdmin (granted on the organization;
# it takes effect on folders below it), roles/compute.orgFirewallPolicyAdmin
# and roles/resourcemanager.folderIamAdmin. The live-test account holds none
# of them (see the design, "Grants").

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.0, < 9"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
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

provider "google-beta" {
  billing_project       = var.billing_project
  user_project_override = true
}

resource "google_folder" "root" {
  display_name        = "${var.prefix}-root"
  parent              = var.parent
  deletion_protection = false
}

module "environments" {
  source  = "terraform-google-modules/folders/google"
  version = "~> 5.2"

  parent              = google_folder.root.name
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
  version = "~> 5.2"

  parent              = module.environments.ids["prod"]
  names               = ["team-a", "team-b"]
  prefix              = "${var.prefix}-prod"
  deletion_protection = false
}

# An additive grant beside the module's authoritative ones.
resource "google_folder_iam_member" "auditor" {
  folder = google_folder.root.name
  role   = "roles/iam.securityReviewer"
  member = var.auditor
}

module "skip_default_network" {
  source  = "terraform-google-modules/org-policy/google//modules/org_policy_v2"
  version = "~> 7.4"

  policy_root    = "folder"
  policy_root_id = google_folder.root.folder_id
  constraint     = "compute.skipDefaultNetworkCreation"
  policy_type    = "boolean"
  rules          = [{ enforcement = true }]
}

module "resource_locations" {
  source  = "terraform-google-modules/org-policy/google//modules/org_policy_v2"
  version = "~> 7.4"

  policy_root    = "folder"
  policy_root_id = google_folder.root.folder_id
  constraint     = "gcp.resourceLocations"
  policy_type    = "list"
  rules          = [{ enforcement = true, allow = ["in:us-locations"] }]
}

module "require_os_login" {
  source  = "terraform-google-modules/org-policy/google//modules/org_policy_v2"
  version = "~> 7.4"

  policy_root    = "folder"
  policy_root_id = google_folder.root.folder_id
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
  version = "~> 18.3"

  parent_node = google_folder.root.name
  policy_name = "${var.prefix}-baseline"
  description = "offramp fixture: baseline rules for every project below"
  # Associations are plain resources below: the module keys its
  # associations by the folder IDs, unknown until the folders exist.
  target_folders = []

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

resource "google_compute_firewall_policy_association" "environments" {
  for_each          = toset(["prod", "nonprod"])
  name              = "${var.prefix}-${each.value}"
  attachment_target = module.environments.ids[each.value]
  firewall_policy   = module.hierarchical_firewall.fw_policy.name
}
