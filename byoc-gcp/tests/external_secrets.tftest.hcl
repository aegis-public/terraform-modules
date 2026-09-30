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
mock_provider "helm" {}

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
}

run "off_is_unchanged" {
  command = apply
  assert {
    condition     = yamldecode(helm_release.workspace_connector.values[0]) == { config = { env = merge(local.inferred_env_vars, var.app_config.env) } }
    error_message = "without external_secrets the Helm values must be exactly today's"
  }
  assert {
    condition     = yamldecode(helm_release.workspace_connector.values[0]).config.env.AEGIS_DATABASE_URL == var.database.url
    error_message = "the passed URL must still reach the pod"
  }
}

run "on_google_defaults" {
  command = apply
  variables {
    database         = { create = false }
    external_secrets = {}
  }
  assert {
    condition     = yamldecode(helm_release.workspace_connector.values[0]).config.env.AEGIS_DATABASE_URL == "postgresql://acme@localhost:5432/postgres?sslmode=disable&search_path=acme"
    error_message = "the DB URL must carry no password and default user and schema to the tenant ID"
  }
  assert {
    condition     = yamldecode(helm_release.workspace_connector.values[0]).externalSecret.env == { PGPASSWORD = "acme-postgresql-password" }
    error_message = "the password secret must default to <tenant>-postgresql-password"
  }
}

run "on_overrides_and_microsoft_env" {
  command = apply
  variables {
    database = { create = false }
    app_config = {
      workspace_kind             = "microsoft"
      email_addresses            = ["a@acme.test"]
      email_domains              = ["acme.test"]
      microsoft_workspace_config = { tenant_id = "t", client_id = "c" }
    }
    external_secrets = {
      database = { user = "acme_x", password_secret = "acme-x-postgresql-password" }
      env      = { AEGIS_MICROSOFT_CLIENT_STATE = "azure-client-state", AEGIS_MICROSOFT_CLIENT_SECRET = "azure-client-secret" }
    }
  }
  assert {
    condition = alltrue([for k in ["AEGIS_MICROSOFT_CLIENT_STATE", "AEGIS_MICROSOFT_CLIENT_SECRET"] :
    !contains(keys(yamldecode(helm_release.workspace_connector.values[0]).config.env), k)])
    error_message = "secret-backed keys must leave env, or env would shadow envFrom"
  }
  assert {
    condition     = yamldecode(helm_release.workspace_connector.values[0]).config.env.AEGIS_DATABASE_URL == "postgresql://acme_x@localhost:5432/postgres?sslmode=disable&search_path=acme_x"
    error_message = "schema must default to user"
  }
  assert {
    condition = yamldecode(helm_release.workspace_connector.values[0]).externalSecret.env == {
      PGPASSWORD                    = "acme-x-postgresql-password"
      AEGIS_MICROSOFT_CLIENT_STATE  = "azure-client-state"
      AEGIS_MICROSOFT_CLIENT_SECRET = "azure-client-secret"
    }
    error_message = "the password and env secrets must map by name"
  }
}

run "microsoft_needs_client_state" {
  command = plan
  variables {
    app_config = {
      workspace_kind             = "microsoft"
      email_addresses            = ["a@acme.test"]
      email_domains              = ["acme.test"]
      microsoft_workspace_config = { tenant_id = "t", client_id = "c" }
    }
  }
  expect_failures = [var.app_config]
}

run "no_url_needs_external_secrets" {
  command = plan
  variables {
    database = { create = false }
  }
  expect_failures = [var.database]
}

run "external_secrets_replaces_database_url" {
  command = plan
  variables {
    external_secrets = {}
  }
  expect_failures = [var.database]
}

run "password_secret_wins_over_env" {
  command = apply
  variables {
    database = { create = false }
    external_secrets = {
      database = { password_secret = "acme-postgresql-password" }
      env      = { PGPASSWORD = "other-secret" }
    }
  }
  assert {
    condition     = yamldecode(helm_release.workspace_connector.values[0]).externalSecret.env.PGPASSWORD == "acme-postgresql-password"
    error_message = "database.password_secret must not be overridden by env"
  }
}

run "sub_tenant_needs_overrides" {
  command = plan
  variables {
    aegis_tenant_id  = "acme.sub"
    sub_tenant_of    = "acme"
    database         = { create = false }
    external_secrets = {}
  }
  expect_failures = [var.external_secrets]
}
