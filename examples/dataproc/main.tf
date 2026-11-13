# A dataproc module call as a team has it today, after the examples in
# modules/dataproc/README.md of Cloud Foundation Fabric (Apache-2.0,
# Copyright Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

module "processing-dp-cluster" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dataproc?ref=v60.0.0"
  project_id = var.project_id
  name       = "my-cluster"
  region     = "europe-west8"
  dataproc_config = {
    cluster_config = {
      gce_cluster_config = {
        internal_ip_only = true
        service_account  = "dataproc@my-project.iam.gserviceaccount.com"
        subnetwork       = "projects/my-project/regions/europe-west8/subnetworks/subnet"
      }
      software_config = {
        image_version       = "2.2"
        override_properties = {}
      }
    }
  }
  iam = {
    "roles/dataproc.viewer" = ["group:viewers@example.com"]
  }
}
