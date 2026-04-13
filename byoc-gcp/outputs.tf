output "service_account_oauth_client_id" {
  value       = local.is_sub_tenant ? data.google_service_account.workspace_connector_parent[0].unique_id : google_service_account.workspace_connector[0].unique_id
  description = "Service account client ID for workspace connector"
}
