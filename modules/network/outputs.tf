output "vpc_id" {
  description = "The ID of the VPC"
  value       = google_compute_network.main_vpc.id
}

output "private_subnet_id" {
  description = "The ID of the private subnet"
  value       = google_compute_subnetwork.private_subnet.id
}
