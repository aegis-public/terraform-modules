# pubsub topic to receive gmail inbox notifications
resource "google_pubsub_topic" "gmail_inbox" {
  project = var.project_id

  name                       = "gmail-inbox"
  message_retention_duration = "864000s" # 10d
}

# pubsub subscription to deliver gmail inbox notifications to workspace connector
resource "google_pubsub_subscription" "gmail_inbox_messages_received" {
  project = var.project_id

  name  = "gmail-inbox-messages-received"
  topic = google_pubsub_topic.gmail_inbox.name

  ack_deadline_seconds = 10

  push_config {
    push_endpoint = "${var.workspace_connector_http_url}/google/message_received"
    no_wrapper {
      write_metadata = true
    }
    oidc_token {
      service_account_email = google_service_account.workspace_connector.email
    }
  }
}

# permission for system gmail service account to publish to the topic
resource "google_pubsub_topic_iam_member" "gmail_publisher" {
  project = var.project_id

  topic  = google_pubsub_topic.gmail_inbox.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:gmail-api-push@system.gserviceaccount.com"
}
