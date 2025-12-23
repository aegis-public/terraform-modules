# Aegis Terraform Modules

This repository contains reusable Terraform module definitions for the Aegis AI Security Platform infrastructure.

## Usage

This module is used by BYOC (Bring Your Own Cloud) customers to deploy Aegis infrastructure in their own GCP projects. Aegis also uses this module internally to manage tenant deployments.

### How It Works

Reference the module in your Terraform configuration:

```hcl
module "aegis_byoc" {
  source = "github.com/aegis-public/terraform-modules.git//byoc-gcp?ref=vX.Y.Z"

  aegis_tenant_id        = "mycompany"
  gcp_service_account_id = "lighthouse"
  kubernetes_namespace   = "mycompany"
  # ... other tenant-specific variables
}
```

## Repository Structure

```
terraform-modules/
├── README.md
└── byoc-gcp/
    ├── main.tf           # Core infrastructure resources
    ├── lakehouse.tf      # BigQuery lakehouse streaming infrastructure
    ├── variables.tf      # Input variable definitions
    ├── outputs.tf        # Output value definitions
    └── schemas/          # BigQuery table schemas
        ├── emails.json
        └── verdicts.json
```

## Modules

### byoc-gcp

The `byoc-gcp` module provisions all GCP infrastructure required for a BYOC (Bring Your Own Cloud) tenant deployment. This includes:

- **Service Accounts**: Lighthouse service account with appropriate IAM roles
- **Pub/Sub Infrastructure**: Topics and subscriptions for email message flow
  - `email_messages.{domain}.live` - Live email processing
  - `email_messages.{domain}.backfill` - Historical email backfill
  - `email_messages.{domain}.classified` - Classification results
- **Cloud Storage**: Buckets for large messages and attachments
- **Firestore**: Document database for email metadata and SOC queue
- **BigQuery Lakehouse**: Streaming tables for analytics and reporting
- **Workload Identity**: GKE service account bindings
- **Helm Release**: workspace-connector Kubernetes deployment

## Deployment Process

When updating the module (adding new features, fixing bugs, or updating schemas), follow this process:

### 1. Make Changes

```bash
cd ~/path/to/aegis-public/terraform-modules
# Edit files in byoc-gcp/
```

### 2. Commit and Tag

```bash
git add .
git commit -m "Your commit message"
git tag vX.Y.Z  # Use semantic versioning
git push origin main --tags
```

### 3. Test with Staging Tenant

Update a staging tenant to use the new version:

```bash
# Edit tenant .tf file - update the module source ref
# Update the ref to the new version

terraform init -upgrade  # Fetch new module version
terraform plan           # Review changes carefully
terraform apply          # Apply after approval
```

Verify the changes work correctly before rolling out to other tenants.

### 4. Roll Out to Production Tenants

After validating with the staging tenant, update production tenants incrementally:

```bash
# Update tenant files to use the new version
# Change ref=v0.1.16 -> ref=v0.2.0

terraform plan   # Review all changes
terraform apply  # Apply after approval
```

## Versioning

This repository uses [Semantic Versioning](https://semver.org/):

- **MAJOR** (v1.0.0 -> v2.0.0): Breaking changes to module interface
- **MINOR** (v0.1.0 -> v0.2.0): New features, backward compatible
- **PATCH** (v0.1.0 -> v0.1.1): Bug fixes, backward compatible

### Version History

See [releases](https://github.com/aegis-public/terraform-modules/releases) for the full version history.

## Module Reference

### byoc-gcp Variables

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `aegis_tenant_id` | string | yes | Short tenant identifier (e.g., "mycompany") |
| `gcp_service_account_id` | string | yes | GCP service account ID (typically "lighthouse") |
| `gke_cluster_link` | string | yes | Fully qualified GKE cluster URL |
| `kubernetes_namespace` | string | yes | K8s namespace for deployment |
| `helm_values` | object | yes | Helm chart configuration values |
| `helm_ingress_url` | string | yes | Ingress URL for Pub/Sub push subscriptions |
| `database` | object | yes | Database configuration (create flag and connection URL) |
| `app_config` | object | yes | Application configuration (workspace kind, admin email, domains) |

### byoc-gcp Outputs

| Output | Description |
|--------|-------------|
| `service_account_email` | Lighthouse service account email |
| `pubsub_live_topic` | Live messages Pub/Sub topic name |
| `pubsub_backfill_topic` | Backfill messages Pub/Sub topic name |
| `pubsub_classified_topic` | Classified messages Pub/Sub topic name |

## Support

For questions about these modules, contact the Aegis platform team.
