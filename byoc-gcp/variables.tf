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

variable "app_config" {
  description = "Application configuration"
  type = object({
    workspace_connector_http_url = string
    email_accounts               = list(string)
  })
}
