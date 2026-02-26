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
      service = element(split("/", google_cloudfunctions2_function.trigger.service_config[0].service), length(split("/", google_cloudfunctions2_function.trigger.service_config[0].service)) - 1)
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

# =============================================================================
# Log Sinks to route audit logs to Eventarc Pub/Sub topics
#
# Eventarc's native audit-log routing does not always create the required
# Cloud Logging sink automatically.  These explicit sinks guarantee that
# Secret Manager audit-log entries reach the correct Pub/Sub topic.
# =============================================================================

resource "google_logging_project_sink" "secret_event" {
  for_each = local.enabled_events

  project     = var.project_id
  name        = "${var.function_name}-${replace(each.key, "_", "-")}-sink"
  destination = "pubsub.googleapis.com/${google_eventarc_trigger.secret_event[each.key].transport[0].pubsub[0].topic}"
  filter      = "protoPayload.methodName=\"${each.value}\""

  unique_writer_identity = true
}

resource "google_pubsub_topic_iam_member" "logging_publisher" {
  for_each = local.enabled_events

  project = var.project_id
  topic   = google_eventarc_trigger.secret_event[each.key].transport[0].pubsub[0].topic
  role    = "roles/pubsub.publisher"
  member  = google_logging_project_sink.secret_event[each.key].writer_identity
}
