output "release_name" {
  description = "The name of the backend Helm release"
  value       = helm_release.backend_app.name
}

output "release_namespace" {
  description = "The namespace of the backend Helm release"
  value       = helm_release.backend_app.namespace
}

output "backend_ip" {
  description = "The static external IP address of the Backend Ingress"
  value       = google_compute_global_address.backend_ip.address
}

output "backend_url" {
  description = "The full HTTPS URL for the backend API"
  value       = "https://${google_compute_global_address.backend_ip.address}"
}
