variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "zone" {
  description = "The zone to deploy the GKE cluster in (for free tier)"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "subnet_id" {
  description = "The ID of the private subnet"
  type        = string
}
