# A kms module call as a team has it today, after the examples in
# modules/kms/README.md of Cloud Foundation Fabric (Apache-2.0, Copyright
# Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

variable "app_sa" {
  type = string
}

module "kms" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/kms?ref=v60.0.0"
  project_id = var.project_id
  keyring = {
    location = "europe-west1"
    name     = "app"
  }
  iam = {
    "roles/cloudkms.admin" = ["group:kms-admins@example.org"]
  }
  keys = {
    data = {
      rotation_period = "7776000s"
      iam_bindings_additive = {
        app = {
          member = "serviceAccount:${var.app_sa}"
          role   = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
        }
      }
    }
  }
}
