# A vpc-sc module call as a team has it today, after the examples in
# modules/vpc-sc/README.md of Cloud Foundation Fabric (Apache-2.0,
# Copyright Google LLC), pinned the way a team pins it.

module "vpc-sc" {
  source        = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/vpc-sc?ref=v60.0.0"
  access_policy = var.access_policy
  access_levels = {
    a1 = {
      conditions = [
        { members = ["user:user1@example.com"] }
      ]
    }
  }
  ingress_policies = {
    i1 = {
      from = {
        identity_type = "ANY_IDENTITY"
        access_levels = ["$access_levels:a1"]
      }
      to = {
        operations = [{ service_name = "storage.googleapis.com" }]
        resources  = ["projects/11111"]
      }
    }
  }
  perimeters = {
    p1 = {
      status = {
        access_levels       = ["$access_levels:a1"]
        ingress_policies    = ["$ingress_policies:i1"]
        resources           = ["projects/11111", "projects/22222"]
        restricted_services = ["storage.googleapis.com"]
      }
    }
  }
}

variable "access_policy" {
  type = string
}
