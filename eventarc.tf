# =============================================================================
# Eventarc Triggers for Secret Manager Events
# =============================================================================
#
# These triggers listen to Cloud Audit Logs from Secret Manager.
# Note: Eventarc does not support filtering by labels, so all events are
# received and filtering is done in the Cloud Function code.
#
# IMPORTANT: Secret Manager is a global service, so triggers must use
# location = "global" to capture audit log events from all regions.
#
# =============================================================================

# -----------------------------------------------------------------------------
# Trigger for Secret Creation
# -----------------------------------------------------------------------------
resource "google_eventarc_trigger" "secret_created" {
  count = var.trigger_on_create ? 1 : 0

  project  = var.project_id
  name     = "${var.function_name}-secret-created"
  location = "global"

  # Match Cloud Audit Log events
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
    value     = "google.cloud.secretmanager.v1.SecretManagerService.CreateSecret"
  }

  # Route to Cloud Function (via Cloud Run service)
  destination {
    cloud_run_service {
      service = google_cloudfunctions2_function.main.name
      region  = var.region
    }
  }

  service_account = local.service_account_email

  labels = merge(var.labels, {
    managed-by  = "terraform"
    event-type  = "secret-created"
  })

  depends_on = [
    google_cloudfunctions2_function.main,
    google_project_iam_member.eventarc_receiver,
    google_project_iam_member.eventarc_service_agent_invoker,
    google_project_iam_audit_config.secretmanager,
    time_sleep.wait_for_iam_propagation,
  ]
}

# -----------------------------------------------------------------------------
# Trigger for Secret Version Added (Update)
# -----------------------------------------------------------------------------
resource "google_eventarc_trigger" "secret_updated" {
  count = var.trigger_on_update ? 1 : 0

  project  = var.project_id
  name     = "${var.function_name}-secret-updated"
  location = "global"

  # Match Cloud Audit Log events
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
    value     = "google.cloud.secretmanager.v1.SecretManagerService.AddSecretVersion"
  }

  # Route to Cloud Function (via Cloud Run service)
  destination {
    cloud_run_service {
      service = google_cloudfunctions2_function.main.name
      region  = var.region
    }
  }

  service_account = local.service_account_email

  labels = merge(var.labels, {
    managed-by  = "terraform"
    event-type  = "secret-updated"
  })

  depends_on = [
    google_cloudfunctions2_function.main,
    google_project_iam_member.eventarc_receiver,
    google_project_iam_member.eventarc_service_agent_invoker,
    google_project_iam_audit_config.secretmanager,
    time_sleep.wait_for_iam_propagation,
  ]
}

# -----------------------------------------------------------------------------
# Trigger for Secret Deletion
# -----------------------------------------------------------------------------
resource "google_eventarc_trigger" "secret_deleted" {
  count = var.trigger_on_delete ? 1 : 0

  project  = var.project_id
  name     = "${var.function_name}-secret-deleted"
  location = "global"

  # Match Cloud Audit Log events
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
    value     = "google.cloud.secretmanager.v1.SecretManagerService.DeleteSecret"
  }

  # Route to Cloud Function (via Cloud Run service)
  destination {
    cloud_run_service {
      service = google_cloudfunctions2_function.main.name
      region  = var.region
    }
  }

  service_account = local.service_account_email

  labels = merge(var.labels, {
    managed-by  = "terraform"
    event-type  = "secret-deleted"
  })

  depends_on = [
    google_cloudfunctions2_function.main,
    google_project_iam_member.eventarc_receiver,
    google_project_iam_member.eventarc_service_agent_invoker,
    google_project_iam_audit_config.secretmanager,
    time_sleep.wait_for_iam_propagation,
  ]
}
