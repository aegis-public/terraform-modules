locals {
  aegis_project_id = "friendly-access-450904-h1"

  # Normalize to always use email_domains internally
  # Support both legacy email_domain (singular) and new email_domains (plural)
  normalized_email_domains = var.app_config.email_domains != null ? var.app_config.email_domains : (
    var.app_config.email_domain != null ? [var.app_config.email_domain] : []
  )
  primary_email_domain = length(local.normalized_email_domains) > 0 ? local.normalized_email_domains[0] : ""

  aegis_config_deps = {
    base_topic_format  = "projects/%s/topics/email_messages.%s.%%s"
    base_bucket_format = "aegis-%s-%%s"
    safe_email_domain  = replace(local.primary_email_domain, ".", "_")
  }
  aegis_config = {
    tenant_topic_format = format(
      local.aegis_config_deps.base_topic_format,
      local.aegis_project_id,
      local.aegis_config_deps.safe_email_domain
    )
    tenant_bucket_format = format(
      local.aegis_config_deps.base_bucket_format,
      local.aegis_config_deps.safe_email_domain
    )
  }
}

locals {
  inferred_env_vars = {
    AEGIS_READ_ONLY_MODE = var.app_config.read_only_mode ? "true" : "false"

    AEGIS_DATABASE_URL = var.database.url != null ? var.database.url : (
      "postgresql://default:${module.sql_db[0].generated_user_password}@localhost:5432/default?sslmode=disable"
    )

    AEGIS_EMAIL_ADDRESSES          = join(",", var.app_config.email_addresses)
    AEGIS_EXCLUDED_EMAIL_ADDRESSES = join(",", var.app_config.excluded_email_addresses)

    AEGIS_WORKSPACE_KIND  = var.app_config.workspace_kind
    AEGIS_EMAIL_DOMAIN    = local.primary_email_domain  # Legacy support (first domain)
    AEGIS_EMAIL_DOMAINS   = join(",", local.normalized_email_domains)  # New multi-domain support
    AEGIS_BASE_URL        = var.helm_ingress_url

    AEGIS_GOOGLE_SERVICE_ACCOUNT_EMAIL   = google_service_account.workspace_connector.email
    AEGIS_GOOGLE_ADMIN_EMAIL_ADDRESS     = try(var.app_config.google_workspace_config.admin_email_address, null)
    AEGIS_GOOGLE_TOPIC_GMAIL_INBOX_WATCH = google_pubsub_topic.gmail_inbox.id

    AEGIS_MICROSOFT_TENANT_ID     = try(var.app_config.microsoft_workspace_config.tenant_id, null)
    AEGIS_MICROSOFT_CLIENT_ID     = try(var.app_config.microsoft_workspace_config.client_id, null)
    AEGIS_MICROSOFT_CLIENT_SECRET = try(var.app_config.microsoft_workspace_config.client_secret, null)

    AEGIS_AEGIS_TOPIC_LIVE_MESSAGES     = format(local.aegis_config.tenant_topic_format, "live")
    AEGIS_AEGIS_TOPIC_BACKFILL_MESSAGES = format(local.aegis_config.tenant_topic_format, "backfill")
    AEGIS_AEGIS_BUCKET_LARGE_MESSAGES   = format(local.aegis_config.tenant_bucket_format, "large-messages")
    AEGIS_BACKFILL_QUERY                = var.app_config.backfill_query
  }

  inferred_helm_values = {
    config = {
      env = merge(local.inferred_env_vars, var.app_config.env)
    }
  }
}

locals {
  helm_release_name = "aegis-workspace-connector"
}

resource "helm_release" "workspace_connector" {
  name             = local.helm_release_name
  repository       = "https://aegis-public.github.io/helm-charts"
  chart            = "workspace-connector"
  version          = "0.1.24-alpha.4"
  namespace        = var.kubernetes_namespace
  create_namespace = true

  values = [
    yamlencode(local.inferred_helm_values),
    yamlencode({
      serviceAccount = {
        workloadIdentity = {
          gcpServiceAccount = google_service_account.workspace_connector.email
        }
      }
      cloudSql = {
        instanceConnectionName = var.database.create ? module.sql_db[0].instance_connection_name : null
      }
    }),
    yamlencode(var.helm_values),
  ]

  depends_on = [
    google_service_account_iam_member.workspace_connector_wif,
    google_service_account_iam_member.workspace_connector_token_creator,
  ]
}
