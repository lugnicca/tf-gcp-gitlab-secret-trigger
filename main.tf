# =============================================================================
# Enable Required GCP APIs
# =============================================================================

resource "google_project_service" "cloudfunctions" {
  project            = var.project_id
  service            = "cloudfunctions.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  project            = var.project_id
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "eventarc" {
  project            = var.project_id
  service            = "eventarc.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "run" {
  project            = var.project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "logging" {
  project            = var.project_id
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage" {
  project            = var.project_id
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# =============================================================================
# Enable Cloud Audit Logs for Secret Manager
# =============================================================================
# CRITICAL: This is required for Eventarc triggers to work.
# Without this, Secret Manager operations don't generate audit log events,
# and the Cloud Function will never be triggered.
# =============================================================================

resource "google_project_iam_audit_config" "secretmanager" {
  project = var.project_id
  service = "secretmanager.googleapis.com"

  # DATA_WRITE captures: CreateSecret, AddSecretVersion, DeleteSecret
  audit_log_config {
    log_type = "DATA_WRITE"
  }

  # ADMIN_READ captures metadata access (needed for some edge cases)
  audit_log_config {
    log_type = "ADMIN_READ"
  }
}

# =============================================================================
# Cloud Storage for Function Source Code
# =============================================================================

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "function_source" {
  project                     = var.project_id
  name                        = "${var.project_id}-${var.function_name}-src-${random_id.bucket_suffix.hex}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  versioning {
    enabled = true
  }

  labels = merge(var.labels, {
    managed-by = "terraform"
    purpose    = "cloud-function-source"
  })

  depends_on = [google_project_service.storage]
}

# =============================================================================
# Archive and Upload Function Source
# =============================================================================

data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = "${path.module}/function-source"
  output_path = "${path.module}/.terraform/tmp/function-source.zip"
}

resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

# =============================================================================
# Local values for function configuration
# =============================================================================

locals {
  # Convert required_labels map to comma-separated string for env var
  required_labels_str = join(",", [for k, v in var.required_labels : "${k}=${v}"])
}

# =============================================================================
# Cloud Function Gen 2
# =============================================================================

resource "google_cloudfunctions2_function" "main" {
  project     = var.project_id
  name        = var.function_name
  location    = var.region
  description = var.function_description

  build_config {
    runtime     = "python311"
    entry_point = "handle_secret_event"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    min_instance_count             = var.function_min_instances
    max_instance_count             = var.function_max_instances
    available_memory               = "${var.function_memory}M"
    timeout_seconds                = var.function_timeout
    service_account_email          = local.service_account_email
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true

    environment_variables = {
      GCP_PROJECT_ID  = var.project_id
      GITLAB_URL      = var.gitlab_url
      GITLAB_REF      = var.gitlab_ref
      REQUIRED_LABELS = local.required_labels_str
    }

    secret_environment_variables {
      key        = "GITLAB_TRIGGER_TOKEN"
      project_id = var.project_id
      secret     = local.gitlab_token_secret_id
      version    = "latest"
    }

    secret_environment_variables {
      key        = "GITLAB_PROJECT_ID"
      project_id = var.project_id
      secret     = local.gitlab_project_id_secret_id
      version    = "latest"
    }
  }

  labels = merge(var.labels, {
    managed-by = "terraform"
  })

  depends_on = [
    google_project_service.cloudfunctions,
    google_project_service.cloudbuild,
    google_project_service.run,
    google_project_service.artifactregistry,
    google_project_iam_member.eventarc_receiver,
    google_project_iam_member.run_invoker,
    google_project_iam_member.secret_accessor,
    google_project_iam_member.secret_viewer,
    google_secret_manager_secret_version.gitlab_token,
    google_secret_manager_secret_version.gitlab_project_id,
  ]
}
