```hcl
module "byoc_aegis" {
  source = "github.com/aegis-public/terraform-modules.git//byoc-gcp?ref=v0.1.8"

  # fully qualified gke cluster url
  # gcloud container clusters list --format="value(selfLink)"
  gke_cluster_link = "https://container.googleapis.com/v1/projects/aegis-project/zones/us-central1-a/clusters/aegis-cluster"

  # k8s namespace for the deployment
  kubernetes_namespace = "aegis-byoc"

  helm_values = {
    # ingress config to receive pubsub push subscription events
    ingress = {
      className = "nginx"
      host      = "aegisai.ai"
      path      = "/workspace-connector(/|$)(.*)"
      pathType  = "ImplementationSpecific"
      annotations = {
        "nginx.ingress.kubernetes.io/rewrite-target" = "/$2"
      }
    }
  }

  # ingress URL to create pubsub push subscriptions
  helm_ingress_url = "https://aegisai.ai/workspace-connector"

  app_config = {
    # email accounts to watch (can use ["*"] for all accounts)
    email_accounts = ["user@aegisai.ai"]
    email_domain = "aegisai.ai"
    admin_account_email = "admin@aegisai.ai"
    # gmail search query to backfill message classifications across all accounts (optional, remove to disable backfill)
    backfill_query = "newer_than:7d"
  }
}
```
