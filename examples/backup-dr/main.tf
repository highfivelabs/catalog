# A backup-dr module call as a team has it today, after the "Create vault
# and plan" example in modules/backup-dr/README.md of Cloud Foundation
# Fabric (Apache-2.0, Copyright Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

module "dr" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/backup-dr?ref=v60.0.0"
  project_id = var.project_id
  location   = "us-central1"
  name       = "backup-vault"
  backup_plans = {
    my-backup-plan = {
      resource_type = "compute.googleapis.com/Instance"
      description   = "Backup Plan for GCE Instances."
      backup_rules = [
        {
          rule_id               = "daily-backup-rule"
          backup_retention_days = 30
          standard_schedule = {
            recurrence_type  = "HOURLY"
            hourly_frequency = 6
            time_zone        = "America/Los_Angeles"
            backup_window = {
              start_hour_of_day = 1
              end_hour_of_day   = 5
            }
          }
        }
      ]
    }
  }
}
