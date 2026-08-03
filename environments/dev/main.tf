module "network" {
  # This points Terraform to our local module directory
  source = "../../modules/network"

  # We pass the region variable from the dev environment into the module
  region = var.region
}

module "gke" {
  source     = "../../modules/gke"
  
  project_id = var.project_id
  zone       = "${var.region}-a" # Deploys to a specific zone for cost savings
  vpc_id     = module.network.vpc_id
  subnet_id  = module.network.private_subnet_id
}

module "database" {
  source      = "../../modules/database"
  region      = var.region
  vpc_id      = module.network.vpc_id
  db_password = var.db_password
}

module "secrets" {
  source      = "../../modules/secrets"
  project_id  = var.project_id
  db_password = var.db_password
}

# PHASE 7: SSL Certificate Generation (Self-Signed)
resource "tls_private_key" "main" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "main" {
  private_key_pem = tls_private_key.main.private_key_pem

  subject {
    common_name  = "frontend.local"
    organization = "Learning GCP"
  }

  validity_period_hours = 24
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# Save the certs locally so we can inject them into Kubernetes!
resource "local_file" "tls_key" {
  content  = tls_private_key.main.private_key_pem
  filename = "${path.module}/tls.key"
}

resource "local_file" "tls_crt" {
  content  = tls_self_signed_cert.main.cert_pem
  filename = "${path.module}/tls.crt"
}

module "istio" {
  source              = "../../modules/istio"
  ssl_cert_pem        = tls_self_signed_cert.main.cert_pem
  ssl_private_key_pem = tls_private_key.main.private_key_pem
}

module "backend_app" {
  source           = "../../modules/backend_app"
  project_id       = var.project_id
  secrets_sa_email = module.secrets.gsa_email
  db_password      = var.db_password
  istio_ready      = module.istio.istio_namespace
}

module "frontend" {
  source                  = "../../modules/frontend"
  backend_url             = module.backend_app.backend_url
  ssl_private_key_pem     = tls_private_key.main.private_key_pem
  ssl_cert_pem            = tls_self_signed_cert.main.cert_pem
}

output "website_url" {
  description = "Click here to view your secure static frontend!"
  value       = "https://${module.frontend.frontend_ip}"
}

output "backend_url" {
  description = "The automated HTTPS URL for the backend API"
  value       = module.backend_app.backend_url
}

output "secrets_sa_email" {
  description = "The Google Service Account email used by Workload Identity for Secret Manager"
  value       = module.secrets.gsa_email
}


