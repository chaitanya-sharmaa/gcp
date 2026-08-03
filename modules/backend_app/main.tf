# Phase 8: Backend Application & Istio End-to-End Routing via Helm

# Reserve a static global IP for the Backend GKE Ingress
resource "google_compute_global_address" "backend_ip" {
  name = "backend-global-ip"
}

resource "helm_release" "backend_app" {
  name       = "backend-app"
  chart      = "${path.module}/chart"
  namespace  = "default"
  depends_on = [var.istio_ready]

  values = [
    yamlencode({
      projectId      = var.project_id
      secretsSaEmail = var.secrets_sa_email
      dbPassword     = var.db_password
      staticIpName   = google_compute_global_address.backend_ip.name
    })
  ]
}
