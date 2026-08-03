# Phase 3: The GKE Cluster

resource "google_container_cluster" "primary" {
  name     = "my-gke-cluster"
  
  deletion_protection = false

  # COST SAVING: Using a single zone (e.g., us-central1-a) instead of a region 
  # allows us to use the GKE Free Tier for the control plane (saves ~$72/month).
  location = var.zone
  
  # We want to use our own custom node pool, so we delete the default one immediately.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Network Configuration (Pointing to the network module's outputs)
  network    = var.vpc_id
  subnetwork = var.subnet_id

  # PRODUCTION GRADE: VPC-Native Cluster using our secondary ranges
  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  # PRODUCTION GRADE: Private Cluster
  private_cluster_config {
    enable_private_nodes    = true
    
    # We leave the endpoint public (false) so you can easily run `kubectl` from 
    # your laptop without setting up a VPN. In strict environments, this is true.
    enable_private_endpoint = false 
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # PRODUCTION GRADE: Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

# The Custom Node Pool
resource "google_container_node_pool" "primary_nodes" {
  name       = "my-node-pool"
  location   = var.zone
  cluster    = google_container_cluster.primary.name
  node_count = 2

  node_config {
    # COST SAVING: Spot VMs are unused Google capacity sold at up to a 91% discount.
    # They can be preempted (turned off) at any time, making them perfect for testing!
    spot         = true
    machine_type = "e2-standard-4"
    disk_size_gb = 50

    # PRODUCTION GRADE: Shielded Nodes (Hardened OS)
    shielded_instance_config {
      enable_secure_boot = true
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}
