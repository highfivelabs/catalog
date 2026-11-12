# A datafusion module call as a team has it today, after the example in
# modules/datafusion/README.md of Cloud Foundation Fabric (Apache-2.0,
# Copyright Google LLC), pinned the way a team pins it. The range is given
# and the peering left out: the chart refuses ip_allocation_create and
# network_peering when true (charts/gcp/datafusion/README.md).

module "datafusion" {
  source               = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/datafusion?ref=v60.0.0"
  name                 = "my-datafusion"
  region               = "europe-west1"
  project_id           = "my-project"
  network              = "projects/my-project/global/networks/my-network"
  ip_allocation_create = false
  ip_allocation        = "10.0.0.0/22"
  network_peering      = false
}
