# =============================================================================
# Pub/Sub Infrastructure
# =============================================================================

locals {
  is_google_workspace    = var.app_config.workspace_kind == "google"
  is_microsoft_workspace = var.app_config.workspace_kind == "microsoft"

  gmail_message_id_queue_enabled   = local.is_google_workspace && var.message_id_queue_config.enabled
  outlook_message_id_queue_enabled = local.is_microsoft_workspace && var.message_id_queue_config.enabled

  # Resource name suffixes: scoped for sub-tenants, default for standalone tenants.
  gmail_inbox_topic_name        = local.is_sub_tenant ? "aegis-gmail-inbox-${local.sub_tenant_suffix}" : "aegis-gmail-inbox"
  gmail_inbox_sub_name          = local.is_sub_tenant ? "aegis-gmail-inbox-${local.sub_tenant_suffix}-messages-received" : "aegis-gmail-inbox-messages-received"
  gmail_message_ids_topic_name  = local.is_sub_tenant ? "aegis-gmail-message-ids-${local.sub_tenant_suffix}" : "aegis-gmail-message-ids"
  gmail_message_ids_sub_name    = local.is_sub_tenant ? "aegis-gmail-message-ids-${local.sub_tenant_suffix}-worker" : "aegis-gmail-message-ids-worker"
  outlook_message_ids_topic_name = local.is_sub_tenant ? "aegis-outlook-message-ids-${local.sub_tenant_suffix}" : "aegis-outlook-message-ids"
  outlook_message_ids_sub_name   = local.is_sub_tenant ? "aegis-outlook-message-ids-${local.sub_tenant_suffix}-worker" : "aegis-outlook-message-ids-worker"
}

# pubsub topic to receive gmail inbox notifications
resource "google_pubsub_topic" "gmail_inbox" {
  count = local.is_google_workspace ? 1 : 0

  name                       = local.gmail_inbox_topic_name
  message_retention_duration = "1800s" # 30m
}

# pubsub subscription to deliver gmail inbox notifications to workspace connector
resource "google_pubsub_subscription" "gmail_inbox_messages_received" {
  count = local.is_google_workspace ? 1 : 0

  name  = local.gmail_inbox_sub_name
  topic = google_pubsub_topic.gmail_inbox[0].name

  ack_deadline_seconds = var.gmail_inbox_subscription.ack_deadline_seconds

  expiration_policy {
    ttl = "" # never expire; connector may be paused (replicaCount=0) and auto-deletion breaks Gmail push
  }

  push_config {
    push_endpoint = "${var.helm_ingress_url}/public/google/message_received"
    no_wrapper {
      write_metadata = true
    }
    oidc_token {
      service_account_email = local.workspace_connector_sa_email
    }
  }

  # drop unacked notifications after 30m
  message_retention_duration = "1800s"

  retry_policy {
    minimum_backoff = var.gmail_inbox_subscription.retry_minimum_backoff
    maximum_backoff = var.gmail_inbox_subscription.retry_maximum_backoff
  }

}

# permission for system gmail service account to publish to the topic
resource "google_pubsub_topic_iam_member" "gmail_publisher" {
  count = local.is_google_workspace ? 1 : 0

  topic  = google_pubsub_topic.gmail_inbox[0].name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:gmail-api-push@system.gserviceaccount.com"
}

# =============================================================================
# Message ID Queue Infrastructure (Optional, Google Workspace only)
# Decouples webhook handler from message fetching for improved latency
# =============================================================================

# Topic for message IDs (handler publishes here)
resource "google_pubsub_topic" "gmail_message_ids" {
  count = local.gmail_message_id_queue_enabled ? 1 : 0

  name                       = local.gmail_message_ids_topic_name
  message_retention_duration = "864000s" # 10 days
}

# Subscription for MessageIdWorker (pulls and processes message IDs)
resource "google_pubsub_subscription" "gmail_message_ids" {
  count = local.gmail_message_id_queue_enabled ? 1 : 0

  name  = local.gmail_message_ids_sub_name
  topic = google_pubsub_topic.gmail_message_ids[0].name

  ack_deadline_seconds       = 60
  message_retention_duration = "604800s" # 7 days
  enable_message_ordering    = true

  expiration_policy {
    ttl = "" # never expire
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

# IAM: Allow workspace connector to publish to message IDs topic
resource "google_pubsub_topic_iam_member" "gmail_message_ids_publisher" {
  count = local.gmail_message_id_queue_enabled ? 1 : 0

  topic  = google_pubsub_topic.gmail_message_ids[0].name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${local.workspace_connector_sa_email}"
}

# IAM: Allow workspace connector to subscribe to message IDs subscription
resource "google_pubsub_subscription_iam_member" "gmail_message_ids_subscriber" {
  count = local.gmail_message_id_queue_enabled ? 1 : 0

  subscription = google_pubsub_subscription.gmail_message_ids[0].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${local.workspace_connector_sa_email}"

  lifecycle {
    replace_triggered_by = [google_pubsub_subscription.gmail_message_ids[0]]
  }
}

# =============================================================================
# Message ID Queue Infrastructure (Optional, Microsoft/Outlook only)
# Decouples webhook handler from message fetching for improved latency
# =============================================================================

# Topic for Outlook message IDs (handler publishes here)
resource "google_pubsub_topic" "outlook_message_ids" {
  count = local.outlook_message_id_queue_enabled ? 1 : 0

  name                       = local.outlook_message_ids_topic_name
  message_retention_duration = "864000s" # 10 days
}

# Subscription for MessageIdWorker (pulls and processes Outlook message IDs)
resource "google_pubsub_subscription" "outlook_message_ids" {
  count = local.outlook_message_id_queue_enabled ? 1 : 0

  name  = local.outlook_message_ids_sub_name
  topic = google_pubsub_topic.outlook_message_ids[0].name

  ack_deadline_seconds       = 60
  message_retention_duration = "604800s" # 7 days
  enable_message_ordering    = true

  expiration_policy {
    ttl = "" # never expire; connector may be paused (replicaCount=0) and auto-deletion breaks message processing
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

# IAM: Allow workspace connector to publish to Outlook message IDs topic
resource "google_pubsub_topic_iam_member" "outlook_message_ids_publisher" {
  count = local.outlook_message_id_queue_enabled ? 1 : 0

  topic  = google_pubsub_topic.outlook_message_ids[0].name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${local.workspace_connector_sa_email}"
}

# IAM: Allow workspace connector to subscribe to Outlook message IDs subscription
resource "google_pubsub_subscription_iam_member" "outlook_message_ids_subscriber" {
  count = local.outlook_message_id_queue_enabled ? 1 : 0

  subscription = google_pubsub_subscription.outlook_message_ids[0].name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${local.workspace_connector_sa_email}"

  lifecycle {
    replace_triggered_by = [google_pubsub_subscription.outlook_message_ids[0]]
  }
}
