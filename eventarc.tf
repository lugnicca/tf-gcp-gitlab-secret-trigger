# =============================================================================
# Eventarc Triggers for Secret Manager Events
# =============================================================================

resource "google_eventarc_trigger" "secret_event" {
  for_each = local.enabled_events

  project  = var.project_id
  name     = "${var.function_name}-${replace(each.key, "_", "-")}"
  location = var.region

  labels = local.common_labels

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.audit.log.v1.written"
  }

  matching_criteria {
    attribute = "serviceName"
    value     = "secretmanager.googleapis.com"
  }

  matching_criteria {
    attribute = "methodName"
    value     = each.value
  }

  destination {
    cloud_run_service {
      service = google_cloudfunctions2_function.trigger.service_config[0].service
      region  = var.region
    }
  }

  service_account = google_service_account.function.email

  depends_on = [
    google_project_iam_member.eventarc_event_receiver,
    google_cloud_run_service_iam_member.eventarc_invoker,
    google_project_iam_member.eventarc_service_agent,
    google_project_iam_audit_config.secretmanager,
  ]
}
