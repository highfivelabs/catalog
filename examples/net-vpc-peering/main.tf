# A net-vpc-peering module call as a team has it today, after the examples
# in modules/net-vpc-peering/README.md of Cloud Foundation Fabric
# (Apache-2.0, Copyright Google LLC), pinned the way a team pins it.

module "peering" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc-peering?ref=v60.0.0"
  prefix        = "name-prefix"
  local_network = "projects/project-1/global/networks/vpc-1"
  peer_network  = "projects/project-1/global/networks/vpc-2"
  routes_config = {
    local = { import = false }
  }
}
