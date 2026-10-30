mock_provider "google" {
  mock_data "google_container_cluster" {
    defaults = { workload_identity_config = [{ workload_pool = "p.svc.id.goog" }] }
  }
  mock_data "google_service_account" {
    defaults = {
      name  = "projects/p/serviceAccounts/connector@p.iam.gserviceaccount.com"
      email = "connector@p.iam.gserviceaccount.com"
    }
  }
  mock_resource "google_service_account" {
    defaults = {
      name  = "projects/p/serviceAccounts/connector@p.iam.gserviceaccount.com"
      email = "connector@p.iam.gserviceaccount.com"
    }
  }
}
mock_provider "kubernetes" {}

variables {
  message_id_queue_config = { enabled = true }
  aegis_tenant_id         = "acme"
  gke_cluster_link        = "https://container.googleapis.com/v1/projects/p/zones/z/clusters/aegis"
  kubernetes_namespace    = "acme"
  helm_ingress_url        = "https://console.example/acme"
  database = {
    create = false
    url    = "postgresql://acme:pw@localhost:5432/postgres?sslmode=disable&search_path=acme"
  }
  app_config = {
    workspace_kind          = "google"
    email_addresses         = ["a@acme.test"]
    email_domains           = ["acme.test"]
    google_workspace_config = { admin_email_address = "admin@acme.test" }
  }
  helm_values = { ingress = { host = "console.example" } }
}

run "values_object_matches_the_release_values" {
  command = apply
  assert {
    condition = [for k in sort([for k in keys(kubernetes_config_map_v1.connector_values.data) : k if endswith(k, ".yaml")]) :
    kubernetes_config_map_v1.connector_values.data[k]] == local.connector_helm_values
    error_message = "the YAML documents in the ConfigMap, in key order, must be the release's values in merge order"
  }
  assert {
    condition     = kubernetes_config_map_v1.connector_values.data["chart-version"] == local.connector_chart_version
    error_message = "the ConfigMap must carry the chart version the release is pinned to"
  }
  assert {
    condition     = kubernetes_config_map_v1.connector_values.metadata[0].name == "aegis-workspace-connector-values" && kubernetes_config_map_v1.connector_values.metadata[0].namespace == "acme"
    error_message = "the ConfigMap is named after the release, in the tenant namespace"
  }
  assert {
    condition     = yamldecode(local.connector_helm_values[length(local.connector_helm_values) - 1]) == var.helm_values
    error_message = "the tenant's own values merge last, so they win"
  }
  assert {
    condition     = !contains(keys(kubernetes_config_map_v1.connector_values.data), "20-inactive.yaml")
    error_message = "an active tenant carries no inactive layer"
  }
  assert {
    condition     = length(kubernetes_namespace_v1.connector) == 0
    error_message = "the namespace is not managed unless asked"
  }
}

run "inactive_adds_a_layer_between_platform_and_tenant" {
  command = apply
  variables {
    active = false
  }
  assert {
    condition     = yamldecode(kubernetes_config_map_v1.connector_values.data["20-inactive.yaml"]).replicaCount == 0
    error_message = "an inactive tenant's layer sets replicaCount to 0"
  }
  assert {
    condition     = yamldecode(local.connector_helm_values[2]).replicaCount == 0 && yamldecode(local.connector_helm_values[4]) == var.helm_values
    error_message = "the inactive layer sits before the tenant's values, which still merge last"
  }
}

run "managed_namespace" {
  command = apply
  variables {
    manage_namespace = true
  }
  assert {
    condition     = kubernetes_namespace_v1.connector[0].metadata[0].name == "acme"
    error_message = "manage_namespace creates the tenant namespace"
  }
}

run "sub_tenant_shares_the_parent_namespace" {
  command = apply
  variables {
    manage_namespace = true
    aegis_tenant_id  = "acme.flp"
    sub_tenant_of    = "acme"
    helm_ingress_url = "https://console.example/acme-flp"
    database = {
      create = false
      url    = "postgresql://acme:pw@localhost:5432/postgres?sslmode=disable&search_path=acme_flp"
    }
    app_config = {
      workspace_kind          = "google"
      email_addresses         = ["b@acme.test"]
      email_domains           = ["acme.test"]
      google_workspace_config = { admin_email_address = "admin@acme.test" }
    }
  }
  assert {
    condition     = length(kubernetes_namespace_v1.connector) == 0
    error_message = "a sub-tenant never creates a namespace"
  }
  assert {
    condition     = kubernetes_config_map_v1.connector_values.metadata[0].name == "aegis-workspace-connector-flp-values"
    error_message = "a sub-tenant's ConfigMap is named after its own release"
  }
}
