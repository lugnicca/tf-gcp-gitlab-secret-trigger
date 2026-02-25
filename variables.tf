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
  default     = "europe-west1"
}

# =============================================================================
# Git Source Configuration
# =============================================================================

variable "source_git_url" {
  description = "HTTPS URL of the Git repository containing the Cloud Function source code"
  type        = string
  default     = "https://github.com/lugnicca/secret-gitlab-trigger-test.git"
}

# =============================================================================
# Function Configuration
# =============================================================================

variable "function_name" {
  description = "Name of the Cloud Function"
  type        = string
  default     = "secret-gitlab-trigger"
}

# =============================================================================
# GitLab Configuration
# =============================================================================

variable "gitlab_url" {
  description = "GitLab instance URL"
  type        = string
  default     = "https://gitlab.com"
}

variable "gitlab_project_id" {
  description = "GitLab project path or numeric ID to trigger"
  type        = string
  default     = ""
}

variable "gitlab_trigger_token" {
  description = "GitLab pipeline trigger token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "gitlab_ref" {
  description = "Git reference (branch/tag) to trigger"
  type        = string
  default     = "main"
}

# =============================================================================
# Event Configuration
# =============================================================================

variable "event_types" {
  description = "Which Secret Manager events should trigger the GitLab pipeline"
  type = object({
    secret_version_add     = bool
    secret_version_enable  = bool
    secret_version_disable = bool
    secret_version_destroy = bool
  })
  default = {
    secret_version_add     = true
    secret_version_enable  = true
    secret_version_disable = true
    secret_version_destroy = true
  }
}

variable "required_labels" {
  description = "Labels that must be present on secrets to trigger the pipeline"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Resource Labels
# =============================================================================

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}
