# A net-firewall-policy module call as a team has it today, after the
# examples in modules/net-firewall-policy/README.md of Cloud Foundation
# Fabric (Apache-2.0, Copyright Google LLC), pinned the way a team pins it.

module "firewall-policy" {
  source      = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-firewall-policy?ref=v60.0.0"
  name        = "test-1"
  parent_id   = var.project_id
  region      = "global"
  attachments = {
    my-vpc = "projects/my-project/global/networks/my-vpc"
  }
  egress_rules = {
    smtp = {
      priority = 900
      match = {
        destination_ranges = ["0.0.0.0/0"]
        layer4_configs     = [{ protocol = "tcp", ports = ["25"] }]
      }
    }
  }
  ingress_rules = {
    icmp = {
      priority       = 1000
      enable_logging = true
      match = {
        source_ranges  = ["0.0.0.0/0"]
        layer4_configs = [{ protocol = "icmp" }]
      }
    }
  }
}

variable "project_id" {
  type = string
}
