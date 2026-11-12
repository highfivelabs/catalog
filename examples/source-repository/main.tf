# A source-repository module call as a team has it today, after the examples
# in modules/source-repository/README.md of Cloud Foundation Fabric
# (Apache-2.0, Copyright Google LLC), pinned the way a team pins it.

module "repo" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/source-repository?ref=v60.0.0"
  project_id = "my-project"
  name       = "my-repo"
  iam = {
    "roles/source.reader" = ["user:foo@example.com"]
  }
  triggers = {
    foo = {
      filename        = "ci/workflow-foo.yaml"
      included_files  = ["**/*yaml"]
      service_account = null
      substitutions   = null
      template = {
        branch_name = "main"
        project_id  = null
        tag_name    = null
      }
    }
  }
}
