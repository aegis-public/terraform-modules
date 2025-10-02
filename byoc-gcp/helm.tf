locals {
  aegis_project_id = "friendly-access-450904-h1"
  aegis_config_deps = {
    base_topic_format  = "projects/%s/topics/email_messages.%s.%%s"
    base_bucket_format = "aegis-%s-%%s"
    safe_email_domain  = replace(var.app_config.email_domain, ".", "_")
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
    AEGIS_ACCOUNTS                       = join(",", var.app_config.email_accounts)
    AEGIS_GOOGLE_SERVICE_ACCOUNT_EMAIL   = google_service_account.workspace_connector.email
    AEGIS_GOOGLE_ADMIN_ACCOUNT_EMAIL     = var.app_config.admin_account_email
    AEGIS_GOOGLE_EMAIL_DOMAIN            = var.app_config.email_domain
    AEGIS_GOOGLE_TOPIC_GMAIL_INBOX_WATCH = google_pubsub_topic.gmail_inbox.id
    AEGIS_AEGIS_TOPIC_LIVE_MESSAGES      = format(local.aegis_config.tenant_topic_format, "live")
    AEGIS_AEGIS_TOPIC_BACKFILL_MESSAGES  = format(local.aegis_config.tenant_topic_format, "backfill")
    AEGIS_AEGIS_BUCKET_LARGE_MESSAGES   = format(local.aegis_config.tenant_bucket_format, "large-messages")
    AEGIS_BACKFILL_QUERY                 = var.app_config.backfill_query
  }

  inferred_helm_values = {
    config = {
      env = merge(local.inferred_env_vars, var.app_config.env)
    }
  }
}

resource "helm_release" "workspace_connector" {
  name             = "aegis-workspace-connector"
  repository       = "https://aegis-public.github.io/helm-charts"
  chart            = "workspace-connector"
  version          = "0.1.5"
  namespace        = var.kubernetes_namespace
  create_namespace = true

  set = [{
    name  = "serviceAccount.workloadIdentity.gcpServiceAccount"
    value = google_service_account.workspace_connector.email
  }]

  values = [
    yamlencode(local.inferred_helm_values),
    yamlencode(var.helm_values),
  ]
}
