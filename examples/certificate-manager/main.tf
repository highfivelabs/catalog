# A certificate-manager module call as a team has it today, after the
# examples in modules/certificate-manager/README.md of Cloud Foundation
# Fabric (Apache-2.0, Copyright Google LLC), pinned the way a team pins it.

module "certificate-manager" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/certificate-manager?ref=v60.0.0"
  project_id = "project-1"
  map = {
    name        = "my-certificate-map"
    description = "My certificate map"
    entries = {
      mycertentry = {
        certificates = ["mycert"]
        hostname     = "example.com"
      }
    }
  }
  certificates = {
    mycert = {
      managed = {
        domains            = ["example.com"]
        dns_authorizations = ["example-com"]
      }
    }
  }
  dns_authorizations = {
    example-com = {
      type   = "PER_PROJECT_RECORD"
      domain = "example.com"
    }
  }
}
