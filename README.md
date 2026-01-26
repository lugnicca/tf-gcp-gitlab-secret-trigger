# Terraform GCP Secret Manager to GitLab CI Trigger

Terraform module that automatically triggers a GitLab CI pipeline when GCP Secret Manager secrets with specific labels are created, updated, or deleted.

## Architecture

```
Secret Manager --> Cloud Audit Logs --> Eventarc (global) --> Cloud Function Gen2 --> GitLab API
                                                                      |
                                                                      └── Label filtering
```

## Quick Start

### 1. Run the setup script

**Linux/macOS:**
```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

**Windows (PowerShell):**
```powershell
.\scripts\setup.ps1
```

### 2. Deploy with Terraform

```bash
terraform init
terraform plan
terraform apply
```

### 3. Test the deployment

**Linux/macOS:**
```bash
chmod +x scripts/test.sh
./scripts/test.sh
```

**Windows (PowerShell):**
```powershell
.\scripts\test.ps1
```

## Prerequisites

1. **Terraform** >= 1.3.0
2. **GCP Project** with billing enabled
3. **gcloud CLI** installed and authenticated
4. **GitLab Pipeline Trigger Token** - [GitLab Documentation](https://docs.gitlab.com/ee/ci/triggers/)

### Enable Cloud Audit Logs (Critical!)

Cloud Audit Logs for Secret Manager **must be enabled** for triggers to work:

1. Go to GCP Console → IAM & Admin → Audit Logs
2. Find "Secret Manager API"
3. Enable **"Admin Read"** and **"Data Write"**
4. Click Save

Or use this direct link:
```
https://console.cloud.google.com/iam-admin/audit?project=YOUR_PROJECT_ID
```

> **Note:** The Terraform module automatically configures audit logs via `google_project_iam_audit_config`, but manual verification is recommended.

## Usage

### Basic Example

```hcl
module "secret_gitlab_trigger" {
  source = "path/to/tf-gcp-secret-trigger"

  project_id = "my-gcp-project"
  region     = "europe-west1"

  # Label filtering - only secrets with these labels trigger the pipeline
  required_labels = {
    "trigger-gitlab" = "true"
  }

  # GitLab configuration
  gitlab_url           = "https://gitlab.com"
  gitlab_ref           = "main"
  gitlab_trigger_token = var.gitlab_trigger_token  # Sensitive - use tfvars or env
  gitlab_project_id    = "12345678"
}
```

### Example with Existing Secrets

```hcl
module "secret_gitlab_trigger" {
  source = "path/to/tf-gcp-secret-trigger"

  project_id = "my-gcp-project"
  region     = "europe-west1"

  required_labels = {
    "sync-to-gitlab" = "true"
    "environment"    = "production"
  }

  # Events to monitor
  trigger_on_create = true
  trigger_on_update = true
  trigger_on_delete = false  # Disabled by default

  # GitLab
  gitlab_url = "https://gitlab.company.com"
  gitlab_ref = "develop"

  # Use existing secrets
  create_gitlab_secrets                = false
  existing_gitlab_token_secret_id      = "my-existing-gitlab-token"
  existing_gitlab_project_id_secret_id = "my-existing-gitlab-project-id"
}
```

## Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `project_id` | GCP Project ID | `string` | (required) |
| `region` | GCP region | `string` | `"us-central1"` |
| `function_name` | Cloud Function name | `string` | `"secret-gitlab-trigger"` |
| `required_labels` | Labels required on secrets to trigger | `map(string)` | `{}` |
| `trigger_on_create` | Trigger on secret creation | `bool` | `true` |
| `trigger_on_update` | Trigger on secret version add | `bool` | `true` |
| `trigger_on_delete` | Trigger on secret deletion | `bool` | `false` |
| `gitlab_url` | GitLab instance URL | `string` | `"https://gitlab.com"` |
| `gitlab_ref` | Branch/tag to trigger | `string` | `"main"` |
| `gitlab_trigger_token` | GitLab trigger token | `string` | (required) |
| `gitlab_project_id` | GitLab project ID | `string` | (required) |
| `create_gitlab_secrets` | Create secrets for GitLab credentials | `bool` | `true` |

See `variables.tf` for the complete list.

## Outputs

| Output | Description |
|--------|-------------|
| `function_name` | Deployed Cloud Function name |
| `function_uri` | Cloud Function URI |
| `function_url` | Cloud Function URL |
| `service_account_email` | Service account email |
| `eventarc_triggers` | Map of created Eventarc triggers |
| `source_bucket` | Bucket containing the source code |
| `required_labels` | Configured required labels |

## Variables Passed to GitLab Pipeline

The GitLab pipeline receives the following variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `SECRET_EVENT_TYPE` | Event type | `secret_created`, `secret_updated`, `secret_deleted` |
| `SECRET_NAME` | Secret name | `my-api-key` |
| `SECRET_RESOURCE` | Full resource path | `projects/my-project/secrets/my-api-key` |
| `GCP_PROJECT_ID` | GCP project ID | `my-project` |
| `TRIGGERED_BY` | Trigger source | `gcp-secret-manager-webhook` |

### Example `.gitlab-ci.yml`

```yaml
stages:
  - sync

sync-secrets:
  stage: sync
  rules:
    # Only run when triggered by the GCP webhook
    - if: $CI_PIPELINE_SOURCE == "trigger"
    # Or more specifically:
    # - if: $TRIGGERED_BY == "gcp-secret-manager-webhook"
  script:
    - echo "Secret event: $SECRET_EVENT_TYPE"
    - echo "Secret name: $SECRET_NAME"
    - |
      case $SECRET_EVENT_TYPE in
        secret_created)
          echo "New secret created, syncing..."
          # Your sync logic here
          ;;
        secret_updated)
          echo "Secret updated, refreshing..."
          # Your update logic here
          ;;
        secret_deleted)
          echo "Secret deleted, cleaning up..."
          # Your cleanup logic here
          ;;
      esac
```

## Required IAM Permissions

### For the Function Service Account

- `roles/eventarc.eventReceiver`
- `roles/run.invoker`
- `roles/secretmanager.secretAccessor`
- `roles/secretmanager.viewer`
- `roles/logging.logWriter`

### For Terraform Execution

The identity running Terraform needs:

- `roles/cloudfunctions.admin`
- `roles/eventarc.admin`
- `roles/iam.serviceAccountAdmin`
- `roles/storage.admin`
- `roles/secretmanager.admin`
- `roles/iam.serviceAccountUser`
- `roles/serviceusage.serviceUsageAdmin`

## How Label Filtering Works

1. Eventarc receives **all** Secret Manager events
2. Cloud Function is invoked for each event
3. Function checks if the secret has **all** required labels
4. If yes → triggers GitLab pipeline
5. If no → ignores the event (logs only)

> **Note:** For deletion events (`secret_deleted`), label filtering cannot be verified since the secret no longer exists. The pipeline is triggered anyway if `trigger_on_delete = true`.

## Troubleshooting

### Events don't trigger the function

1. **Check Audit Logs are enabled** for Secret Manager (DATA_WRITE + ADMIN_READ)
2. **Verify Eventarc triggers are in `global` location** (not regional)
   ```bash
   gcloud eventarc triggers list --location=global
   ```
3. **Check Cloud Function logs:**
   ```bash
   gcloud functions logs read YOUR_FUNCTION_NAME --gen2 --region=YOUR_REGION
   ```
4. **Verify IAM permissions** for the service account

### GitLab pipeline doesn't trigger

1. **Error 400 - "pipeline would have been empty":**
   - Your `.gitlab-ci.yml` jobs have rules that exclude trigger events
   - Add `rules: [if: $CI_PIPELINE_SOURCE == "trigger"]` to at least one job

2. **Error 400 - "Reference not found":**
   - The branch specified in `gitlab_ref` doesn't exist
   - Check the default branch of your GitLab project

3. **Error 401/403:**
   - Invalid or expired GitLab trigger token
   - Generate a new token in GitLab: Settings > CI/CD > Pipeline trigger tokens

### Label filtering doesn't work

1. Labels are **case-sensitive** - ensure exact match
2. Both key AND value must match
3. Check logs to see detected vs required labels:
   ```bash
   gcloud logging read 'resource.labels.service_name="YOUR_FUNCTION_NAME"' --limit=20
   ```

## Testing

### Manual Test

Create a secret with the required labels:
```bash
gcloud secrets create test-secret \
  --project=YOUR_PROJECT \
  --labels=trigger-gitlab=true \
  --replication-policy=automatic
```

Check the function logs:
```bash
gcloud logging read 'resource.labels.service_name="secret-gitlab-trigger"' \
  --project=YOUR_PROJECT \
  --limit=10
```

### Automated Test

Run the full test suite:

```bash
# Linux/macOS
./scripts/test.sh

# Windows PowerShell
.\scripts\test.ps1
```

The test script will:
1. Verify infrastructure (Cloud Function, Eventarc triggers)
2. Test GitLab API connectivity
3. Create a test secret and verify the pipeline triggers
4. Test label filtering (create secret without labels, verify it's skipped)
5. Clean up test resources

## Costs

- **Cloud Functions Gen2:** Billed per invocation and execution time
- **Eventarc:** Included in Cloud Audit Logs quotas
- **Cloud Storage:** Minimal storage for source code
- **Secret Manager:** Access to secrets for GitLab credentials

## Important Notes

### Eventarc Location

Eventarc triggers for global services like Secret Manager **must use `location = "global"`**. Regional triggers (e.g., `europe-west1`) will not capture events from global services.

### Audit Log Propagation

After enabling Audit Logs, there may be a short delay (1-2 minutes) before events start being captured.

### GitLab CI Rules

Ensure your `.gitlab-ci.yml` has at least one job that accepts trigger events:

```yaml
# This job will NOT run from triggers (wrong)
deploy:
  rules:
    - if: $CI_PIPELINE_SOURCE == "push"

# This job WILL run from triggers (correct)
deploy:
  rules:
    - if: $CI_PIPELINE_SOURCE == "trigger"
    - if: $CI_PIPELINE_SOURCE == "push"
```

## License

MIT
