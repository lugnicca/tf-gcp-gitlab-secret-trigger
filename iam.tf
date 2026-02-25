# =============================================================================
# Service Account
# =============================================================================

resource "google_service_account" "function" {
  project      = var.project_id
  account_id   = "${var.function_name}-sa"
  display_name = "Service Account for ${var.function_name} Cloud Function"
}

# =============================================================================
# IAM Roles for the Function Service Account
# =============================================================================

resource "google_project_iam_member" "secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.function.email}"
}

resource "google_project_iam_member" "secret_viewer" {
  project = var.project_id
  role    = "roles/secretmanager.viewer"
  member  = "serviceAccount:${google_service_account.function.email}"
}

resource "google_project_iam_member" "eventarc_event_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.function.email}"
}

resource "google_cloud_run_service_iam_member" "eventarc_invoker" {
  project  = var.project_id
  location = var.region
  service  = google_cloudfunctions2_function.trigger.service_config[0].service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.function.email}"
}

# =============================================================================
# Eventarc Service Agent (required for fresh projects)
# =============================================================================

resource "google_project_service_identity" "eventarc_sa" {
  provider = google-beta
  project  = var.project_id
  service  = "eventarc.googleapis.com"

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "eventarc_service_agent" {
  project = var.project_id
  role    = "roles/eventarc.serviceAgent"
  member  = "serviceAccount:${google_project_service_identity.eventarc_sa.email}"
}
