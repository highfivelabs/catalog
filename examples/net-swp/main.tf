# A net-swp module call as a team has it today, after the "Secure Web Proxy
# with rules" example in modules/net-swp/README.md of Cloud Foundation
# Fabric (Apache-2.0, Copyright Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

module "secure-web-proxy" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-swp?ref=v60.0.0"
  project_id = var.project_id
  region     = "europe-west4"
  name       = "secure-web-proxy"
  network    = "projects/my-project/global/networks/my-network"
  subnetwork = "projects/my-project/regions/europe-west4/subnetworks/my-subnetwork"
  certificates = [
    "projects/my-project/locations/europe-west4/certificates/secure-web-proxy-cert"
  ]
  gateway_config = {
    addresses = ["10.142.68.3"]
    ports     = [80, 443]
  }
  policy_rules = {
    host-0 = {
      priority        = 1000
      allow           = false
      session_matcher = "host() == 'google.com'"
    }
    url-list-0 = {
      priority        = 1001
      session_matcher = "inUrlList(host(), '%s')"
      matcher_args = {
        session = ["url_list:default"]
      }
    }
  }
  url_lists = {
    default = {
      values = ["example.org"]
    }
  }
}
