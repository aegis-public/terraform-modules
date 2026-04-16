# =============================================================================
# FTS Burst Retroactive Quarantine Pub/Sub Infrastructure
# =============================================================================

locals {
  fts_burst_enabled = var.fts_burst_config.enabled

  fts_burst_topic_name     = local.is_sub_tenant ? "fts-burst-retroactive-${local.sub_tenant_suffix}" : "fts-burst-retroactive"
  fts_burst_sub_name       = local.is_sub_tenant ? "fts-burst-retroactive-${local.sub_tenant_suffix}-sub" : "fts-burst-retroactive-sub"
  fts_burst_dlq_topic_name = local.is_sub_tenant ? "fts-burst-retroactive-${local.sub_tenant_suffix}-dlq" : "fts-burst-retroactive-dlq"
  fts_burst_dlq_sub_name   = local.is_sub_tenant ? "fts-burst-retroactive-${local.sub_tenant_suffix}-dlq-sub" : "fts-burst-retroactive-dlq-sub"
}

# ── DLQ (must exist before main subscription) ────────────────────────────────

resource "google_pubsub_topic" "fts_burst_dlq" {
  count = local.fts_burst_enabled ? 1 : 0

  name                       = local.fts_burst_dlq_topic_name
  message_retention_duration = "1209600s" # 14 days

  labels = {
    purpose = "dead-letter"
    feature = "fts-burst"
  }
}

resource "google_pubsub_subscription" "fts_burst_dlq" {
  count = local.fts_burst_enabled ? 1 : 0

  name                       = local.fts_burst_dlq_sub_name
  topic                      = google_pubsub_topic.fts_burst_dlq[0].name
  ack_deadline_seconds       = 60
  message_retention_duration = "1209600s" # 14 days

  expiration_policy {
    ttl = "" # never expire
  }
}

# P4SA needs publisher on DLQ topic (required for dead-letter forwarding)
resource "google_pubsub_topic_iam_member" "fts_burst_dlq_p4sa_publisher" {
  count = local.fts_burst_enabled ? 1 : 0

  topic  = google_pubsub_topic.fts_burst_dlq[0].name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"

  depends_on = [google_pubsub_topic.fts_burst_dlq]
}

# ── Main topic ────────────────────────────────────────────────────────────────

resource "google_pubsub_topic" "fts_burst" {
  count = local.fts_burst_enabled ? 1 : 0

  name                       = local.fts_burst_topic_name
  message_retention_duration = "604800s" # 7 days

  labels = {
    feature = "fts-burst"
  }
}

# ── Pull subscription (workspace-connector subscribes) ────────────────────────

resource "google_pubsub_subscription" "fts_burst" {
  count = local.fts_burst_enabled ? 1 : 0

  name  = local.fts_burst_sub_name
  topic = google_pubsub_topic.fts_burst[0].name

  ack_deadline_seconds       = 120       # BQ query + report submissions
  message_retention_duration = "604800s" # 7 days

  expiration_policy {
    ttl = "" # never expire
  }

  retry_policy {
    minimum_backoff = "30s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.fts_burst_dlq[0].id
    max_delivery_attempts = 10
  }

  depends_on = [
    google_pubsub_topic_iam_member.fts_burst_dlq_p4sa_publisher,
  ]
}

# P4SA needs subscriber on main subscription (required for dead-letter forwarding)
resource "google_pubsub_subscription_iam_member" "fts_burst_p4sa_subscriber" {
  count = local.fts_burst_enabled ? 1 : 0

  subscription = google_pubsub_subscription.fts_burst[0].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# ── IAM: same SA for both kraken (publisher) and AC (subscriber) ──────────────

resource "google_pubsub_topic_iam_member" "fts_burst_publisher" {
  count = local.fts_burst_enabled ? 1 : 0

  topic  = google_pubsub_topic.fts_burst[0].name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${local.workspace_connector_sa_email}"
}

resource "google_pubsub_subscription_iam_member" "fts_burst_subscriber" {
  count = local.fts_burst_enabled ? 1 : 0

  subscription = google_pubsub_subscription.fts_burst[0].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${local.workspace_connector_sa_email}"

  lifecycle {
    replace_triggered_by = [google_pubsub_subscription.fts_burst[0]]
  }
}
