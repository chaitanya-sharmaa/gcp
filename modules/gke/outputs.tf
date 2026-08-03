output "cluster_name" {
  description = "The name of the GKE cluster"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "The IP endpoint of the GKE cluster control plane"
  value       = google_container_cluster.primary.endpoint
}

output "cluster_ca_certificate" {
  description = "The public CA certificate of the GKE cluster"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
}
