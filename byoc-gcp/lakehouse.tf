# =============================================================================
# Lakehouse Streaming Infrastructure
# Streams confirmed threats from Lookout to BigQuery via Pub/Sub
# =============================================================================

data "google_project" "current" {
  count = var.lakehouse_config.enabled ? 1 : 0
}

locals {
  lakehouse_enabled       = var.lakehouse_config.enabled
  lakehouse_project_id    = local.lakehouse_enabled ? data.google_project.current[0].project_id : null
  lakehouse_project_number = local.lakehouse_enabled ? data.google_project.current[0].number : null
}

# -----------------------------------------------------------------------------
# BigQuery Dataset & Table (in tenant project)
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Pub/Sub Topic for Lakehouse Streaming
# -----------------------------------------------------------------------------

resource "google_pubsub_topic" "lakehouse_flagged" {
  count = local.lakehouse_enabled ? 1 : 0

  name                       = "lakehouse-flagged"
  message_retention_duration = "864000s" # 10 days
}

# Dead letter topic for failed BQ writes
resource "google_pubsub_topic" "lakehouse_flagged_dlq" {
  count = local.lakehouse_enabled ? 1 : 0

  name                       = "lakehouse-flagged-dlq"
  message_retention_duration = "86400s" # 1 days
}

# -----------------------------------------------------------------------------
# BigQuery Subscription (Pub/Sub → BQ direct write)
# -----------------------------------------------------------------------------

# Grant Pub/Sub service agent permission to write to BigQuery
resource "google_bigquery_dataset_iam_member" "pubsub_bq_writer" {
  count = local.lakehouse_enabled ? 1 : 0

  dataset_id = google_bigquery_dataset.lakehouse_reporting[0].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:service-${local.lakehouse_project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription" "lakehouse_flagged_bq" {
  count = local.lakehouse_enabled ? 1 : 0

  name  = "lakehouse-flagged-bigquery"
  topic = google_pubsub_topic.lakehouse_flagged[0].id

  bigquery_config {
    table               = "${local.lakehouse_project_id}.${google_bigquery_dataset.lakehouse_reporting[0].dataset_id}.${google_bigquery_table.lakehouse_flagged[0].table_id}"
    use_table_schema    = true
    drop_unknown_fields = true
    write_metadata      = false
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.lakehouse_flagged_dlq[0].id
    max_delivery_attempts = 5
  }

  depends_on = [google_bigquery_dataset_iam_member.pubsub_bq_writer]
}

# Pull subscription for DLQ monitoring
resource "google_pubsub_subscription" "lakehouse_flagged_dlq_pull" {
  count = local.lakehouse_enabled ? 1 : 0

  name  = "lakehouse-flagged-dlq-pull"
  topic = google_pubsub_topic.lakehouse_flagged_dlq[0].id

  ack_deadline_seconds       = 600
  message_retention_duration = "604800s" # 7 days
}

# -----------------------------------------------------------------------------
# IAM: Grant Lookout (from central project) permission to publish
# -----------------------------------------------------------------------------

resource "google_pubsub_topic_iam_member" "lakehouse_publisher" {
  count = local.lakehouse_enabled ? 1 : 0

  topic  = google_pubsub_topic.lakehouse_flagged[0].name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:lookout-backend@${local.aegis_project_id}.iam.gserviceaccount.com"
}

# -----------------------------------------------------------------------------
# IAM: Grant Pub/Sub service account permissions for dead letter queue
# -----------------------------------------------------------------------------

# Allow Pub/Sub service account to publish to DLQ topic
resource "google_pubsub_topic_iam_member" "lakehouse_dlq_publisher" {
  count = local.lakehouse_enabled ? 1 : 0

  topic  = google_pubsub_topic.lakehouse_flagged_dlq[0].name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${local.lakehouse_project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# Allow Pub/Sub service account to acknowledge messages from the subscription (for DLQ forwarding)
resource "google_pubsub_subscription_iam_member" "lakehouse_dlq_subscriber" {
  count = local.lakehouse_enabled ? 1 : 0

  subscription = google_pubsub_subscription.lakehouse_flagged_bq[0].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${local.lakehouse_project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}
