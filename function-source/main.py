"""
Cloud Function to trigger GitLab CI pipelines on Secret Manager events.

This function listens to Cloud Audit Log events from Secret Manager and
triggers a GitLab CI pipeline when secrets with matching labels are
created, updated, or deleted.
"""

import os
import json
import functions_framework
import requests
from cloudevents.http import CloudEvent
from google.cloud import secretmanager


# Initialize Secret Manager client
secret_client = secretmanager.SecretManagerServiceClient()


def get_secret_labels(secret_name: str) -> dict:
    """
    Get labels from a secret resource.

    Args:
        secret_name: Full resource name of the secret
                     (projects/{project}/secrets/{name})

    Returns:
        Dictionary of labels or empty dict if not found
    """
    try:
        # Ensure we're using the secret path without version
        if "/versions/" in secret_name:
            secret_name = secret_name.split("/versions/")[0]

        secret = secret_client.get_secret(request={"name": secret_name})
        return dict(secret.labels) if secret.labels else {}
    except Exception as e:
        print(f"Error getting secret labels for {secret_name}: {e}")
        return {}


def should_trigger_pipeline(labels: dict, required_labels: dict) -> bool:
    """
    Check if secret labels match all required filter labels.

    Args:
        labels: Labels from the secret
        required_labels: Required labels configured in the function

    Returns:
        True if all required labels are present and match
    """
    if not required_labels:
        # No filter configured, trigger for all secrets
        return True

    for key, value in required_labels.items():
        if labels.get(key) != value:
            return False

    return True


def parse_required_labels(labels_str: str) -> dict:
    """
    Parse required labels from environment variable string.

    Args:
        labels_str: Comma-separated key=value pairs (e.g., "env=prod,trigger=true")

    Returns:
        Dictionary of label key-value pairs
    """
    if not labels_str:
        return {}

    labels = {}
    for pair in labels_str.split(","):
        pair = pair.strip()
        if "=" in pair:
            key, value = pair.split("=", 1)
            labels[key.strip()] = value.strip()

    return labels


def extract_secret_info(resource_name: str) -> tuple:
    """
    Extract project and secret name from resource path.

    Args:
        resource_name: Full resource path
                       (projects/{project}/secrets/{name}[/versions/{version}])

    Returns:
        Tuple of (project_id, secret_name)
    """
    parts = resource_name.split("/")
    project_id = parts[1] if len(parts) > 1 else "unknown"
    secret_name = parts[3] if len(parts) > 3 else "unknown"

    return project_id, secret_name


def trigger_gitlab_pipeline(
    gitlab_url: str,
    project_id: str,
    trigger_token: str,
    ref: str,
    variables: dict = None
) -> dict:
    """
    Trigger a GitLab CI pipeline using the Pipeline Trigger API.

    Args:
        gitlab_url: GitLab instance URL
        project_id: GitLab project ID
        trigger_token: Pipeline trigger token
        ref: Git ref (branch/tag) to run pipeline on
        variables: Optional dict of pipeline variables

    Returns:
        API response as dictionary

    Raises:
        requests.exceptions.RequestException: If API call fails
    """
    url = f"{gitlab_url}/api/v4/projects/{project_id}/trigger/pipeline"

    data = {
        "token": trigger_token,
        "ref": ref
    }

    if variables:
        for key, value in variables.items():
            data[f"variables[{key}]"] = value

    response = requests.post(url, data=data, timeout=30)
    response.raise_for_status()

    return response.json()


@functions_framework.cloud_event
def handle_secret_event(cloud_event: CloudEvent) -> None:
    """
    Handle Secret Manager audit log events and trigger GitLab pipelines.

    This function is triggered by Cloud Audit Log events for:
    - google.cloud.secretmanager.v1.SecretManagerService.CreateSecret
    - google.cloud.secretmanager.v1.SecretManagerService.AddSecretVersion
    - google.cloud.secretmanager.v1.SecretManagerService.DeleteSecret

    Args:
        cloud_event: CloudEvent containing the audit log data
    """
    # Extract event data from Cloud Audit Log
    event_data = cloud_event.data
    proto_payload = event_data.get("protoPayload", {})
    method_name = proto_payload.get("methodName", "")
    resource_name = proto_payload.get("resourceName", "")

    print(f"Received event - Method: {method_name}, Resource: {resource_name}")

    # Determine event type based on the method called
    if "CreateSecret" in method_name:
        event_type = "secret_created"
    elif "AddSecretVersion" in method_name:
        event_type = "secret_updated"
    elif "DeleteSecret" in method_name:
        event_type = "secret_deleted"
    else:
        print(f"Ignoring unhandled method: {method_name}")
        return

    # Get configuration from environment variables
    gcp_project_id = os.environ.get("GCP_PROJECT_ID", "")
    gitlab_url = os.environ.get("GITLAB_URL", "https://gitlab.com")
    gitlab_project_id = os.environ.get("GITLAB_PROJECT_ID", "")
    gitlab_trigger_token = os.environ.get("GITLAB_TRIGGER_TOKEN", "")
    gitlab_ref = os.environ.get("GITLAB_REF", "main")
    required_labels_str = os.environ.get("REQUIRED_LABELS", "")

    # Validate required configuration
    if not gitlab_project_id or not gitlab_trigger_token:
        print("ERROR: Missing GitLab configuration (GITLAB_PROJECT_ID or GITLAB_TRIGGER_TOKEN)")
        return

    # Parse required labels for filtering
    required_labels = parse_required_labels(required_labels_str)

    # Extract secret information
    _, secret_name = extract_secret_info(resource_name)

    # Get secret path without version for label lookup
    secret_path = resource_name.split("/versions/")[0] if "/versions/" in resource_name else resource_name

    # Check labels (skip for delete events since the secret no longer exists)
    if event_type != "secret_deleted" and required_labels:
        labels = get_secret_labels(secret_path)

        if not should_trigger_pipeline(labels, required_labels):
            print(f"Secret '{secret_name}' labels {labels} do not match required labels {required_labels}. Skipping pipeline trigger.")
            return

        print(f"Secret '{secret_name}' labels {labels} match required labels {required_labels}")
    elif event_type == "secret_deleted" and required_labels:
        print(f"Note: Cannot verify labels for deleted secret '{secret_name}'. Triggering pipeline anyway.")

    # Prepare pipeline variables to pass context to GitLab CI
    pipeline_variables = {
        "SECRET_EVENT_TYPE": event_type,
        "SECRET_NAME": secret_name,
        "SECRET_RESOURCE": resource_name,
        "GCP_PROJECT_ID": gcp_project_id,
        "TRIGGERED_BY": "gcp-secret-manager-webhook"
    }

    # Trigger the GitLab pipeline
    try:
        result = trigger_gitlab_pipeline(
            gitlab_url=gitlab_url,
            project_id=gitlab_project_id,
            trigger_token=gitlab_trigger_token,
            ref=gitlab_ref,
            variables=pipeline_variables
        )

        pipeline_id = result.get("id", "unknown")
        pipeline_url = result.get("web_url", "N/A")

        print(f"Successfully triggered GitLab pipeline #{pipeline_id}")
        print(f"Pipeline URL: {pipeline_url}")
        print(f"Event type: {event_type}, Secret: {secret_name}")

    except requests.exceptions.RequestException as e:
        print(f"ERROR: Failed to trigger GitLab pipeline: {e}")
        raise
