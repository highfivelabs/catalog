# A dns module call as a team has it today, after the examples in
# modules/dns/README.md of Cloud Foundation Fabric (Apache-2.0, Copyright
# Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

variable "network" {
  type = string
}

module "private-dns" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/dns?ref=v60.0.0"
  project_id = var.project_id
  name       = "test-example"
  zone_config = {
    domain = "test.example."
    private = {
      client_networks = [var.network]
    }
  }
  recordsets = {
    "A localhost" = { records = ["127.0.0.1"] }
    "A myhost"    = { ttl = 600, records = ["10.0.0.120"] }
  }
  iam = {
    "roles/dns.admin" = ["group:dns-administrators@example.org"]
  }
}
