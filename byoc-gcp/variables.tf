variable "aegis_tenant_id" {
  description = "Aegis tenant identifier"
  type        = string
}

variable "aegis_project_id" {
  description = "Aegis GCP project ID"
  type        = string
  default     = "friendly-access-450904-h1"
}

variable "gke_cluster_link" {
  description = "GKE cluster selfLink"
  type        = string
}

variable "kubernetes_namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "helm_values" {
  description = "Helm values (will be merged after inferred defaults)"
  type        = any
  default     = {}
}

variable "helm_ingress_url" {
  description = "URL for the configured helm ingress"
  type        = string
}

variable "database_url" {
  description = "Database URL"
  type        = string
  default     = null
}

variable "database" {
  description = "Database configuration"
  type = object({
    url    = optional(string, null)
    create = optional(bool, true)
  })
  default = {}
  validation {
    condition     = var.database.create || var.database.url != null
    error_message = "database.url must be provided when database.create is false"
  }
}

variable "app_config" {
  description = "Application configuration"
  type = object({
    access_mode              = optional(string, "readonly")
    operational_mode         = optional(string, "readonly")
    workspace_kind           = string
    email_addresses          = list(string)
    excluded_email_addresses = optional(list(string), [])
    email_domains            = list(string)
    backfill_query           = optional(string, "")
    env                      = optional(map(string), {})
    google_workspace_config = optional(object({
      admin_email_address = string
      gmail_label_names = optional(object({
        spam      = string
        phishing  = string
        promotion = string
        malware   = string
      }), null)
    }), null)
    microsoft_workspace_config = optional(object({
      tenant_id     = string
      client_id     = string
      client_state  = string
      client_secret = optional(string, "")
    }), null)
  })
  validation {
    condition     = contains(["readonly", "modify", "full"], var.app_config.access_mode)
    error_message = "access_mode must be one of: readonly, modify, full"
  }
  validation {
    condition     = contains(["google", "microsoft"], var.app_config.workspace_kind)
    error_message = "workspace_kind must be either google or microsoft"
  }
  validation {
    condition     = var.app_config.workspace_kind == "google" ? var.app_config.google_workspace_config != null : true
    error_message = "google_workspace_config must be provided if workspace_kind is google"
  }
  validation {
    condition     = var.app_config.workspace_kind == "microsoft" ? var.app_config.microsoft_workspace_config != null : true
    error_message = "microsoft_workspace_config must be provided if workspace_kind is microsoft"
  }
  validation {
    condition     = length(var.app_config.email_domains) > 0
    error_message = "must specify at least one email domain"
  }
}

##########################################################

variable "gcp_service_account_id" {
  description = "GCP Service Account ID (do not override unless you know what you're doing!)"
  type        = string
  default     = "aegis-workspace-connector"
}

variable "lakehouse_config" {
  description = "Lakehouse streaming configuration"
  type = object({
    enabled = optional(bool, false)
  })
  default = {
    enabled = false
  }
}

variable "message_id_queue_config" {
  description = "Message ID queue configuration for decoupled message processing"
  type = object({
    enabled = optional(bool, false)
  })
  default = {
    enabled = false
  }
}

variable "fts_burst_config" {
  description = "FTS burst retroactive quarantine Pub/Sub infrastructure. Kraken publishes, workspace-connector subscribes."
  type = object({
    enabled = optional(bool, false)
  })
  default = {
    enabled = false
  }
}

variable "active" {
  description = "Whether this tenant is actively receiving traffic. When false, replicaCount is forced to 0 and the deployment gets label aegisai.ai/active=false."
  type        = bool
  default     = true
}

variable "gmail_inbox_subscription" {
  description = <<-EOT
    Tunables for the Gmail inbox push subscription
    (`<tenant>-gmail-inbox-messages-received`). All fields are optional.

    - ack_deadline_seconds: how long Pub/Sub waits for an HTTP 200 before
      considering a delivery failed. With ack-immediate enabled in the handler
      (EnableGmailAckImmediate=true), the handler returns 200 in <100ms after
      Flush, so a low deadline is safe and caps `oldest_unacked_message_age`
      on transient push failures. Range: 10-600. Default: 300.
    - retry_minimum_backoff / retry_maximum_backoff: how long Pub/Sub waits
      between push retries after a delivery failure. Lower = faster recovery
      after transient ingress 5xx; higher = less retry pressure during real
      outages. Defaults: 30s / 300s.
  EOT
  type = object({
    ack_deadline_seconds  = optional(number, 300)
    retry_minimum_backoff = optional(string, "30s")
    retry_maximum_backoff = optional(string, "300s")
  })
  default = {}
}

variable "sub_tenant_of" {
  description = <<-EOT
    When set, this connector is an MSP sub-tenant that shares its parent's GCP project and
    service account. The value is the parent tenant ID (e.g. "acme").

    Behaviour when set:
      - No new GCP service account is created; the existing SA identified by
        gcp_service_account_id is looked up via a data source instead.
      - Connector Pub/Sub resources (Gmail inbox topic, message-ID queue) are given
        scoped names with a suffix derived from the sub-tenant portion of aegis_tenant_id
        (e.g. "aegis-gmail-inbox-sub" instead of "aegis-gmail-inbox").
      - The Helm release is named "aegis-workspace-connector-<suffix>" so it can
        coexist with the parent connector in the same k8s namespace.
      - The large-messages GCS bucket is shared from the parent tenant, not derived
        from aegis_tenant_id.
      - The serviceAccountTokenCreator self-binding is skipped (already exists on the
        parent SA).

    Central-pipeline topics (live/backfill/classified/DLQ) are NOT created by this
    module; they are expected to be pre-provisioned in the central project (e.g. via
    the prod Terraform stack).
  EOT
  type        = string
  default     = null
}
