# Module calls that use things the charts cannot carry, and some they can:
# what `catalogtool convert` says for each. The first block is the sort of
# call a team writes over the years (a retention rate, object retention, a
# KMS key from another stack, a managed folder); the others loop, or use a
# module the catalog does not port yet.

variable "project_id" {
  type = string
}

variable "kms_key" {
  type = string
}

module "archive" {
  source                  = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v59.0.0"
  project_id              = var.project_id
  name                    = "archive"
  location                = "EU"
  storage_class           = "ARCHIVE"
  encryption_key          = var.kms_key
  enable_object_retention = true
  rpo                     = "ASYNC_TURBO"
  retention_policy = {
    retention_period = 31536000
  }
  managed_folders = {
    "reports" = { force_destroy = false }
  }
  bucket_location = "EU"
  context = {
    project_ids = { prod = "prod-project" }
  }
}

module "scratch" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/gcs?ref=v60.0.0"
  count      = 3
  project_id = var.project_id
  name       = "scratch-${count.index}"
  location   = "EU"
}

module "registry" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/container-registry?ref=v60.0.0"
  project_id = var.project_id
  location   = "EU"
}
