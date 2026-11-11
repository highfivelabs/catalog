# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0

variable "project_id" {
  type = string
}

variable "prefix" {
  type        = string
  description = "Prefix of every name."
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "owner" {
  type        = string
  description = "The owner label on the cluster."
}

variable "nodes_cidr" {
  type    = string
  default = "10.40.0.0/24"
}

variable "pods_cidr" {
  type    = string
  default = "10.41.0.0/20"
}

variable "services_cidr" {
  type    = string
  default = "10.42.0.0/24"
}

variable "master_cidr" {
  type    = string
  default = "172.16.0.0/28"
}
