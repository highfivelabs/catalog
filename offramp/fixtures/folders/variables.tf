# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0

variable "parent" {
  type        = string
  description = "The folder (folders/<number>) or organization (organizations/<number>) the root folder goes under. Live runs: the live-tests folder."
}

variable "org_id" {
  type        = string
  description = "The organization's number, for the tag in the OS Login condition."
}

variable "billing_project" {
  type        = string
  description = "The project folder, policy and firewall calls bill to."
}

variable "prefix" {
  type        = string
  description = "Prefix of every name, the live run's ID."
}

variable "prod_admins" {
  type        = list(string)
  description = "Members of prod's authoritative folderViewer binding."
}

variable "all_folder_admins" {
  type        = list(string)
  default     = []
  description = "Members granted folder_admin_roles on every environment folder."
}

variable "auditor" {
  type        = string
  description = "One member granted iam.securityReviewer on the root, additively."
}
