terraform {
  backend "gcs" {
    bucket = "tf-state-project-ddfa7a80-7677-4268-95a"
    prefix = "terraform/state/dev"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
