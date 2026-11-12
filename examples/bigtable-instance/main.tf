# A bigtable-instance module call as a team has it today, after the examples
# in modules/bigtable-instance/README.md of Cloud Foundation Fabric
# (Apache-2.0, Copyright Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

module "bigtable-instance" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/bigtable-instance?ref=v60.0.0"
  project_id = var.project_id
  name       = "instance"
  clusters = {
    my-cluster = {
      zone = "europe-west1-b"
    }
  }
  tables = {
    table-0 = {}
    table-1 = {
      column_families = {
        cf1 = {}
        cf2 = {
          gc_policy = { max_version = "7" }
        }
      }
    }
  }
  iam = {
    "roles/bigtable.user" = ["user:me@example.com"]
  }
}
