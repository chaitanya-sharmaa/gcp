# Phase 5: Istio Ambient Mode (Sidecar-less Service Mesh) on GKE

# 1. Istio Base (CRDs and Cluster Roles)
resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  namespace        = "istio-system"
  create_namespace = true
}

# 2. Istio CNI Plugin (Redirects node traffic to ztunnel)
resource "helm_release" "istio_cni" {
  name            = "istio-cni"
  repository      = "https://istio-release.storage.googleapis.com/charts"
  chart           = "cni"
  namespace       = "kube-system"
  replace         = true
  cleanup_on_fail = true
  depends_on      = [helm_release.istio_base]

  values = [
    yamlencode({
      profile     = "ambient"
      cniBinDir   = "/home/kubernetes/bin"
      cniConfDir  = "/etc/cni/net.d"
      privileged  = true
      ambient = {
        enabled    = true
        dnsCapture = true
      }
      resources = {
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }
    })
  ]
}

# 3. Istio Control Plane (istiod with Ambient profile)
resource "helm_release" "istiod" {
  name            = "istiod"
  repository      = "https://istio-release.storage.googleapis.com/charts"
  chart           = "istiod"
  namespace       = "istio-system"
  replace         = true
  cleanup_on_fail = true
  depends_on      = [helm_release.istio_base]

  values = [
    yamlencode({
      profile = "ambient"
      meshConfig = {
        caTrustedNodeAccounts = [
          "istio-system/ztunnel",
          "kube-system/ztunnel"
        ]
      }
      pilot = {
        env = {
          CA_TRUSTED_NODE_ACCOUNTS = "istio-system/ztunnel,kube-system/ztunnel,istio-system/istio-cni,kube-system/istio-cni"
        }
      }
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "1024Mi"
        }
      }
    })
  ]

}

# 4. Istio ztunnel (Node-level Rust proxy DaemonSet for L4 mTLS)
resource "helm_release" "ztunnel" {
  name            = "ztunnel"
  repository      = "https://istio-release.storage.googleapis.com/charts"
  chart           = "ztunnel"
  namespace       = "kube-system"
  replace         = true
  cleanup_on_fail = true
  depends_on      = [helm_release.istiod, helm_release.istio_cni]

  values = [
    yamlencode({
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }
    })
  ]
}

# 5. Istio Ingress Gateway (Configured for GCLB integration)
resource "helm_release" "istio_ingress" {
  name            = "istio-ingressgateway"
  repository      = "https://istio-release.storage.googleapis.com/charts"
  chart           = "gateway"
  namespace       = "istio-system"
  replace         = true
  cleanup_on_fail = true
  depends_on      = [helm_release.istiod]

  values = [
    yamlencode({
      service = {
        type = "NodePort"
        annotations = {
          "cloud.google.com/appprotocols" = "{\"https\":\"HTTPS\"}"
        }
      }
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }
    })
  ]
}

# 6. Backend TLS Secret inside istio-system and default namespaces for GCLB & Gateway HTTPS
resource "kubernetes_secret" "backend_tls" {
  metadata {
    name      = "backend-tls"
    namespace = "istio-system"
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = var.ssl_cert_pem
    "tls.key" = var.ssl_private_key_pem
  }

  depends_on = [helm_release.istio_base]
}

resource "kubernetes_secret" "backend_tls_default" {
  metadata {
    name      = "backend-tls"
    namespace = "default"
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = var.ssl_cert_pem
    "tls.key" = var.ssl_private_key_pem
  }

  depends_on = [helm_release.istio_base]
}

