# =============================================================================
# Service Account for Cloud Function
# =============================================================================

resource "google_service_account" "function_sa" {
  count = var.create_service_account ? 1 : 0

  project      = var.project_id
  account_id   = "${var.function_name}-sa"
  display_name = "Service Account for ${var.function_name} Cloud Function"
  description  = "Used by the secret-gitlab-trigger Cloud Function to receive events and access secrets"
}

locals {
  service_account_email = var.create_service_account ? google_service_account.function_sa[0].email : var.service_account_email
}

# =============================================================================
# IAM Roles for the Function Service Account
# =============================================================================

# Allow receiving events from Eventarc
resource "google_project_iam_member" "eventarc_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${local.service_account_email}"
}

# Allow Cloud Run to be invoked (Cloud Functions Gen2 runs on Cloud Run)
resource "google_project_iam_member" "run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${local.service_account_email}"
}

# Allow reading secret values (for GitLab credentials)
resource "google_project_iam_member" "secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${local.service_account_email}"
}

# Allow reading secret metadata (for label filtering)
resource "google_project_iam_member" "secret_viewer" {
  project = var.project_id
  role    = "roles/secretmanager.viewer"
  member  = "serviceAccount:${local.service_account_email}"
}

# Allow writing logs
resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.service_account_email}"
}

# =============================================================================
# Eventarc Service Agent Permissions
# =============================================================================

data "google_project" "project" {
  project_id = var.project_id
}

# Create the Eventarc service agent by enabling the service identity
resource "google_project_service_identity" "eventarc_sa" {
  provider = google-beta
  project  = var.project_id
  service  = "eventarc.googleapis.com"

  depends_on = [google_project_service.eventarc]
}

# Grant the Eventarc service agent its own role (required for audit log triggers)
resource "google_project_iam_member" "eventarc_service_agent" {
  project = var.project_id
  role    = "roles/eventarc.serviceAgent"
  member  = "serviceAccount:${google_project_service_identity.eventarc_sa.email}"

  depends_on = [google_project_service_identity.eventarc_sa]
}

# Grant the Eventarc service agent permission to invoke Cloud Run services
resource "google_project_iam_member" "eventarc_service_agent_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_project_service_identity.eventarc_sa.email}"

  depends_on = [google_project_service_identity.eventarc_sa]
}

# Wait for IAM permissions to propagate
resource "time_sleep" "wait_for_iam_propagation" {
  depends_on = [
    google_project_iam_member.eventarc_service_agent,
    google_project_iam_member.eventarc_service_agent_invoker,
  ]
  create_duration = "60s"
}

# Grant the Cloud Functions service agent permission to access artifacts
resource "google_project_iam_member" "cloudfunctions_service_agent" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcf-admin-robot.iam.gserviceaccount.com"

  depends_on = [google_project_service.cloudfunctions]
}
