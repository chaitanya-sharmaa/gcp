# We output the Load Balancer's public IP address so you can visit the website!
output "frontend_ip" {
  description = "The public IP address of the frontend Static Web App"
  value       = google_compute_global_forwarding_rule.default.ip_address
}
