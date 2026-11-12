# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Case (b) again, around Cloud Foundation Fabric's project module: the
# source is fixtures/platform-project, a root module that calls fabric's
# project, iam-service-account, gcs and secret-manager modules.

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../fixtures//platform-project"
}

inputs = {
  folder_id       = "folders/100000000001"
  billing_account = "012345-6789AB-CDEF01"
  prefix          = "ofr-test"
  platform_admins = ["group:platform-admins@example.com"]
}
