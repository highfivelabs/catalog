# A pubsub module call as a team has it today, after the examples in
# modules/pubsub/README.md of Cloud Foundation Fabric (Apache-2.0, Copyright
# Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

module "pubsub" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/pubsub?ref=v60.0.0"
  project_id = var.project_id
  name       = "my-topic"
  iam = {
    "roles/pubsub.publisher" = ["group:publishers@example.org"]
  }
  subscriptions = {
    test-pull = {
      ack_deadline_seconds = 20
      retry_policy = {
        minimum_backoff = 10
        maximum_backoff = 300
      }
    }
    test-push = {
      push = {
        endpoint = "https://example.com/foo"
      }
    }
  }
}
