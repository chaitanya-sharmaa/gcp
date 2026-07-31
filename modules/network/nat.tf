# Phase 2: Outbound Internet Access

# 1. The Cloud Router
# Think of the Cloud Router as the brain behind the scenes. 
# It handles routing and helps the NAT gateway know where to send traffic.
resource "google_compute_router" "router" {
  name    = "gke-router"
  region  = var.region
  network = google_compute_network.main_vpc.id
}

# 2. The Cloud NAT Gateway
# This acts as the translator. When a private GKE node wants to download an 
# image from DockerHub, the NAT gateway hides the node's private IP, fetches 
# the image using a Google public IP, and sends it back to the node.
resource "google_compute_router_nat" "nat" {
  name                               = "gke-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  
  # Google will automatically assign external IPs for our NAT.
  nat_ip_allocate_option             = "AUTO_ONLY"
  
  # We tell the NAT gateway to only provide internet access to our private subnet.
  # The public subnet doesn't need it.
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.private_subnet.id
    # We include secondary ranges (ALL_IP_RANGES) so our Pods also get internet access!
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"] 
  }
}
