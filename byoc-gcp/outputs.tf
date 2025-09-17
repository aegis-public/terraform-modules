output "pubsub_topic_name" {
  value       = google_pubsub_topic.gmail_inbox.id
  description = "Pubsub topic name for gmail inbox notifications"
}

output "service_account_email" {
  value       = google_service_account.workspace_connector.email
  description = "Service account email for workspace connector"
}

output "service_account_oauth_client_id" {
  value       = google_service_account.workspace_connector.unique_id
  description = "Service account client ID for workspace connector"
}
