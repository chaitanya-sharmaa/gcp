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
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Enterprise GCP Infrastructure - Live Demo</title>
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; text-align: center; margin-top: 40px; background: #0f172a; color: #f8fafc; }
      .container { max-width: 700px; margin: 0 auto; padding: 24px; }
      .card { background: #1e293b; border-radius: 12px; padding: 24px; box-shadow: 0 10px 25px rgba(0,0,0,0.3); border: 1px solid #334155; margin-top: 20px; }
      .badge { display: inline-block; padding: 4px 12px; border-radius: 9999px; font-size: 12px; font-weight: 600; background: #3b82f6; color: white; margin-bottom: 12px; }
      pre { background: #090d16; padding: 16px; border-radius: 8px; text-align: left; overflow-x: auto; color: #38bdf8; font-size: 13px; line-height: 1.5; border: 1px solid #1e293b; }
      .btn { display: inline-block; background: #3b82f6; color: white; padding: 10px 20px; border-radius: 8px; text-decoration: none; font-weight: 600; border: none; cursor: pointer; transition: background 0.2s; margin-top: 10px; }
      .btn:hover { background: #2563eb; }
      .warning-box { background: #451a03; border: 1px solid #b45309; color: #fef3c7; border-radius: 8px; padding: 16px; margin-top: 16px; font-size: 14px; text-align: left; }
    </style>
  </head>
  <body>
    <div class="container">
      <span class="badge">Google Cloud CDN • GKE • Istio Ambient Mesh</span>
      <h1>🚀 Cloud Infrastructure Live Demo</h1>
      <p style="color: #94a3b8;">Served globally via Cloud CDN with Zero-Trust mTLS backend.</p>

      <div class="card">
        <h3>Live Backend Payload (GKE + Cloud SQL + Secret Manager)</h3>
        <p id="status-text" style="color: #cbd5e1;">Connecting to Backend API...</p>
        
        <div id="cert-warning" class="warning-box" style="display: none;">
          <strong>⚠️ Browser Security Notice (Self-Signed SSL):</strong>
          <p style="margin: 8px 0;">Because this environment uses a testing self-signed SSL certificate, your browser will block background requests until you accept the certificate for the backend IP.</p>
          <a id="cert-link" href="#" target="_blank" class="btn">1. Click Here to Accept Backend Certificate ➔</a>
          <p style="font-size: 12px; margin-top: 8px; color: #fde68a;">Click "Advanced" ➔ "Proceed to unsafe". Then return here and click Retry.</p>
          <button class="btn" style="background: #10b981;" onclick="fetchData()">2. 🔄 Retry Fetch</button>
        </div>

        <pre id="result" style="display: none;"></pre>
      </div>
    </div>

    <script>
      const apiUrl = "${var.backend_url}/api/data";
      document.getElementById('cert-link').href = apiUrl;

      function fetchData() {
        const statusText = document.getElementById('status-text');
        const certWarning = document.getElementById('cert-warning');
        const result = document.getElementById('result');

        statusText.style.display = 'block';
        statusText.innerText = "Fetching live data from: " + apiUrl;
        certWarning.style.display = 'none';

        fetch(apiUrl)
          .then(res => {
            if (!res.ok) throw new Error('HTTP ' + res.status);
            return res.json();
          })
          .then(data => {
            statusText.style.display = 'none';
            certWarning.style.display = 'none';
            result.style.display = 'block';
            result.innerText = JSON.stringify(data, null, 2);
          })
          .catch(err => {
            statusText.innerText = "❌ Connection blocked by browser SSL/CORS policy.";
            certWarning.style.display = 'block';
          });
      }

      // Initial fetch on page load
      fetchData();
    </script>
  </body>
</html>
EOF
  content_type = "text/html"
}

# 2. Cloud CDN & Global Load Balancer Setup
# A backend bucket tells the Load Balancer to fetch content from Cloud Storage
resource "google_compute_backend_bucket" "cdn_backend" {
  name                 = "frontend-cdn-backend"
  bucket_name          = google_storage_bucket.static_site.name
  enable_cdn           = true # PRODUCTION GRADE: Turns on global caching!
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
