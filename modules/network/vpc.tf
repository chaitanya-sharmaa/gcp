# Step 1: The Foundation - VPCs and Subnets
# 
# A VPC (Virtual Private Cloud) is the global network foundation in GCP.
# 'auto_create_subnetworks = false' ensures we have a custom-mode VPC,
# meaning we explicitly define our subnets and their IP ranges.
resource "google_compute_network" "main_vpc" {
  name                    = "learn-gcp-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL" 
  # REGIONAL routing means Cloud Routers will only learn routes in their region. 
  # GLOBAL allows cross-region dynamic routing.
}

# A subnet is a regional resource. It divides the VPC into smaller networks.
# We are creating a "public" subnet here, though in GCP, "public" usually just means
# instances *can* have external IPs and have a route to the internet gateway.
resource "google_compute_subnetwork" "public_subnet" {
  name          = "public-subnet-${var.region}"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.main_vpc.id
}

# A private subnet. Instances here won't have external IPs.
# We enable 'private_ip_google_access' so instances without public IPs 
# can still reach Google APIs (like Cloud Storage or BigQuery) internally.
resource "google_compute_subnetwork" "private_subnet" {
  name                     = "private-subnet-${var.region}"
  ip_cidr_range            = "10.0.2.0/24"
  region                   = var.region
  network                  = google_compute_network.main_vpc.id
  private_ip_google_access = true

  # Secondary ranges are required for VPC-native GKE clusters.
  # The GKE cluster will use these to assign IPs to Pods and Services.
  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.4.0.0/14"
  }
  
  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.8.0.0/20"
  }
}
