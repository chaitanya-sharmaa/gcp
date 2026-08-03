# Note: Cloud Armor Security Policy is disabled by default because sandbox/trial GCP projects
# have a quota limit of 0.0 for SECURITY_POLICY_RULES.
# In a paid production project with quota, enable the resource below:
#
# resource "google_compute_security_policy" "edge_waf" {
#   name        = "edge-security-policy"
#   description = "Production Cloud Armor policy with rate limiting and OWASP rules"
#   ...
# }
