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

# 3. Allow GKE Master to communicate with Webhooks (Istio, etc.) on Worker Nodes
resource "google_compute_firewall" "allow_gke_master_to_nodes" {
  name    = "allow-gke-master-to-nodes"
  network = google_compute_network.main_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["15017", "15012", "8443", "443", "8080", "9443"]
  }

  source_ranges = ["172.16.0.0/28"] # GKE master CIDR block
}

# 4. Allow Google Cloud Load Balancer & Health Checks
resource "google_compute_firewall" "allow_gclb_health_checks" {
  name    = "allow-gclb-health-checks"
  network = google_compute_network.main_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080", "15021", "30000-32767"]
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]
}

