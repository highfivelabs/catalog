# An ncc-spoke-ra module call as a team has it today, after the example in
# modules/ncc-spoke-ra/README.md of Cloud Foundation Fabric (Apache-2.0,
# Copyright Google LLC), pinned the way a team pins it.

module "spoke-ra" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/ncc-spoke-ra?ref=v60.0.0"
  hub        = { create = true, name = "ncc-hub" }
  name       = "spoke-ra"
  project_id = var.project_id
  region     = "europe-west1"
  router_appliances = [
    {
      internal_ip  = "10.0.0.3"
      vm_self_link = "projects/my-project/zones/europe-west1-b/instances/router-app"
    }
  ]
  router_config = {
    asn           = 65000
    ip_interface0 = "10.0.0.14"
    ip_interface1 = "10.0.0.15"
    peer_asn      = 65001
  }
  vpc_config = {
    network_name     = "my-vpc"
    subnet_self_link = "projects/my-project/regions/europe-west1/subnetworks/subnet"
  }
}

variable "project_id" {
  type = string
}
