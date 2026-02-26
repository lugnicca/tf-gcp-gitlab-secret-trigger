# =============================================================================
# Outputs
# =============================================================================

output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.trigger.name
}

output "function_uri" {
  description = "URI of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.trigger.url
}

output "service_account_email" {
  description = "Email of the service account used by the function"
  value       = google_service_account.function.email
}

output "eventarc_trigger_names" {
  description = "Names of the created Eventarc triggers"
  value       = { for k, v in google_eventarc_trigger.secret_event : k => element(split("/", v.name), length(split("/", v.name)) - 1) }
}

output "enabled_event_types" {
  description = "List of enabled event types"
  value       = keys(local.enabled_events)
}

output "source_bucket_name" {
  description = "Name of the GCS bucket storing the function source"
  value       = google_storage_bucket.function_source.name
}

output "deployed_git_ref" {
  description = "Git tag and commit of the deployed source"
  value = {
    tag    = data.external.fetch_source.result.tag
    commit = data.external.fetch_source.result.commit
  }
}
