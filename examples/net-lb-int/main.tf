# A net-lb-int module call as a team has it today, after the examples in
# modules/net-lb-int/README.md of Cloud Foundation Fabric (Apache-2.0,
# Copyright Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

module "ilb" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-lb-int?ref=v60.0.0"
  project_id = var.project_id
  region     = "europe-west1"
  name       = "ilb-test"
  vpc_config = {
    network    = "projects/my-project/global/networks/my-network"
    subnetwork = "projects/my-project/regions/europe-west1/subnetworks/gce"
  }
  backends = [{
    group = "projects/my-project/zones/europe-west1-b/instanceGroups/my-ig"
  }]
  health_check_config = {
    http = {
      port = 80
    }
  }
}
