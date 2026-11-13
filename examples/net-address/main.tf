# A net-address module call as a team has it today, after the examples in
# modules/net-address/README.md of Cloud Foundation Fabric (Apache-2.0,
# Copyright Google LLC), pinned the way a team pins it.

module "addresses" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-address?ref=v60.0.0"
  project_id = var.project_id
  external_addresses = {
    one = { region = "europe-west1" }
  }
  internal_addresses = {
    ilb-1 = {
      purpose    = "SHARED_LOADBALANCER_VIP"
      region     = "europe-west1"
      subnetwork = "projects/my-project/regions/europe-west1/subnetworks/default"
    }
  }
  psc_addresses = {
    googleapis = {
      address            = "10.0.0.32"
      network            = "projects/my-project/global/networks/my-network"
      service_attachment = { psc_service_attachment_link = "all-apis" }
    }
  }
}

variable "project_id" {
  type = string
}
