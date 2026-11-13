# A net-lb-ext module call as a team has it today, after the examples in
# modules/net-lb-ext/README.md of Cloud Foundation Fabric (Apache-2.0,
# Copyright Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

module "nlb" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-lb-ext?ref=v60.0.0"
  project_id = var.project_id
  region     = "europe-west1"
  name       = "nlb-test"
  backends = [{
    group = "projects/my-project/zones/europe-west1-b/instanceGroups/my-ig"
  }]
  health_check_config = {
    http = {
      port = 80
    }
  }
}
