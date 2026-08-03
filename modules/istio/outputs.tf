output "istio_namespace" {
  description = "The namespace where Istio is installed"
  value       = helm_release.istio_base.namespace
}

output "tls_secret_name" {
  description = "The name of the TLS secret created for Istio Ingress"
  value       = kubernetes_secret.backend_tls.metadata[0].name
}
