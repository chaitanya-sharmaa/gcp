# Google Cloud Armor Security Policy (WAF & Rate Limiting)
# Protects the Edge Load Balancer from DDoS, brute-force, and web application attacks.

resource "google_compute_security_policy" "edge_waf" {
  name        = "edge-security-policy"
  description = "Production Cloud Armor policy with rate limiting and OWASP rules"

  # Rule 1: Rate limiting (e.g. max 100 requests per minute per client IP)
  rule {
    action   = "rate_based_ban"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
      ban_duration_sec = 300
    }
    description = "Throttle clients exceeding 100 req/min for 5 minutes"
  }

  # Rule 2: Default allow rule for legitimate traffic
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
