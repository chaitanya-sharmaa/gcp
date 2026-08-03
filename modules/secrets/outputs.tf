output "secret_id" {
  description = "The ID of the Secret Manager Secret"
  value       = google_secret_manager_secret.db_password.secret_id
}

output "secret_name" {
  description = "The resource name of the Secret"
  value       = google_secret_manager_secret.db_password.name
}

output "gsa_email" {
  description = "The email of the Google Service Account configured for Workload Identity"
  value       = google_service_account.secrets_sa.email
}
