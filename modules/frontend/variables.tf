variable "backend_url" {
  description = "The URL of the backend API (e.g. http://34.120.x.x). Used in the frontend Javascript."
  type        = string
  default     = "http://PENDING-BACKEND-IP"
}

variable "ssl_cert_pem" {
  description = "The SSL certificate in PEM format"
  type        = string
}

variable "ssl_private_key_pem" {
  description = "The SSL private key in PEM format"
  type        = string
}

variable "edge_security_policy_id" {
  description = "The ID of the Cloud Armor Edge Security Policy"
  type        = string
}
