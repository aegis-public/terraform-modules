# service account for workspace connector
resource "google_service_account" "workspace_connector" {
  project      = var.project_id

  account_id   = "aegis-workspace-connector"
  display_name = "Aegis Workspace Connector"
}

# allow kubernetes service account to impersonate gcp service account
resource "google_service_account_iam_member" "workspace_connector_wif" {
  service_account_id = google_service_account.workspace_connector.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.workload_identity_pool}[${var.kubernetes_namespace}/${var.kubernetes_service_account}]"
}

# allow gcp service account to create tokens for itself (for domain wide delegation)
resource "google_service_account_iam_member" "workspace_connector_token_creator" {
  service_account_id = google_service_account.workspace_connector.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.workspace_connector.email}"
}
