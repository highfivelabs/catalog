# A cloud-identity-group module call as a team has it today, after the
# examples in modules/cloud-identity-group/README.md of Cloud Foundation
# Fabric (Apache-2.0, Copyright Google LLC), pinned the way a team pins it.

module "group" {
  source       = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/cloud-identity-group?ref=v60.0.0"
  customer_id  = "customers/C01234567"
  name         = "mygroup@example.com"
  display_name = "My group name"
  description  = "My group Description"
  managers = [
    "user1@example.com"
  ]
  members = [
    "user2@example.com",
    "user3@example.com"
  ]
}
