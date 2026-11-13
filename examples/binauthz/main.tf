# A binauthz module call as a team has it today, after the example in
# modules/binauthz/README.md of Cloud Foundation Fabric (Apache-2.0,
# Copyright Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

module "binauthz" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/binauthz?ref=v60.0.0"
  project_id = var.project_id
  default_admission_rule = {
    evaluation_mode  = "ALWAYS_DENY"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    attestors        = null
  }
  cluster_admission_rules = {
    "europe-west1-c.cluster" = {
      evaluation_mode  = "REQUIRE_ATTESTATION"
      enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
      attestors        = ["test"]
    }
  }
  attestors_config = {
    "test" : {
      note_reference   = null
      pgp_public_keys  = null
      pkix_public_keys = [{
        id                  = null
        public_key_pem      = "-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE\n-----END PUBLIC KEY-----\n"
        signature_algorithm = "ECDSA_P256_SHA256"
      }]
      iam = {
        "roles/viewer" = ["user:user1@example.com"]
      }
    }
  }
}
