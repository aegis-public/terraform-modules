# pubsub topic to receive gmail inbox notifications
resource "google_pubsub_topic" "gmail_inbox" {
  name                       = "aegis-gmail-inbox"
  message_retention_duration = "864000s" # 10d
}

# pubsub subscription to deliver gmail inbox notifications to workspace connector
resource "google_pubsub_subscription" "gmail_inbox_messages_received" {
  name  = "aegis-gmail-inbox-messages-received"
  topic = google_pubsub_topic.gmail_inbox.name

  ack_deadline_seconds = 600

  push_config {
    push_endpoint = "${var.helm_ingress_url}/public/google/message_received"
    no_wrapper {
      write_metadata = true
    }
    oidc_token {
      service_account_email = google_service_account.workspace_connector.email
    }
  }

  retry_policy {
    minimum_backoff = "30s"
    maximum_backoff = "600s"
  }

}

# permission for system gmail service account to publish to the topic
resource "google_pubsub_topic_iam_member" "gmail_publisher" {
  topic  = google_pubsub_topic.gmail_inbox.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:gmail-api-push@system.gserviceaccount.com"
}

# =============================================================================
# Message ID Queue Infrastructure (Optional)
# Decouples webhook handler from message fetching for improved latency
# =============================================================================

locals {
  message_id_queue_enabled = var.message_id_queue_config.enabled
}

# Topic for message IDs (handler publishes here)
resource "google_pubsub_topic" "gmail_message_ids" {
  count = local.message_id_queue_enabled ? 1 : 0

  name                       = "aegis-gmail-message-ids"
  message_retention_duration = "864000s" # 10 days
}

# Subscription for MessageIdWorker (pulls and processes message IDs)
resource "google_pubsub_subscription" "gmail_message_ids" {
  count = local.message_id_queue_enabled ? 1 : 0

  name  = "aegis-gmail-message-ids-worker"
  topic = google_pubsub_topic.gmail_message_ids[0].name

  ack_deadline_seconds       = 60
  message_retention_duration = "604800s" # 7 days
  enable_message_ordering    = true

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

# IAM: Allow workspace connector to publish to message IDs topic
resource "google_pubsub_topic_iam_member" "gmail_message_ids_publisher" {
  count = local.message_id_queue_enabled ? 1 : 0

  topic  = google_pubsub_topic.gmail_message_ids[0].name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.workspace_connector.email}"
}

# IAM: Allow workspace connector to subscribe to message IDs subscription
resource "google_pubsub_subscription_iam_member" "gmail_message_ids_subscriber" {
  count = local.message_id_queue_enabled ? 1 : 0

  subscription = google_pubsub_subscription.gmail_message_ids[0].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.workspace_connector.email}"
}
