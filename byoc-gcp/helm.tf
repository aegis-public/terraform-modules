locals {
  aegis_project_id = "friendly-access-450904-h1"

  aegis_config_deps = {
    base_topic_format  = "projects/%s/topics/email_messages.%s.%%s"
    base_bucket_format = "aegis-%s-%%s"
  }
  aegis_config = {
    tenant_topic_format = format(
      local.aegis_config_deps.base_topic_format,
      local.aegis_project_id,
      var.aegis_tenant_id
    )
    # Sub-tenants share the parent's large-messages bucket, so derive the
    # bucket name from the parent tenant ID rather than the full (dotted)
    # sub-tenant ID to avoid creating a new bucket with dots in the name.
    tenant_bucket_format = format(
      local.aegis_config_deps.base_bucket_format,
      local.is_sub_tenant ? var.sub_tenant_of : var.aegis_tenant_id
    )
  }
}

locals {
  inferred_env_vars = {
    AEGIS_DATABASE_URL = var.database.url != null ? var.database.url : (
      "postgresql://default:${module.sql_db[0].generated_user_password}@localhost:5432/default?sslmode=disable"
    )

    AEGIS_ACCESS_MODE              = var.app_config.access_mode
    AEGIS_OPERATIONAL_MODE         = var.app_config.operational_mode
    AEGIS_EMAIL_ADDRESSES          = join(",", var.app_config.email_addresses)
    AEGIS_EXCLUDED_EMAIL_ADDRESSES = join(",", var.app_config.excluded_email_addresses)

    AEGIS_WORKSPACE_KIND = var.app_config.workspace_kind
    AEGIS_EMAIL_DOMAINS  = join(",", var.app_config.email_domains)
    AEGIS_BASE_URL       = var.helm_ingress_url

    AEGIS_GOOGLE_SERVICE_ACCOUNT_EMAIL   = local.workspace_connector_sa_email
    AEGIS_GOOGLE_ADMIN_EMAIL_ADDRESS     = try(var.app_config.google_workspace_config.admin_email_address, null)
    AEGIS_GOOGLE_TOPIC_GMAIL_INBOX_WATCH = try(google_pubsub_topic.gmail_inbox[0].id, null)
    AEGIS_GOOGLE_GMAIL_LABEL_NAMES       = try(jsonencode(var.app_config.google_workspace_config.gmail_label_names), null)

    AEGIS_MICROSOFT_TENANT_ID     = try(var.app_config.microsoft_workspace_config.tenant_id, null)
    AEGIS_MICROSOFT_CLIENT_ID     = try(var.app_config.microsoft_workspace_config.client_id, null)
    AEGIS_MICROSOFT_CLIENT_SECRET = try(var.app_config.microsoft_workspace_config.client_secret, null)
    AEGIS_MICROSOFT_CLIENT_STATE  = try(var.app_config.microsoft_workspace_config.client_state, null)

    AEGIS_AEGIS_TOPIC_LIVE_MESSAGES     = format(local.aegis_config.tenant_topic_format, "live")
    AEGIS_AEGIS_TOPIC_BACKFILL_MESSAGES = format(local.aegis_config.tenant_topic_format, "backfill")
    AEGIS_AEGIS_BUCKET_LARGE_MESSAGES   = format(local.aegis_config.tenant_bucket_format, "large-messages")
    AEGIS_BACKFILL_QUERY                = var.app_config.backfill_query

    # Message ID Queue (optional — Gmail or Outlook depending on workspace kind)
    AEGIS_AEGIS_TOPIC_MESSAGE_IDS = coalesce(
      try(google_pubsub_topic.gmail_message_ids[0].id, null),
      try(google_pubsub_topic.outlook_message_ids[0].id, null),
    )
    AEGIS_AEGIS_SUBSCRIPTION_MESSAGE_IDS = coalesce(
      try(google_pubsub_subscription.gmail_message_ids[0].id, null),
      try(google_pubsub_subscription.outlook_message_ids[0].id, null),
    )
  }

  inferred_helm_values = {
    config = {
      env = merge(local.inferred_env_vars, var.app_config.env)
    }
  }
}

locals {
  # Sub-tenants run as a separate Helm release alongside the parent connector in
  # the same k8s namespace; the release name doubles as the k8s SA name for WIF.
  helm_release_name = local.is_sub_tenant ? "aegis-workspace-connector-${local.sub_tenant_suffix}" : "aegis-workspace-connector"
}

resource "helm_release" "workspace_connector" {
  name             = local.helm_release_name
  repository       = "https://aegis-public.github.io/helm-charts"
  chart            = "workspace-connector"
  version          = "0.1.28"
  namespace        = var.kubernetes_namespace
  create_namespace = true

  values = concat(
    [
      yamlencode(local.inferred_helm_values),
      yamlencode({
        serviceAccount = {
          workloadIdentity = {
            gcpServiceAccount = local.workspace_connector_sa_email
          }
        }
        cloudSql = {
          instanceConnectionName = var.database.create ? module.sql_db[0].instance_connection_name : null
        }
      }),
    ],
    var.active ? [] : [yamlencode({
      replicaCount = 0
      labels       = { "aegisai.ai/active" = "false" }
    })],
    [yamlencode(var.helm_values)],
  )

  depends_on = [
    google_service_account_iam_member.workspace_connector_wif,
  ]

  lifecycle {
    prevent_destroy = true
  }
}
