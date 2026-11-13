# A net-cloud-armor module call as a team has it today, after the examples
# in modules/net-cloud-armor/README.md of Cloud Foundation Fabric
# (Apache-2.0, Copyright Google LLC), pinned the way a team pins it.

module "policy" {
  source    = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-cloud-armor?ref=v60.0.0"
  name      = "test-premium"
  parent_id = { project_id = "project-1" }
  rules = {
    deny-ip = {
      priority = 1000
      action   = "deny(403)"
      match    = { src_ip_ranges = ["10.0.0.0/8"] }
    }
    throttle = {
      priority = 2000
      action   = "throttle"
      match    = { src_ip_ranges = ["*"] }
      rate_limit_options = {
        exceed_action        = "deny(429)"
        rate_limit_threshold = { count = 100, interval_sec = 60 }
        enforce_on_key       = "IP"
      }
    }
  }
}
