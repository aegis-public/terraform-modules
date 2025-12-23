# Aegis Terraform Modules

This repository contains reusable Terraform module definitions for the Aegis AI Security Platform infrastructure.

## Important: This is NOT a Customer-Facing Repository

**These modules are internal Aegis infrastructure components.** The module definitions here are referenced by Aegis's internal tenant configuration files (`infra/live/connector/{tenant}.tf`), not deployed directly by customers.

### How It Works

```
aegis-public/terraform-modules/byoc-gcp/         <-- Module definition (this repo)
         ^
         |  (referenced via git source)
         |
reasonable-security/infra/live/connector/        <-- Tenant configurations
    aegis.tf
    jupiter.tf
    reasonablesecurityai.tf   <-- Staging tenant for testing
    ...
```

Each tenant `.tf` file in `infra/live/connector/` references this module with a specific version tag:

```hcl
module "connector_jupiter" {
  source = "github.com/aegis-public/terraform-modules.git//byoc-gcp?ref=v0.1.16"

  aegis_tenant_id        = "jupiter"
  gcp_service_account_id = "lighthouse"
  kubernetes_namespace   = "jupiter"
  # ... other tenant-specific variables
}
```

### A Note on Naming

The module is named `byoc-gcp` (Bring Your Own Cloud - GCP) while the live configuration directory is `infra/live/connector/`. This naming difference is intentional:

- **`byoc-gcp`**: Describes what the module provisions - BYOC tenant infrastructure on GCP
- **`connector`**: Describes the deployment pattern - these tenants use the workspace-connector service for email ingestion

Both names are correct for their context. The module name reflects the infrastructure pattern, while the directory name reflects the service architecture.

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
cd ~/path/to/aegis-public/terraform-modules
git add byoc-gcp/lakehouse.tf byoc-gcp/variables.tf byoc-gcp/schemas/
git commit -m "Add lakehouse streaming infrastructure"
git tag v0.2.0  # Use semantic versioning
git push origin main --tags
```

### 3. Test with Staging Tenant

Update the staging tenant (`reasonablesecurityai`) to use the new version:

```bash
cd ~/path/to/reasonable-security/infra/live/connector

# Edit reasonablesecurityai.tf - update the module source ref
# Change: ref=v0.1.16 -> ref=v0.2.0

terraform init -upgrade  # Fetch new module version
terraform plan           # Review changes carefully
terraform apply          # Apply after approval
```

Verify the changes work correctly with `reasonablesecurityai` before rolling out to other tenants.

### 4. Roll Out to Production Tenants

After validating with the staging tenant, update production tenants incrementally:

```bash
# Update other tenant files to use the new version
# Edit jupiter.tf, aegis.tf, etc. - change ref=v0.1.16 -> ref=v0.2.0

terraform plan   # Review all changes
terraform apply  # Apply after approval
```

## Versioning

This repository uses [Semantic Versioning](https://semver.org/):

- **MAJOR** (v1.0.0 -> v2.0.0): Breaking changes to module interface
- **MINOR** (v0.1.0 -> v0.2.0): New features, backward compatible
- **PATCH** (v0.1.0 -> v0.1.1): Bug fixes, backward compatible

### Version History

| Version | Description |
|---------|-------------|
| v0.2.0  | Add lakehouse streaming infrastructure (BigQuery) |
| v0.1.16 | Current stable version |

## Module Reference

### byoc-gcp Variables

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `aegis_tenant_id` | string | yes | Short tenant identifier (e.g., "jupiter") |
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

## Related Documentation

- [BYOC Tenant Onboarding](../CLAUDE.md#onboarding-new-byoc-tenants) - Full onboarding process in reasonable-security repo
- [workspace-connector](../workspace-connector/) - BYOC email ingestion service
- [Lighthouse](../lighthouse/) - Email classification service

## Support

For questions about these modules, contact the Aegis platform team.
