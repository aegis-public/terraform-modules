# service account for workspace connector
resource "google_service_account" "workspace_connector" {
  account_id   = var.gcp_service_account_id
  display_name = "Aegis Workspace Connector"
}

data "google_container_cluster" "primary" {
  # https://container.googleapis.com/v1/projects/friendly-access-450904-h1/zones/us-central1-a/clusters/aegis
  name     = regex("^.*/clusters/(.*)$", var.gke_cluster_link)[0]
  location = regex("^.*/zones/(.*)/clusters/.*$", var.gke_cluster_link)[0]
  project  = regex("^.*/projects/(.*)/zones/.*$", var.gke_cluster_link)[0]
}

locals {
  kubernetes_service_account = helm_release.workspace_connector.name
  workload_identity_pool     = data.google_container_cluster.primary.workload_identity_config[0].workload_pool
}

# allow kubernetes service account to impersonate gcp service account
resource "google_service_account_iam_member" "workspace_connector_wif" {
  service_account_id = google_service_account.workspace_connector.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.workload_identity_pool}[${var.kubernetes_namespace}/${local.kubernetes_service_account}]"
}

# allow gcp service account to create tokens for itself (for domain wide delegation)
resource "google_service_account_iam_member" "workspace_connector_token_creator" {
  service_account_id = google_service_account.workspace_connector.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.workspace_connector.email}"
}
