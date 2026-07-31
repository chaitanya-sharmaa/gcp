# Phase 5: The Static Frontend (Cloud Storage & CDN)

# 1. The Cloud Storage Bucket
# Bucket names must be globally unique across all of Google Cloud, so we add a random suffix.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "static_site" {
  name          = "my-static-frontend-${random_id.bucket_suffix.hex}"
  location      = "US" # Multi-region is best for a CDN origin
  force_destroy = true # This ensures `terraform destroy` works even if files are in it (great for testing)

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
  
  uniform_bucket_level_access = true
}

# Make the bucket publicly readable so the CDN can serve the files to users
resource "google_storage_bucket_iam_member" "public_rule" {
  bucket = google_storage_bucket.static_site.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Upload a dummy index.html file so we have something to look at!
resource "google_storage_bucket_object" "index_page" {
  name         = "index.html"
  bucket       = google_storage_bucket.static_site.name
  content      = <<EOF
<html>
  <head>
    <style>
      body { font-family: sans-serif; text-align: center; margin-top: 50px; }
      #data { margin-top: 20px; padding: 20px; background: #f0f0f0; border-radius: 8px; display: inline-block; }
    </style>
  </head>
  <body>
    <h1>🚀 Hello from your Static Frontend!</h1>
    <p>Served blazing fast via Google Cloud CDN.</p>
    
    <div id="data">
      <h3>Data from Backend (GKE):</h3>
      <p id="loading">Fetching data from backend...</p>
      <pre id="result" style="text-align: left;"></pre>
    </div>

    <script>
      // The Backend URL is injected by Terraform!
      const apiUrl = "${var.backend_url}/api/data";
      
      fetch(apiUrl)
        .then(response => response.json())
        .then(data => {
          document.getElementById('loading').style.display = 'none';
          document.getElementById('result').innerText = JSON.stringify(data, null, 2);
        })
        .catch(error => {
          document.getElementById('loading').innerText = "Backend API is not yet reachable. Error: " + error;
        });
    </script>
  </body>
</html>
EOF
  content_type = "text/html"
}

# 2. Cloud CDN & Global Load Balancer Setup
# A backend bucket tells the Load Balancer to fetch content from Cloud Storage
resource "google_compute_backend_bucket" "cdn_backend" {
  name        = "frontend-cdn-backend"
  bucket_name = google_storage_bucket.static_site.name
  enable_cdn  = true # PRODUCTION GRADE: Turns on global caching!
}

# URL Map routes incoming HTTP requests to our backend bucket
resource "google_compute_url_map" "default" {
  name            = "frontend-url-map"
  default_service = google_compute_backend_bucket.cdn_backend.id
}

# Upload our Self-Signed SSL Certificate to Google Cloud
resource "google_compute_ssl_certificate" "default" {
  name        = "frontend-ssl-cert"
  private_key = var.ssl_private_key_pem
  certificate = var.ssl_cert_pem
}

# The HTTPS Proxy sits between the forwarding rule and the URL map
resource "google_compute_target_https_proxy" "default" {
  name             = "frontend-https-proxy"
  url_map          = google_compute_url_map.default.id
  ssl_certificates = [google_compute_ssl_certificate.default.id]
}

# The Forwarding Rule is the actual IP address that listens for traffic on Port 443 (HTTPS)
resource "google_compute_global_forwarding_rule" "default" {
  name                  = "frontend-forwarding-rule"
  target                = google_compute_target_https_proxy.default.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL"
}
