# =============================================================================
# Project Configuration
# =============================================================================

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

# =============================================================================
# Function Configuration
# =============================================================================

variable "function_name" {
  description = "Name of the Cloud Function"
  type        = string
  default     = "secret-gitlab-trigger"
}

variable "function_description" {
  description = "Description of the Cloud Function"
  type        = string
  default     = "Triggers GitLab pipeline on Secret Manager events"
}

variable "function_memory" {
  description = "Memory allocation for the function in MB"
  type        = number
  default     = 256
}

variable "function_timeout" {
  description = "Function timeout in seconds"
  type        = number
  default     = 60
}

variable "function_min_instances" {
  description = "Minimum number of function instances"
  type        = number
  default     = 0
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
}

# =============================================================================
# Label Filtering (applied in function code)
# =============================================================================

variable "required_labels" {
  description = "Map of labels that secrets must have to trigger pipeline. Only secrets with ALL these labels will trigger the pipeline."
  type        = map(string)
  default     = {}
}

# =============================================================================
# Event Types to Trigger On
# =============================================================================

variable "trigger_on_create" {
  description = "Trigger pipeline when secrets are created"
  type        = bool
  default     = true
}

variable "trigger_on_update" {
  description = "Trigger pipeline when secret versions are added"
  type        = bool
  default     = true
}

variable "trigger_on_delete" {
  description = "Trigger pipeline when secrets are deleted"
  type        = bool
  default     = false
}

# =============================================================================
# GitLab Configuration
# =============================================================================

variable "gitlab_url" {
  description = "GitLab instance URL (e.g., https://gitlab.com or https://gitlab.yourcompany.com)"
  type        = string
  default     = "https://gitlab.com"
}

variable "gitlab_ref" {
  description = "Git ref (branch/tag) to trigger pipeline on"
  type        = string
  default     = "main"
}

# =============================================================================
# GitLab Credentials - Secret Management
# =============================================================================

variable "create_gitlab_secrets" {
  description = "Whether to create Secret Manager secrets for GitLab credentials. If false, you must provide existing secret IDs."
  type        = bool
  default     = true
}

# Used when create_gitlab_secrets = true
variable "gitlab_trigger_token" {
  description = "GitLab Pipeline Trigger Token (only used if create_gitlab_secrets = true)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "gitlab_project_id" {
  description = "GitLab Project ID (only used if create_gitlab_secrets = true)"
  type        = string
  default     = ""
}

# Used when create_gitlab_secrets = false
variable "existing_gitlab_token_secret_id" {
  description = "Existing Secret Manager secret ID for GitLab trigger token (only used if create_gitlab_secrets = false)"
  type        = string
  default     = ""
}

variable "existing_gitlab_project_id_secret_id" {
  description = "Existing Secret Manager secret ID for GitLab project ID (only used if create_gitlab_secrets = false)"
  type        = string
  default     = ""
}

# =============================================================================
# Service Account Configuration
# =============================================================================

variable "create_service_account" {
  description = "Whether to create a new service account or use an existing one"
  type        = bool
  default     = true
}

variable "service_account_email" {
  description = "Existing service account email (only used if create_service_account = false)"
  type        = string
  default     = ""
}

# =============================================================================
# Labels for resources created by this module
# =============================================================================

variable "labels" {
  description = "Labels to apply to all resources created by this module"
  type        = map(string)
  default     = {}
}
