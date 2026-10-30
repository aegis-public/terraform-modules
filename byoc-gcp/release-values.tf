# What the connector release is made of, written where the thing that installs
# and upgrades the release can read it. This module never runs helm: the
# byoc-gcp-release module does for a self-hosted install, and Aegis's deploy
# rail does for the fleet it operates, where it is the only writer of the
# release.

resource "kubernetes_namespace_v1" "connector" {
  count = var.manage_namespace && !local.is_sub_tenant ? 1 : 0

  metadata {
    name = var.kubernetes_namespace
  }

  lifecycle {
    # The cluster and other controllers label and annotate namespaces.
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

resource "kubernetes_config_map_v1" "connector_values" {
  metadata {
    name      = "${local.helm_release_name}-values"
    namespace = var.kubernetes_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "aegis-workspace-connector"
      "aegisai.ai/release"           = local.helm_release_name
    }
  }

  data = merge(local.connector_values_files, { "chart-version" = local.connector_chart_version })

  depends_on = [
    kubernetes_namespace_v1.connector,
    google_service_account_iam_member.workspace_connector_wif,
  ]
}
