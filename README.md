# Terraform GCP Secret Manager to GitLab CI Trigger

Terraform config that automatically triggers a GitLab CI pipeline when GCP Secret Manager secrets with specific labels are modified.

The function source code is fetched directly from a Git repository at the latest tag.

## Architecture

```
Git repo (secret-gitlab-trigger-test)
  --> Terraform clones latest tag
  --> Archives source into ZIP
  --> Uploads to GCS

Secret Manager event
  --> Cloud Audit Logs
  --> Eventarc trigger
  --> Cloud Function Gen2
  --> Label filtering
  --> GitLab Trigger API
```

## Quick Start

```bash
# 1. Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 2. Deploy
./scripts/setup.sh

# 3. Test
./scripts/test.sh

# 4. Teardown
./scripts/teardown.sh
```

## Prerequisites

- **Terraform** >= 1.10.0
- **GCP Project** with billing enabled
- **gcloud CLI** authenticated (`gcloud auth application-default login`)
- **git** (used by Terraform to clone the function source)
- **GitLab Pipeline Trigger Token** ([docs](https://docs.gitlab.com/ee/ci/triggers/))

## How It Works

### Deployment

1. `terraform plan` runs `git ls-remote` to detect the latest `v*` tag on the source repo
2. Clones the repo at that tag (`--depth 1`)
3. Archives `main.py`, `secret_gitlab_trigger/__init__.py`, and `requirements.txt` into a ZIP
4. Uploads the ZIP to a GCS bucket
5. Deploys a Cloud Function Gen2 with the ZIP as source
6. Creates Eventarc triggers for each enabled event type

### Runtime

1. A Secret Manager operation generates a Cloud Audit Log
2. Eventarc matches the event and invokes the Cloud Function
3. The function reads the secret's labels
4. If labels match `required_labels`, triggers a GitLab pipeline
5. Pipeline receives: `SECRET_EVENT_TYPE`, `SECRET_NAME`, `SECRET_RESOURCE`, `GCP_PROJECT_ID`, `TRIGGERED_BY`

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `project_id` | GCP Project ID | (required) |
| `region` | GCP region | `europe-west1` |
| `source_git_url` | Git repo URL for function source | `https://github.com/lugnicca/secret-gitlab-trigger-test.git` |
| `function_name` | Cloud Function name | `secret-gitlab-trigger` |
| `gitlab_url` | GitLab instance URL | `https://gitlab.com` |
| `gitlab_project_id` | GitLab project ID or path | `""` |
| `gitlab_trigger_token` | GitLab trigger token (sensitive) | `""` |
| `gitlab_ref` | Branch/tag to trigger | `main` |
| `event_types` | Which events to listen to | all `true` |
| `required_labels` | Labels secrets must have to trigger | `{}` |
| `labels` | Labels for Terraform-managed resources | `{}` |

### Event Types

```hcl
event_types = {
  secret_version_add     = true   # New version added
  secret_version_enable  = true   # Version re-enabled
  secret_version_disable = true   # Version disabled
  secret_version_destroy = true   # Version destroyed
}
```

## Outputs

| Output | Description |
|--------|-------------|
| `function_name` | Deployed Cloud Function name |
| `function_uri` | Cloud Function URL |
| `service_account_email` | Service account email |
| `eventarc_trigger_names` | Map of Eventarc trigger names |
| `enabled_event_types` | List of enabled event types |
| `source_bucket_name` | GCS bucket for source code |
| `deployed_git_ref` | Git tag and commit deployed |

## Updating the Function Source

When a new tag is pushed to the source repo:

```bash
# In the source repo
git tag v1.0.4
git push origin v1.0.4

# In this repo
terraform plan   # detects new tag
terraform apply  # redeploys the function
```

## IAM Created

| Role | Principal | Purpose |
|------|-----------|---------|
| `roles/secretmanager.secretAccessor` | Function SA | Read secret values |
| `roles/secretmanager.viewer` | Function SA | Read secret metadata/labels |
| `roles/eventarc.eventReceiver` | Function SA | Receive Eventarc events |
| `roles/run.invoker` | Function SA | Eventarc invokes Cloud Run |
| `roles/eventarc.serviceAgent` | Eventarc SA | Eventarc service agent |

## Troubleshooting

### No events received

```bash
# Check function is ACTIVE
gcloud functions describe secret-gitlab-trigger --region=europe-west1 --gen2

# Check Eventarc triggers
gcloud eventarc triggers list --location=europe-west1

# Check audit logs exist
gcloud logging read 'protoPayload.serviceName="secretmanager.googleapis.com"' --limit=5
```

### Function receives event but no pipeline

```bash
# Check function logs
gcloud functions logs read secret-gitlab-trigger --region=europe-west1 --gen2 --limit=20
```

Common causes:
- Labels don't match `required_labels`
- Invalid/expired GitLab trigger token
- `gitlab_project_id` is wrong
- GitLab CI has no jobs matching `$CI_PIPELINE_SOURCE == "trigger"`

## License

MIT
