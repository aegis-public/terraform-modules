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

variable "app_config" {
  description = "Application configuration"
  type = object({
    workspace_kind           = string
    email_addresses          = list(string)
    excluded_email_addresses = optional(list(string), [])
    email_domain             = string
    admin_email_address      = string
    backfill_query           = optional(string, "")
    env                      = optional(map(string), {})
    google_workspace_config  = optional(object({
      admin_email_address = string
    }), null)
    microsoft_workspace_config = optional(object({
      tenant_id     = string
      client_id     = string
      client_secret = optional(string, "")
    }), null)
  })
  validation {
    condition = contains(["google", "microsoft"], var.app_config.workspace_kind)
    error_message = "workspace_kind must be either google or microsoft"
  }
  validation {
    condition = var.app_config.workspace_kind == "google" ? var.app_config.google_workspace_config != null : true
    error_message = "google_workspace_config must be provided if workspace_kind is google"
  }
  validation {
    condition = var.app_config.workspace_kind == "microsoft" ? var.app_config.microsoft_workspace_config != null : true
    error_message = "microsoft_workspace_config must be provided if workspace_kind is microsoft"
  }
}

##########################################################

variable "gcp_service_account_id" {
  description = "GCP Service Account ID (do not override unless you know what you're doing!)"
  type        = string
  default     = "aegis-workspace-connector"
}
