# A service-directory module call as a team has it today, after the examples
# in modules/service-directory/README.md of Cloud Foundation Fabric
# (Apache-2.0, Copyright Google LLC), pinned the way a team pins it.

module "service-directory" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/service-directory?ref=v60.0.0"
  project_id = "my-project"
  location   = "europe-west1"
  name       = "sd-1"
  services = {
    one = {
      endpoints = ["first", "second"]
      metadata  = null
    }
  }
  service_iam = {
    one = {
      "roles/servicedirectory.editor" = [
        "serviceAccount:service-editor.example.com"
      ]
    }
  }
  endpoint_config = {
    "one/first"  = { address = "127.0.0.1", port = 80, metadata = {} }
    "one/second" = { address = "127.0.0.2", port = 80, metadata = {} }
  }
}
