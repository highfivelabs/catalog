# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0

variable "project_id" {
  type        = string
  description = "The host project."
}

variable "prefix" {
  type        = string
  description = "Prefix of every name, the live run's ID (ofr-<MMDDHHMM>-<4 hex>)."
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "shared_vpc_host" {
  type        = bool
  default     = false
  description = "Enable the project as a Shared VPC host. Needs roles/compute.xpnAdmin on the folder or organization."
}

variable "apps_subnet_users" {
  type        = list(string)
  description = "Members granted roles/compute.networkUser on the apps subnet, one google_compute_subnetwork_iam_member each."
}

variable "gke_subnet_users" {
  type        = list(string)
  description = "Members of the authoritative roles/compute.networkUser binding on the GKE subnet."
}
