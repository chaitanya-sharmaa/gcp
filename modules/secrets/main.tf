# 0. Enable Secret Manager API
resource "google_project_service" "secretmanager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

# 1. The Secret Resource in Google Secret Manager
resource "google_secret_manager_secret" "db_password" {
  secret_id  = "db-password"
  depends_on = [google_project_service.secretmanager]

  replication {
    auto {}
  }
}

# 2. The Initial Secret Version (Stores the DB Password)
resource "google_secret_manager_secret_version" "db_password_version" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}

# 3. Google Service Account (GSA) dedicated for GKE Secret Access
resource "google_service_account" "secrets_sa" {
  account_id   = "gke-secrets-sa"
  display_name = "GKE Secret Manager Accessor Service Account"
}

# 4. Grant the GSA access to read this specific secret
resource "google_secret_manager_secret_iam_member" "secret_accessor" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.secrets_sa.email}"
}

# 5. Workload Identity Binding: Allow K8s Service Account 'backend-sa' to impersonate the GSA
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.secrets_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[default/backend-sa]"
}
