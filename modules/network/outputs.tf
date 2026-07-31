output "vpc_id" {
  description = "The ID of the VPC"
  value       = google_compute_network.main_vpc.id
}

output "private_subnet_id" {
  description = "The ID of the private subnet"
  value       = google_compute_subnetwork.private_subnet.id
}

output "frontend_edge_policy_id" {
  description = "The ID of the Cloud Armor Edge Security Policy"
  value       = google_compute_security_policy.frontend_edge.id
}

output "backend_standard_policy_name" {
  description = "The Name of the Cloud Armor Standard Security Policy"
  value       = google_compute_security_policy.backend_standard.name
}
