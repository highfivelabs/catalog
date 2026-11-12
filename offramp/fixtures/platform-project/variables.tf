# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0

variable "folder_id" {
  type        = string
  description = "The folder the project goes in, folders/<number>. Live runs: the live-tests folder."
}

variable "billing_account" {
  type        = string
  description = "The billing account the project is linked to."
}

variable "prefix" {
  type        = string
  description = "Prefix of every name, the live run's ID."
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "platform_admins" {
  type        = list(string)
  description = "Members given the platform admins' project roles, additively."
}
