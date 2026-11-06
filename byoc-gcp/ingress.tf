# The connector's Ingress objects, from the same helm_values the chart reads: the
# pubsub push Ingress (helm_values.ingress) and the siblings in
# helm_values.extraIngresses (the restore page, the DLP appeal page). The chart's
# defaults are written out here so an imported object plans clean: the main
# Ingress has TLS on and the nginx proxy annotations, an extra one has neither
# unless it says so. Both writers set helm.sh/resource-policy: keep.
locals {
  ingress_values       = try(var.helm_values.ingress, {})
  ingress_enabled      = try(local.ingress_values.enabled, true)
  ingress_service_port = try(var.helm_values.service.port, 8080)
  extra_ingresses      = { for ing in try(var.helm_values.extraIngresses, []) : ing.name => ing }
}

resource "kubernetes_ingress_v1" "connector" {
  count = local.ingress_enabled && can(local.ingress_values.host) ? 1 : 0

  metadata {
    name      = local.helm_release_name
    namespace = var.kubernetes_namespace
    labels = {
      app = local.helm_release_name
    }
    annotations = merge(
      {
        "helm.sh/resource-policy"                             = "keep"
        "nginx.ingress.kubernetes.io/proxy-body-size"         = "10m"
        "nginx.ingress.kubernetes.io/proxy-buffering"         = "off"
        "nginx.ingress.kubernetes.io/proxy-request-buffering" = "off"
        "nginx.ingress.kubernetes.io/proxy-read-timeout"      = tostring(try(local.ingress_values.proxyReadTimeout, "60"))
        "nginx.ingress.kubernetes.io/proxy-send-timeout"      = tostring(try(local.ingress_values.proxySendTimeout, "60"))
        "nginx.ingress.kubernetes.io/proxy-connect-timeout"   = tostring(try(local.ingress_values.proxyConnectTimeout, "10"))
      },
      try(local.ingress_values.annotations, {}),
    )
  }

  spec {
    ingress_class_name = try(local.ingress_values.className, null)

    dynamic "tls" {
      for_each = try(local.ingress_values.tls.enabled, true) ? [1] : []
      content {
        hosts       = [local.ingress_values.host]
        secret_name = try(local.ingress_values.tls.secretName, "") != "" ? local.ingress_values.tls.secretName : null
      }
    }

    rule {
      host = local.ingress_values.host
      http {
        path {
          # The chart's own default path when a consumer sets none.
          path      = try(local.ingress_values.path, "/reasonablesecurityai/workspace-connector(/|$)(.*)")
          path_type = try(local.ingress_values.pathType, "ImplementationSpecific")
          backend {
            service {
              name = local.helm_release_name
              port {
                number = local.ingress_service_port
              }
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace_v1.connector]
}

resource "kubernetes_ingress_v1" "extra" {
  for_each = local.extra_ingresses

  metadata {
    name      = each.key
    namespace = var.kubernetes_namespace
    labels = {
      app = local.helm_release_name
    }
    annotations = merge(
      { "helm.sh/resource-policy" = "keep" },
      try(each.value.annotations, {}),
    )
  }

  spec {
    ingress_class_name = try(each.value.className, null)

    dynamic "tls" {
      for_each = try(each.value.tls.enabled, false) ? [1] : []
      content {
        hosts       = [each.value.host]
        secret_name = try(each.value.tls.secretName, "") != "" ? each.value.tls.secretName : null
      }
    }

    rule {
      host = each.value.host
      http {
        path {
          path      = each.value.path
          path_type = try(each.value.pathType, "ImplementationSpecific")
          backend {
            service {
              name = local.helm_release_name
              port {
                number = local.ingress_service_port
              }
            }
          }
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = startswith(each.key, "${local.helm_release_name}-")
      error_message = "extraIngresses[].name must start with ${local.helm_release_name}-, so two releases in one namespace never collide"
    }
  }

  depends_on = [kubernetes_namespace_v1.connector]
}
