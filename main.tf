# =============================================================================
# Enable Required GCP APIs
# =============================================================================

resource "google_project_service" "apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "logging.googleapis.com",
    "storage.googleapis.com",
  ])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = true
}

# =============================================================================
# Enable Cloud Audit Logs for Secret Manager
# =============================================================================

resource "google_project_iam_audit_config" "secretmanager" {
  project = var.project_id
  service = "secretmanager.googleapis.com"

  audit_log_config {
    log_type = "DATA_WRITE"
  }

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_READ"
  }
}

# =============================================================================
# GIT SOURCE - FETCH LATEST TAG AND SOURCE CODE
# =============================================================================

data "external" "fetch_source" {
  program = ["bash", "-c", <<-EOF
    set -e
    TAG=$(git ls-remote --tags --sort=-v:refname "${var.source_git_url}" "v*" | head -1 | sed 's|.*refs/tags/||')
    [ -z "$TAG" ] && echo '{"error":"no tags"}' >&2 && exit 1
    DIR="${path.module}/.terraform/git-source"
    rm -rf "$DIR" && git clone -q --depth 1 --branch "$TAG" "${var.source_git_url}" "$DIR"
    COMMIT=$(git -C "$DIR" rev-parse --short HEAD)
    echo "{\"tag\":\"$TAG\",\"commit\":\"$COMMIT\"}"
  EOF
  ]
}

# =============================================================================
# Local Values
# =============================================================================

locals {
  source_git_tag = data.external.fetch_source.result.tag

  event_method_mapping = {
    secret_version_add     = "google.cloud.secretmanager.v1.SecretManagerService.AddSecretVersion"
    secret_version_enable  = "google.cloud.secretmanager.v1.SecretManagerService.EnableSecretVersion"
    secret_version_disable = "google.cloud.secretmanager.v1.SecretManagerService.DisableSecretVersion"
    secret_version_destroy = "google.cloud.secretmanager.v1.SecretManagerService.DestroySecretVersion"
  }

  enabled_events = {
    for event_type, method in local.event_method_mapping :
    event_type => method if lookup(var.event_types, event_type, false)
  }

  common_labels = merge(
    {
      managed-by = "terraform"
      module     = "secret-gitlab-trigger"
    },
    var.labels
  )
}

# =============================================================================
# Function Source - From Git Repository
# =============================================================================

data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/.terraform/function-source.zip"

  source {
    content  = file("${path.module}/.terraform/git-source/main.py")
    filename = "main.py"
  }

  source {
    content  = file("${path.module}/.terraform/git-source/src/secret_gitlab_trigger/__init__.py")
    filename = "secret_gitlab_trigger/__init__.py"
  }

  source {
    content  = file("${path.module}/.terraform/git-source/requirements.txt")
    filename = "requirements.txt"
  }

  depends_on = [data.external.fetch_source]
}

resource "google_storage_bucket" "function_source" {
  project  = var.project_id
  name     = "${var.project_id}-${var.function_name}-source"
  location = var.region

  labels                      = local.common_labels
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.source_git_tag}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

# =============================================================================
# Cloud Function Gen2
# =============================================================================

resource "google_cloudfunctions2_function" "trigger" {
  project  = var.project_id
  name     = var.function_name
  location = var.region

  labels = local.common_labels

  build_config {
    runtime     = "python312"
    entry_point = "handle_secret_event"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    min_instance_count = 0
    max_instance_count = 10
    timeout_seconds    = 60
    available_memory   = "256Mi"
    available_cpu      = "1"

    service_account_email = google_service_account.function.email

    environment_variables = {
      GITLAB_URL           = var.gitlab_url
      GITLAB_PROJECT_ID    = var.gitlab_project_id
      GITLAB_REF           = var.gitlab_ref
      GITLAB_TRIGGER_TOKEN = var.gitlab_trigger_token
      REQUIRED_LABELS      = jsonencode(var.required_labels)
      GCP_PROJECT_ID       = var.project_id
    }
  }

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.secret_accessor,
    google_project_iam_member.secret_viewer,
    google_project_iam_member.eventarc_event_receiver,
  ]
}
