# 1. Edge Security Policy for Frontend Bucket
resource "google_compute_security_policy" "frontend_edge" {
  name        = "frontend-edge-policy"
  description = "Cloud Armor Edge policy for Frontend Bucket"
  type        = "CLOUD_ARMOR_EDGE"

  rule {
    action   = "deny(403)"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["9.9.9.9/32"] # Example malicious IP to block
      }
    }
    description = "Block known malicious IP"
  }

  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }
}

# 2. Standard Security Policy for GKE Backend
resource "google_compute_security_policy" "backend_standard" {
  name        = "backend-standard-policy"
  description = "Cloud Armor Standard policy for GKE Backend API"

  rule {
    action   = "deny(403)"
    priority = "1000"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-v33-stable') || evaluatePreconfiguredExpr('xss-v33-stable')"
      }
    }
    description = "Block SQLi and XSS"
  }

  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }
}
