# The connector's plain env, as a ConfigMap the pod loads through envFrom when
# env_delivery is configmap. Written in both modes so the switch changes only the
# Deployment. A ConfigMap holds strings only, so a null entry is absent here the
# way helm drops it from the pod template.
resource "kubernetes_config_map_v1" "connector_env_vars" {
  metadata {
    name      = local.env_configmap_name
    namespace = var.kubernetes_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "aegis-workspace-connector"
      "aegisai.ai/release"           = local.helm_release_name
    }
  }

  data = { for name, value in local.connector_plain_env : name => tostring(value) if value != null }

  depends_on = [kubernetes_namespace_v1.connector]
}
