# =============================================================================
# Outputs
# =============================================================================

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.main.name
}

output "function_uri" {
  description = "URI of the Cloud Function"
  value       = google_cloudfunctions2_function.main.service_config[0].uri
}

output "function_url" {
  description = "HTTPS URL of the Cloud Function (same as URI)"
  value       = google_cloudfunctions2_function.main.url
}

output "service_account_email" {
  description = "Email of the service account used by the function"
  value       = local.service_account_email
}

output "eventarc_triggers" {
  description = "Map of created Eventarc trigger names by event type"
  value = {
    secret_created = var.trigger_on_create ? google_eventarc_trigger.secret_created[0].name : null
    secret_updated = var.trigger_on_update ? google_eventarc_trigger.secret_updated[0].name : null
    secret_deleted = var.trigger_on_delete ? google_eventarc_trigger.secret_deleted[0].name : null
  }
}

output "source_bucket" {
  description = "Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "gitlab_token_secret_id" {
  description = "Secret Manager secret ID for GitLab trigger token"
  value       = local.gitlab_token_secret_id
}

output "gitlab_project_id_secret_id" {
  description = "Secret Manager secret ID for GitLab project ID"
  value       = local.gitlab_project_id_secret_id
}

output "required_labels" {
  description = "Labels configured for filtering secrets"
  value       = var.required_labels
}
