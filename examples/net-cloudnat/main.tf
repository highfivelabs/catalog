# A Cloud NAT module call as a team has it today, after the examples in
# modules/net-cloudnat/README.md of Cloud Foundation Fabric (Apache-2.0,
# Copyright Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

variable "network" {
  type = string
}

module "nat" {
  source         = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-cloudnat?ref=v60.0.0"
  project_id     = var.project_id
  region         = "europe-west8"
  name           = "default"
  router_network = var.network
  logging_filter = "ERRORS_ONLY"
  config_port_allocation = {
    enable_endpoint_independent_mapping = false
    enable_dynamic_port_allocation      = true
    min_ports_per_vm                    = 64
  }
}
