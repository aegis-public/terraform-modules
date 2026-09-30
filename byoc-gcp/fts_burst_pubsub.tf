# =============================================================================
# FTS Burst Pub/Sub Infrastructure
#
# Two independent paths off the same detection, each with its own enable flag so
# either can be turned on, rolled back, or left unprovisioned without touching
# the other:
#
#   retroactive quarantine (fts_burst_config.enabled)
#     Kraken publishes the threshold-crossing message only, and only once the
#     burst rule is past its rollout gate. Consumed by the clawback sweep.
#
#   SIEM alert (fts_burst_config.alert_enabled)
#     Kraken publishes every over-bar observation from the ungated telemetry
#     site, so a customer's SOC can be alerted while quarantine is still off.
#     Consumed by the workspace-connector alert dispatcher.
# =============================================================================

locals {
  fts_burst_enabled = var.fts_burst_config.enabled

  fts_burst_topic_name     = local.is_sub_tenant ? "fts-burst-retroactive-${local.sub_tenant_suffix}" : "fts-burst-retroactive"
  fts_burst_sub_name       = local.is_sub_tenant ? "fts-burst-retroactive-${local.sub_tenant_suffix}-sub" : "fts-burst-retroactive-sub"
  fts_burst_dlq_topic_name = local.is_sub_tenant ? "fts-burst-retroactive-${local.sub_tenant_suffix}-dlq" : "fts-burst-retroactive-dlq"
  fts_burst_dlq_sub_name   = local.is_sub_tenant ? "fts-burst-retroactive-${local.sub_tenant_suffix}-dlq-sub" : "fts-burst-retroactive-dlq-sub"

  fts_burst_alert_enabled = var.fts_burst_config.alert_enabled

  fts_burst_alert_topic_name     = local.is_sub_tenant ? "fts-burst-alert-${local.sub_tenant_suffix}" : "fts-burst-alert"
  fts_burst_alert_sub_name       = local.is_sub_tenant ? "fts-burst-alert-${local.sub_tenant_suffix}-sub" : "fts-burst-alert-sub"
  fts_burst_alert_dlq_topic_name = local.is_sub_tenant ? "fts-burst-alert-${local.sub_tenant_suffix}-dlq" : "fts-burst-alert-dlq"
  fts_burst_alert_dlq_sub_name   = local.is_sub_tenant ? "fts-burst-alert-${local.sub_tenant_suffix}-dlq-sub" : "fts-burst-alert-dlq-sub"
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

# =============================================================================
# SIEM alert path
# =============================================================================

# ── Alert DLQ (must exist before the alert subscription) ─────────────────────

resource "google_pubsub_topic" "fts_burst_alert_dlq" {
  count = local.fts_burst_alert_enabled ? 1 : 0

  name                       = local.fts_burst_alert_dlq_topic_name
  message_retention_duration = "1209600s" # 14 days

  labels = {
    purpose = "dead-letter"
    feature = "fts-burst-alert"
  }
}

resource "google_pubsub_subscription" "fts_burst_alert_dlq" {
  count = local.fts_burst_alert_enabled ? 1 : 0

  name                       = local.fts_burst_alert_dlq_sub_name
  topic                      = google_pubsub_topic.fts_burst_alert_dlq[0].name
  ack_deadline_seconds       = 60
  message_retention_duration = "1209600s" # 14 days

  expiration_policy {
    ttl = "" # never expire
  }
}

# P4SA needs publisher on the DLQ topic for dead-letter forwarding
resource "google_pubsub_topic_iam_member" "fts_burst_alert_dlq_p4sa_publisher" {
  count = local.fts_burst_alert_enabled ? 1 : 0

  topic  = google_pubsub_topic.fts_burst_alert_dlq[0].name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"

  depends_on = [google_pubsub_topic.fts_burst_alert_dlq]
}

# ── Alert topic ───────────────────────────────────────────────────────────────

# Retention is a day rather than the quarantine path's week: an alert says a burst
# is happening now, so a message replayed hours later is misinformation, not a
# recovered event. The dispatcher expires stale messages itself; this bound is so
# a long dispatcher outage ages out instead of accumulating a week of them.
resource "google_pubsub_topic" "fts_burst_alert" {
  count = local.fts_burst_alert_enabled ? 1 : 0

  name                       = local.fts_burst_alert_topic_name
  message_retention_duration = "86400s" # 1 day

  labels = {
    feature = "fts-burst-alert"
  }
}

# ── Pull subscription (workspace-connector alert dispatcher subscribes) ───────

# Tuned against the quarantine subscription, which budgets for a BigQuery query
# and report submissions. This path is one outbound HTTPS POST, so the deadline is
# shorter and the first retry comes sooner. Fewer delivery attempts because an
# alert loses its value as it ages: reaching the DLQ quickly is what pages us, and
# the page is the only way anyone learns a customer's endpoint went dark.
resource "google_pubsub_subscription" "fts_burst_alert" {
  count = local.fts_burst_alert_enabled ? 1 : 0

  name  = local.fts_burst_alert_sub_name
  topic = google_pubsub_topic.fts_burst_alert[0].name

  ack_deadline_seconds       = 60
  message_retention_duration = "86400s" # 1 day, matching the topic

  expiration_policy {
    ttl = "" # never expire
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.fts_burst_alert_dlq[0].id
    max_delivery_attempts = 5
  }

  depends_on = [
    google_pubsub_topic_iam_member.fts_burst_alert_dlq_p4sa_publisher,
  ]
}

# P4SA needs subscriber on the alert subscription for dead-letter forwarding
resource "google_pubsub_subscription_iam_member" "fts_burst_alert_p4sa_subscriber" {
  count = local.fts_burst_alert_enabled ? 1 : 0

  subscription = google_pubsub_subscription.fts_burst_alert[0].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# ── IAM: same SA for both kraken (publisher) and AC (subscriber) ──────────────

resource "google_pubsub_topic_iam_member" "fts_burst_alert_publisher" {
  count = local.fts_burst_alert_enabled ? 1 : 0

  topic  = google_pubsub_topic.fts_burst_alert[0].name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${local.workspace_connector_sa_email}"
}

resource "google_pubsub_subscription_iam_member" "fts_burst_alert_subscriber" {
  count = local.fts_burst_alert_enabled ? 1 : 0

  subscription = google_pubsub_subscription.fts_burst_alert[0].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${local.workspace_connector_sa_email}"

  lifecycle {
    replace_triggered_by = [google_pubsub_subscription.fts_burst_alert[0]]
  }
}
