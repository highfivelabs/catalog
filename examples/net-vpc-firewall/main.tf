# A net-vpc-firewall module call as a team has it today, after the examples
# in modules/net-vpc-firewall/README.md of Cloud Foundation Fabric
# (Apache-2.0, Copyright Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

module "firewall" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc-firewall?ref=v60.0.0"
  project_id = var.project_id
  network    = "my-network"
  default_rules_config = {
    admin_ranges = ["10.0.0.0/8"]
  }
  egress_rules = {
    deny-all = {
      priority = 65000
    }
  }
  ingress_rules = {
    allow-ingress-ntp = {
      description = "Allow NTP service based on tag."
      targets     = ["ntp-svc"]
      rules       = [{ protocol = "udp", ports = ["123"] }]
    }
  }
}
