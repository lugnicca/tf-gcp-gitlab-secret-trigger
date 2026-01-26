# =============================================================================
# GitLab Credentials Secrets
# =============================================================================

# GitLab Pipeline Trigger Token
resource "google_secret_manager_secret" "gitlab_token" {
  count = var.create_gitlab_secrets ? 1 : 0

  project   = var.project_id
  secret_id = "${var.function_name}-gitlab-token"

  replication {
    auto {}
  }

  labels = merge(var.labels, {
    managed-by = "terraform"
    purpose    = "gitlab-trigger"
  })

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "gitlab_token" {
  count = var.create_gitlab_secrets ? 1 : 0

  secret      = google_secret_manager_secret.gitlab_token[0].id
  secret_data = var.gitlab_trigger_token
}

# GitLab Project ID
resource "google_secret_manager_secret" "gitlab_project_id" {
  count = var.create_gitlab_secrets ? 1 : 0

  project   = var.project_id
  secret_id = "${var.function_name}-gitlab-project-id"

  replication {
    auto {}
  }

  labels = merge(var.labels, {
    managed-by = "terraform"
    purpose    = "gitlab-trigger"
  })

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "gitlab_project_id" {
  count = var.create_gitlab_secrets ? 1 : 0

  secret      = google_secret_manager_secret.gitlab_project_id[0].id
  secret_data = var.gitlab_project_id
}

# =============================================================================
# Local values for secret references
# =============================================================================

locals {
  gitlab_token_secret_id = var.create_gitlab_secrets ? google_secret_manager_secret.gitlab_token[0].secret_id : var.existing_gitlab_token_secret_id

  gitlab_project_id_secret_id = var.create_gitlab_secrets ? google_secret_manager_secret.gitlab_project_id[0].secret_id : var.existing_gitlab_project_id_secret_id
}
