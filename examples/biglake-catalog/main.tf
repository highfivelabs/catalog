# A biglake-catalog module call as a team has it today, after the example
# in modules/biglake-catalog/README.md of Cloud Foundation Fabric
# (Apache-2.0, Copyright Google LLC), pinned the way a team pins it.

variable "project_id" {
  type = string
}

module "biglake_catalog" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/biglake-catalog?ref=v60.0.0"
  project_id = var.project_id
  name       = "my_catalog"
  location   = "US"
  databases = {
    my_database = {
      type = "HIVE"
      hive_options = {
        location_uri = "gs://my-bucket/my-database-folder"
        parameters = {
          "owner" : "John Doe"
        }
      }
      tables = {
        my_table = {
          type = "HIVE"
          hive_options = {
            table_type    = "MANAGED_TABLE"
            location_uri  = "gs://my-bucket/my-table-folder"
            input_format  = "org.apache.hadoop.mapred.SequenceFileInputFormat"
            output_format = "org.apache.hadoop.hive.ql.io.HiveSequenceFileOutputFormat"
            parameters = {
              "provider" = "iceberg"
              "owner"    = "John Doe"
            }
          }
        }
      }
    }
  }
}
