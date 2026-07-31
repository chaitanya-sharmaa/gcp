# Phase 4: The Database (Cloud SQL)

# 1. Private Services Access Allocation
# Google hosts Cloud SQL in their own VPC. We must allocate a small chunk of our 
# internal IP addresses and peer it with Google so our GKE cluster can talk to the DB.
resource "google_compute_global_address" "private_ip_alloc" {
  name          = "private-ip-alloc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 24
  network       = var.vpc_id
}

# Establish the VPC peering connection
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = var.vpc_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
}

# 2. Cloud SQL Instance (PostgreSQL)
resource "google_sql_database_instance" "main" {
  name             = "my-postgres-db"
  database_version = "POSTGRES_15"
  region           = var.region
  deletion_protection = false
  
  # We must wait for the peering connection to finish before creating the DB!
  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    # COST SAVING: 'db-f1-micro' is the cheapest tier. Perfect for our testing budget!
    tier = "db-f1-micro"
    
    ip_configuration {
      # PRODUCTION GRADE: We completely disable the public internet IP.
      ipv4_enabled    = false 
      private_network = var.vpc_id
    }
  }
}

# 3. Create a default database inside the instance
resource "google_sql_database" "database" {
  name     = "webapp_db"
  instance = google_sql_database_instance.main.name
}

# 4. Create an admin user
resource "google_sql_user" "users" {
  name     = "dbadmin"
  instance = google_sql_database_instance.main.name
  password = var.db_password
}
