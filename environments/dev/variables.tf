variable "project_id" {
  description = "The GCP Project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The primary region for networking resources"
  type        = string
  default     = "us-central1"
}

variable "secondary_region" {
  description = "The secondary region for networking resources"
  type        = string
  default     = "us-east4"
}

variable "db_password" {
  description = "Password for the database"
  type        = string
  default     = "SuperSecret123!" # Safe default for our temporary test
}

variable "backend_url" {
  description = "The URL of the backend API (we will update this in Phase 6)"
  type        = string
  default     = "https://35.244.177.223"
}
