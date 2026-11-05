variable "name" {
  description = "Release name; byoc-gcp's helm_release_name output"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace; the same one passed to byoc-gcp"
  type        = string
}

variable "chart_version" {
  description = "workspace-connector chart version; byoc-gcp's helm_chart_version output"
  type        = string
}

variable "values" {
  description = "Values documents in merge order; byoc-gcp's helm_values output"
  type        = list(string)
}

variable "create_namespace" {
  description = "Let helm create the namespace. Off when byoc-gcp creates it (manage_namespace = true)."
  type        = bool
  default     = true
}
