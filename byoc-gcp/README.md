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

In addition, to authorize privileged Gmail actions (listing users, fetching emails, modifying labels) you must manually grant Domain-wide Delegation permission to the generated service account from the Google Admin Console.

<img src="https://github.com/user-attachments/assets/aba7e149-f453-4e0d-ab2b-556f2a460397" width="400" alt="screenshot" />

Client ID: Available in terraform output - `module.byoc_aegis.service_account_oauth_client_id`

Also available under `Advanced Settings` for the service account in GCP console (IAM & Admin > Service Accounts).

Scopes:

`https://www.googleapis.com/auth/gmail.readonly`  
`https://www.googleapis.com/auth/gmail.modify`  
`https://www.googleapis.com/auth/admin.directory.user.readonly`  


Google Admin Console: https://admin.google.com/u/0/ac/owl/domainwidedelegation

Instructions in Google Help Center: https://support.google.com/a/answer/162106
