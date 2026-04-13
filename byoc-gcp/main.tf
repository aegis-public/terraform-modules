locals {
  is_sub_tenant = var.sub_tenant_of != null

  # Suffix used to scope connector resource names (topics, Helm release) when this
  # is a sub-tenant.  Derived from the sub-tenant portion of aegis_tenant_id after
  # removing the parent prefix, with dots replaced by dashes.
  # Example: aegis_tenant_id="acme.sub", sub_tenant_of="acme" → sub_tenant_suffix="sub"
  sub_tenant_suffix = local.is_sub_tenant ? replace(
    trimprefix(var.aegis_tenant_id, "${var.sub_tenant_of}."),
    ".", "-"
  ) : ""
}

# ---------------------------------------------------------------------------
# GCP Service Account
# ---------------------------------------------------------------------------

# Standalone tenant: create a dedicated service account.
resource "google_service_account" "workspace_connector" {
  count = local.is_sub_tenant ? 0 : 1

  account_id   = var.gcp_service_account_id
  display_name = "Aegis Workspace Connector"
  lifecycle {
    ignore_changes = [display_name, description]
  }
}

# Sub-tenant: look up the parent's existing service account (no new SA created).
data "google_service_account" "workspace_connector_parent" {
  count = local.is_sub_tenant ? 1 : 0

  account_id = var.gcp_service_account_id
}

locals {
  workspace_connector_sa_email = local.is_sub_tenant ? data.google_service_account.workspace_connector_parent[0].email : google_service_account.workspace_connector[0].email
  workspace_connector_sa_name  = local.is_sub_tenant ? data.google_service_account.workspace_connector_parent[0].name : google_service_account.workspace_connector[0].name
}

# ---------------------------------------------------------------------------
# GKE / Workload Identity
# ---------------------------------------------------------------------------

data "google_container_cluster" "primary" {
  # https://container.googleapis.com/v1/projects/friendly-access-450904-h1/zones/us-central1-a/clusters/aegis
  name     = regex("^.*/clusters/(.*)$", var.gke_cluster_link)[0]
  location = regex("^.*/zones/(.*)/clusters/.*$", var.gke_cluster_link)[0]
  project  = regex("^.*/projects/(.*)/zones/.*$", var.gke_cluster_link)[0]
}

locals {
  kubernetes_service_account = local.helm_release_name
  workload_identity_pool     = data.google_container_cluster.primary.workload_identity_config[0].workload_pool
}

# Bind the k8s service account to the GCP SA (works for both standalone and sub-tenant).
resource "google_service_account_iam_member" "workspace_connector_wif" {
  service_account_id = local.workspace_connector_sa_name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.workload_identity_pool}[${var.kubernetes_namespace}/${local.kubernetes_service_account}]"
}

# Allow the SA to create tokens for itself (domain-wide delegation).
# Skipped for sub-tenants: the parent SA already has this binding.
resource "google_service_account_iam_member" "workspace_connector_token_creator" {
  count = local.is_sub_tenant ? 0 : 1

  service_account_id = local.workspace_connector_sa_name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${local.workspace_connector_sa_email}"
}
