variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "workspace_connector_http_url" {
  description = "HTTP URL of the workspace connector"
  type        = string
}

variable "kubernetes_namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "kubernetes_service_account" {
  description = "Kubernetes service account"
  type        = string
}

variable "workload_identity_pool" {
  description = "GCP workload identity pool name"
  type        = string
}
