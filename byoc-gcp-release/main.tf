# The workspace-connector Helm release for a self-hosted install: one apply
# produces a running connector. Aegis's own fleet does not use this module; its
# deploy rail installs and upgrades the release from the values byoc-gcp writes.

resource "helm_release" "workspace_connector" {
  name             = var.name
  repository       = "https://aegis-public.github.io/helm-charts"
  chart            = "workspace-connector"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace
  max_history      = 10

  values = var.values

  lifecycle {
    prevent_destroy = true
  }
}
