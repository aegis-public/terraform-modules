# The ExternalSecret that syncs the tenant's secrets from Secret Manager into the
# Secret <release>-env the pod loads through envFrom. The same object the chart
# renders when externalSecret.render is on, with the API's defaults written out so
# an imported one plans clean. Both writers set helm.sh/resource-policy: keep, so
# a helm upgrade that stops rendering it leaves it in place: the target Secret is
# owned by this object and would be deleted with it.
resource "kubernetes_manifest" "external_secret" {
  count = var.external_secrets == null ? 0 : 1

  # An adopted object still carries the chart's field manager on .spec, and the
  # API refuses the first change to spec.data as a conflict with it. Taking the
  # fields is safe: the chart stops rendering this object and never writes it again.
  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "${local.helm_release_name}-env"
      namespace = var.kubernetes_namespace
      labels = {
        app = local.helm_release_name
      }
      annotations = {
        "helm.sh/resource-policy" = "keep"
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        kind = "SecretStore"
        name = "gcp-secret-store"
      }
      target = {
        name           = "${local.helm_release_name}-env"
        creationPolicy = "Owner"
        deletionPolicy = "Retain"
      }
      data = [
        for name in sort(keys(local.external_secret_env)) : {
          secretKey = name
          remoteRef = {
            key                = local.external_secret_env[name]
            conversionStrategy = "Default"
            decodingStrategy   = "None"
            metadataPolicy     = "None"
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_namespace_v1.connector]
}
