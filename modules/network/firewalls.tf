# Step 2: Security - Firewall Rules and IAP

# 1. Internal Communication
# Allow instances within our VPC to communicate with each other freely.
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.main_vpc.name

  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = ["10.0.0.0/16"] # Covers both our subnets (10.0.1.0/24 and 10.0.2.0/24)
}

# 2. SSH Access via IAP
# Identity-Aware Proxy allows secure access to VMs without external IPs.
# IAP uses a specific IP range for its forwarding instances: 35.235.240.0/20
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "allow-iap-ssh"
  network = google_compute_network.main_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # IAP IP range
}
