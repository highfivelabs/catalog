# A gke-hub module call as a team has it today, after the examples in
# modules/gke-hub/README.md of Cloud Foundation Fabric (Apache-2.0,
# Copyright Google LLC), pinned the way a team pins it.

module "hub" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gke-hub?ref=v60.0.0"
  project_id = "my-project"
  location   = "europe-west1"
  clusters = {
    cluster-1 = {
      id               = "projects/my-project/locations/europe-west1/clusters/cluster-1"
      configmanagement = "default"
    }
  }
  features = {
    configmanagement = true
  }
  configmanagement_templates = {
    default = {
      config_sync = {
        git = {
          sync_repo   = "https://github.com/danielmarzini/configsync-platform-example"
          policy_dir  = "configsync"
          secret_type = "none"
        }
        source_format = "hierarchy"
      }
      version = "v1"
    }
  }
}
