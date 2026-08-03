variable "ssl_cert_pem" {
  description = "The TLS Certificate PEM string for backend-tls secret"
  type        = string
}

variable "ssl_private_key_pem" {
  description = "The TLS Private Key PEM string for backend-tls secret"
  type        = string
  sensitive   = true
}
