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
  helm_ingress_url        = "https://console.example/acme/workspace-connector"
  database                = { create = false }
  external_secrets = {
    env = { AEGIS_MICROSOFT_CLIENT_STATE = "azure-client-state", AEGIS_RESTORE_LINK_SIGNING_KEY = "restore-link-signing-key" }
  }
  app_config = {
    workspace_kind             = "microsoft"
    email_addresses            = ["*"]
    email_domains              = ["*"]
    microsoft_workspace_config = { tenant_id = "t", client_id = "c" }
    env                        = { AEGIS_QUARANTINE_MODE = "defang_request_restore" }
  }
  helm_values = {
    ingress = {
      className   = "nginx"
      host        = "console.example"
      path        = "/acme/workspace-connector/(public/.*)"
      pathType    = "ImplementationSpecific"
      annotations = { "nginx.ingress.kubernetes.io/rewrite-target" = "/$1" }
    }
    extraIngresses = [{
      name        = "aegis-workspace-connector-restore"
      className   = "nginx"
      host        = "console.example"
      path        = "/acme/(restore.*)"
      pathType    = "ImplementationSpecific"
      tls         = { enabled = true }
      annotations = { "nginx.ingress.kubernetes.io/rewrite-target" = "/$1" }
    }]
  }
}

run "inline_renders_what_0_5_rendered_plus_the_switches" {
  command = apply
  assert {
    condition     = yamldecode(local.connector_helm_values[0]).config.env == { for k, v in local.connector_plain_env : k => v }
    error_message = "inline mode renders the plain env into config.env as before"
  }
  assert {
    condition     = !yamldecode(local.connector_helm_values[0]).envConfigMap.enabled && !yamldecode(local.connector_helm_values[0]).reloader.enabled
    error_message = "inline mode leaves the ConfigMap envFrom and Reloader off"
  }
  assert {
    condition     = yamldecode(local.connector_helm_values[0]).ingress.render && yamldecode(local.connector_helm_values[0]).externalSecret.render
    error_message = "inline mode keeps the chart rendering the ExternalSecret and the Ingresses"
  }
  assert {
    condition     = contains(keys(yamldecode(local.connector_helm_values[length(local.connector_helm_values) - 1])), "ingress") && contains(keys(yamldecode(local.connector_helm_values[length(local.connector_helm_values) - 1])), "extraIngresses")
    error_message = "inline mode keeps the tenant's ingress values in the tenant document, where the chart reads them"
  }
  assert {
    condition     = kubernetes_config_map_v1.connector_values.data["env-delivery"] == "inline" && kubernetes_config_map_v1.connector_values.data["chart-version"] == "0.1.43"
    error_message = "the values ConfigMap carries the mode and the chart version"
  }
}

run "the_env_configmap_holds_the_plain_env_without_nulls_or_secrets" {
  command = apply
  assert {
    condition     = kubernetes_config_map_v1.connector_env_vars.metadata[0].name == "aegis-workspace-connector-env-vars"
    error_message = "the env ConfigMap is named after the release"
  }
  assert {
    condition     = kubernetes_config_map_v1.connector_env_vars.data.AEGIS_QUARANTINE_MODE == "defang_request_restore" && kubernetes_config_map_v1.connector_env_vars.data.AEGIS_TENANT_ID == "acme"
    error_message = "the tenant's env and the inferred env are in the ConfigMap"
  }
  assert {
    condition     = !contains(keys(kubernetes_config_map_v1.connector_env_vars.data), "AEGIS_GMAIL_INBOX_PULL_SUBSCRIPTION")
    error_message = "a null inferred value is absent, the way helm drops it"
  }
  assert {
    condition     = length(setintersection(keys(kubernetes_config_map_v1.connector_env_vars.data), ["PGPASSWORD", "AEGIS_MICROSOFT_CLIENT_STATE", "AEGIS_RESTORE_LINK_SIGNING_KEY"])) == 0
    error_message = "secret-backed keys never land in the env ConfigMap"
  }
}

run "configmap_mode_moves_the_env_and_the_rendering" {
  command = apply
  variables {
    env_delivery = "configmap"
  }
  assert {
    condition     = yamldecode(local.connector_helm_values[0]).config.env == {}
    error_message = "configmap mode renders no inline env"
  }
  assert {
    condition     = yamldecode(local.connector_helm_values[0]).envConfigMap.enabled && yamldecode(local.connector_helm_values[0]).envConfigMap.name == "aegis-workspace-connector-env-vars" && yamldecode(local.connector_helm_values[0]).reloader.enabled
    error_message = "configmap mode turns on the ConfigMap envFrom and Reloader"
  }
  assert {
    condition     = !yamldecode(local.connector_helm_values[0]).ingress.render && !yamldecode(local.connector_helm_values[0]).externalSecret.render && yamldecode(local.connector_helm_values[0]).externalSecret.enabled
    error_message = "configmap mode stops the chart rendering the ExternalSecret and the Ingresses but keeps the Secret's envFrom"
  }
  assert {
    condition     = !contains(keys(yamldecode(local.connector_helm_values[length(local.connector_helm_values) - 1])), "ingress") && !contains(keys(yamldecode(local.connector_helm_values[length(local.connector_helm_values) - 1])), "extraIngresses")
    error_message = "configmap mode leaves the tenant's ingress values out of the tenant document: the chart renders no Ingress from them"
  }
  assert {
    condition     = length(kubernetes_ingress_v1.connector) == 1 && kubernetes_ingress_v1.extra["aegis-workspace-connector-restore"].spec[0].rule[0].http[0].path[0].path == "/acme/(restore.*)"
    error_message = "configmap mode still creates the Ingresses from helm_values"
  }
  assert {
    condition     = kubernetes_config_map_v1.connector_values.data["env-delivery"] == "configmap"
    error_message = "the values ConfigMap says configmap"
  }
}

run "the_external_secret_matches_what_the_chart_renders" {
  command = apply
  assert {
    condition     = kubernetes_manifest.external_secret[0].manifest.metadata.name == "aegis-workspace-connector-env" && kubernetes_manifest.external_secret[0].manifest.spec.target.name == "aegis-workspace-connector-env"
    error_message = "the ExternalSecret and its target Secret are named after the release"
  }
  assert {
    condition     = [for d in kubernetes_manifest.external_secret[0].manifest.spec.data : d.secretKey] == ["AEGIS_MICROSOFT_CLIENT_STATE", "AEGIS_RESTORE_LINK_SIGNING_KEY", "PGPASSWORD"]
    error_message = "the data entries are in key order, as helm renders them"
  }
  assert {
    condition     = [for d in kubernetes_manifest.external_secret[0].manifest.spec.data : d.remoteRef.key][2] == "acme-postgresql-password"
    error_message = "PGPASSWORD maps to the default password secret"
  }
  assert {
    condition     = kubernetes_manifest.external_secret[0].manifest.metadata.annotations["helm.sh/resource-policy"] == "keep"
    error_message = "the ExternalSecret carries the keep policy"
  }
}

run "the_ingresses_match_what_the_chart_renders" {
  command = apply
  assert {
    condition     = kubernetes_ingress_v1.connector[0].metadata[0].name == "aegis-workspace-connector" && kubernetes_ingress_v1.connector[0].metadata[0].annotations["nginx.ingress.kubernetes.io/proxy-body-size"] == "10m" && kubernetes_ingress_v1.connector[0].metadata[0].annotations["nginx.ingress.kubernetes.io/rewrite-target"] == "/$1"
    error_message = "the main Ingress carries the chart's proxy annotations and the tenant's own"
  }
  assert {
    condition     = length(kubernetes_ingress_v1.connector[0].spec[0].tls) == 1 && kubernetes_ingress_v1.connector[0].spec[0].rule[0].http[0].path[0].backend[0].service[0].port[0].number == 8080
    error_message = "the main Ingress has TLS on and routes to the Service port"
  }
  assert {
    condition     = kubernetes_ingress_v1.extra["aegis-workspace-connector-restore"].spec[0].rule[0].http[0].path[0].path == "/acme/(restore.*)" && !contains(keys(kubernetes_ingress_v1.extra["aegis-workspace-connector-restore"].metadata[0].annotations), "nginx.ingress.kubernetes.io/proxy-body-size")
    error_message = "an extra Ingress keeps its own path and gets no proxy annotations"
  }
}

run "configmap_mode_needs_external_secrets" {
  command = plan
  variables {
    env_delivery     = "configmap"
    external_secrets = null
    database         = { create = false, url = "postgresql://acme:pw@localhost:5432/postgres?sslmode=disable" }
    app_config = {
      workspace_kind          = "google"
      email_addresses         = ["*"]
      email_domains           = ["*"]
      google_workspace_config = { admin_email_address = "admin@acme.test" }
    }
  }
  expect_failures = [var.env_delivery]
}

run "an_extra_ingress_is_named_after_the_release" {
  command = plan
  variables {
    helm_values = {
      ingress        = { host = "console.example", path = "/acme/(public/.*)" }
      extraIngresses = [{ name = "restore", host = "console.example", path = "/acme/(restore.*)" }]
    }
  }
  expect_failures = [kubernetes_ingress_v1.extra]
}
