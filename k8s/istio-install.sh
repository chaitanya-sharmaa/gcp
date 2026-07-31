#!/bin/bash
set -e

echo "Downloading and installing Istio (if not already installed)..."
# You should have istioctl installed in your PATH. If not, download it first:
# curl -L https://istio.io/downloadIstio | sh -

echo "Applying Istio profile with GKE Ingress (GCLB) configuration..."

# We install Istio and configure the default istio-ingressgateway:
# 1. Type NodePort: We don't want a generic L4 Load Balancer. We want GCLB to route to it.
# 2. Annotate with appprotocols to force GCLB to speak HTTPS to Istio.
# 3. Annotate with backend-config to attach the Cloud Armor WAF.

istioctl install -y --set profile=default \
  --set components.ingressGateways[0].k8s.service.type=NodePort \
  --set components.ingressGateways[0].k8s.serviceAnnotations."cloud\.google\.com/appprotocols"='{"https":"HTTPS"}' \
  --set components.ingressGateways[0].k8s.serviceAnnotations."cloud\.google\.com/backend-config"='{"default":"backend-waf-config"}'

echo "Istio successfully installed and configured for End-to-End Encryption with Cloud Armor!"
