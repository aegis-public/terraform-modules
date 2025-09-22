variable "email_domain" {
  description = "Email domain"
  type        = string
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

variable "app_config" {
  description = "Application configuration"
  type = object({
    email_accounts      = list(string)
    admin_account_email = string
    env                 = optional(map(string))
  })
}

##########################################################

variable "gcp_service_account_id" {
  description = "GCP Service Account ID (do not override unless you know what you're doing!)"
  type        = string
  default     = "aegis-workspace-connector"
}
