variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "secrets_sa_email" {
  description = "The Google Service Account email for Workload Identity"
  type        = string
}

variable "db_password" {
  description = "The database password"
  type        = string
  sensitive   = true
}

variable "istio_ready" {
  description = "Dependency trigger to ensure Istio CRDs and namespace are deployed first"
  type        = any
  default     = null
}
