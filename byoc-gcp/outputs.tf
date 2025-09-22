output "service_account_oauth_client_id" {
  value       = google_service_account.workspace_connector.unique_id
  description = "Service account client ID for workspace connector"
}
