data "google_project" "project" {}

# create postgres instance
module "sql_db" {
  count = var.database.create ? 1 : 0

  source  = "GoogleCloudPlatform/sql-db/google//modules/postgresql"
  version = "~> 26.2"

  name                 = "aegis-workspace-connector"
  random_instance_name = true
  project_id           = data.google_project.project.project_id
  database_version     = "POSTGRES_15"

  enable_default_user = true
  enable_default_db   = true
}
