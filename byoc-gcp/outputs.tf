output "service_account_oauth_client_id" {
  value       = local.is_sub_tenant ? data.google_service_account.workspace_connector_parent[0].unique_id : google_service_account.workspace_connector[0].unique_id
  description = "Service account client ID for workspace connector"
}

output "helm_release_name" {
  value       = local.helm_release_name
  description = "Name of the workspace-connector Helm release"
}

output "helm_chart_version" {
  value       = local.connector_chart_version
  description = "workspace-connector chart version the release is pinned to"
}

output "helm_values" {
  value       = local.connector_helm_values
  description = "The release's values, one YAML document per layer, in merge order"
}
