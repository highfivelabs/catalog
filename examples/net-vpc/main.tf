# A network module call as a team has it today, after the "Simple VPC"
# example in modules/net-vpc/README.md of Cloud Foundation Fabric
# (Apache-2.0, Copyright Google LLC), with a route and the Shared VPC host
# setting added.

variable "project_id" {
  type = string
}

variable "service_project_ids" {
  type    = list(string)
  default = []
}

module "vpc" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v60.0.0"
  project_id = var.project_id
  name       = "my-network"
  subnets = [
    {
      ip_cidr_range = "10.0.0.0/24"
      name          = "production"
      region        = "europe-west1"
      secondary_ip_ranges = {
        pods     = { ip_cidr_range = "172.16.0.0/20" }
        services = { ip_cidr_range = "192.168.0.0/24" }
      }
    },
    {
      ip_cidr_range = "10.0.16.0/24"
      name          = "production"
      region        = "europe-west2"
    },
  ]
  routes = {
    gateway = {
      dest_range    = "0.0.0.0/0"
      priority      = 100
      next_hop_type = "gateway"
      next_hop      = "default-internet-gateway"
    }
  }
  shared_vpc_host             = true
  shared_vpc_service_projects = var.service_project_ids
}
