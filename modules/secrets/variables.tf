variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "db_password" {
  description = "The password for the PostgreSQL Database to store in Secret Manager"
  type        = string
  sensitive   = true
}
