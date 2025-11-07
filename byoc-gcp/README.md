Aegis workspace-connector can be installed using this terraform module.  
This module communicates with your e-mail provider to fetch messages & apply quarantine labels in response to classification results from Aegis.

Note: all terraform variables specified here are required, and must be configured as per your environment.

```hcl
module "byoc_aegis" {
  source = "github.com/aegis-public/terraform-modules.git//byoc-gcp?ref=v0.1.10"

  # fully qualified url for gke cluster (with workload identity federation enabled)
  # gcloud container clusters list --format="value(selfLink)"
  gke_cluster_link = "https://container.googleapis.com/v1/projects/mycompany/zones/us-central1-a/clusters/mycluster"

  # k8s namespace for the deployment
  kubernetes_namespace = "aegis-byoc"

  helm_values = {
    # ingress config to receive pubsub push subscription events
    ingress = {
      className = "nginx"
      host      = "mycompany.com"
      path      = "/aegis-workspace-connector(/|$)(.*)"
      pathType  = "ImplementationSpecific"
      annotations = {
        "nginx.ingress.kubernetes.io/rewrite-target" = "/$2"
      }
    }
  }

  # ingress URL to create pubsub push subscriptions
  helm_ingress_url = "https://mycompany.com/aegis-workspace-connector"

  app_config = {
    workspace_kind = "google"
    google_workspace_config = {
      "admin_email_address" = "admin@mycompany.com"
    }
    # in read only mode, emails are not quarantined
    # read_only_mode = true
    # email addresses to watch (can use ["*"] for all addresses)
    email_addresses = ["employee@mycompany.com"]
    excluded_email_addresses = []
    email_domain = "mycompany.com"
    # gmail search query to list messages to backfill classification (optional, remove to disable backfill)
    backfill_query = "newer_than:7d"
  }
}
```

In addition, to authorize privileged Gmail actions (listing users, fetching emails, modifying labels) you must manually grant Domain-wide Delegation permission to the generated service account from the Google Admin Console.

<img src="https://i.postimg.cc/WN8ydqrZ/495848066-aba7e149-f453-4e0d-ab2b-556f2a460397.png" width="400" alt="screenshot" />

Client ID: Available in terraform output - `module.byoc_aegis.service_account_oauth_client_id`

Also available under `Advanced Settings` for the service account in GCP console (IAM & Admin > Service Accounts).

Scopes:

`https://www.googleapis.com/auth/gmail.readonly`  
`https://www.googleapis.com/auth/gmail.modify`                  required if `read_only_mode = false` (default)  
`https://www.googleapis.com/auth/admin.directory.user.readonly` required if `email_addresses = ["*"]`  


Google Admin Console: https://admin.google.com/u/0/ac/owl/domainwidedelegation

Instructions in Google Help Center: https://support.google.com/a/answer/162106
