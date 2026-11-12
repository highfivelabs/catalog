# An artifact-registry module call as a team has it today, after the
# examples in modules/artifact-registry/README.md of Cloud Foundation Fabric
# (Apache-2.0, Copyright Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

variable "ci_sa" {
  type = string
}

module "docker-artifact-registry" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/artifact-registry?ref=v60.0.0"
  project_id = var.project_id
  location   = "europe-west1"
  name       = "docker-registry"
  format = {
    docker = {
      standard = {
        immutable_tags = true
      }
    }
  }
  cleanup_policies = {
    keep-5-versions = {
      action = "KEEP"
      most_recent_versions = {
        keep_count = 5
      }
    }
  }
  iam = {
    "roles/artifactregistry.writer" = ["serviceAccount:${var.ci_sa}"]
  }
}
