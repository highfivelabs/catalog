# An api-gateway module call as a team has it today, after the "Create
# service account" example in modules/api-gateway/README.md of Cloud
# Foundation Fabric (Apache-2.0, Copyright Google LLC), pinned the way a
# team pins it.

variable "project_id" {
  type = string
}

module "gateway" {
  source                 = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/api-gateway?ref=v60.0.0"
  project_id             = var.project_id
  api_id                 = "orders"
  region                 = "europe-west1"
  service_account_create = true
  iam = {
    "roles/apigateway.viewer" = ["group:orders-readers@example.com"]
  }
  spec = <<EOT
swagger: "2.0"
info:
  title: orders
  version: "1.0.0"
paths:
  /orders:
    get:
      operationId: listOrders
      x-google-backend:
        address: https://orders.example.com
      responses:
        "200":
          description: OK
EOT
}
