# =============================================================================
# Lakehouse v1 reporting table (historical)
# The per-tenant reporting.flagged table is retained for historical data only;
# nothing writes to it. The central v2 lakehouse (lakehouse.events_customer)
# is the live pipeline.
# =============================================================================

locals {
  lakehouse_enabled = var.lakehouse_config.enabled
}

resource "google_bigquery_dataset" "lakehouse_reporting" {
  count = local.lakehouse_enabled ? 1 : 0

  dataset_id = "reporting"
  location   = "US"

  labels = {
    env = "prod"
  }
}

resource "google_bigquery_table" "lakehouse_flagged" {
  count = local.lakehouse_enabled ? 1 : 0

  dataset_id = google_bigquery_dataset.lakehouse_reporting[0].dataset_id
  table_id   = "flagged"

  time_partitioning {
    type  = "DAY"
    field = "received_at"
  }

  clustering = ["email_address", "message_id"]

  schema = file("${path.module}/schemas/lakehouse_flagged.json")
}
