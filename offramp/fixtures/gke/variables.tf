# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0

variable "project_id" {
  type = string
}

variable "prefix" {
  type        = string
  description = "Prefix of every name, the live run's ID."
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "autopilot" {
  type        = bool
  default     = false
  description = "An Autopilot cluster instead of Standard with two node pools."
}

variable "create_service_account" {
  type        = bool
  default     = true
  description = "The module's own: make a node service account and grant it project roles. Live runs set false (no project IAM outside the fixture)."
}
