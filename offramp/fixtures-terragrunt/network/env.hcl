# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# The network environment: the live run ofr-11110114-2801's project and
# prefix, so each unit's state is that run's (internal/offramp/testdata/
# terragrunt/README.md).

locals {
  project_id = "hfl-dev-514205"
  prefix     = "ofr-11110114-2801"
  members    = ["serviceAccount:cce-live-tests@hfl-dev-514205.iam.gserviceaccount.com"]
}
