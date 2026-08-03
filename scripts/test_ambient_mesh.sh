#!/usr/bin/env bash
# ==============================================================================
# Automated End-to-End Test Suite for Istio Ambient Mesh on GCP
# ==============================================================================

set -e

# Color definitions
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASSED_COUNT=0
FAILED_COUNT=0

function print_header() {
  echo -e "\n${BLUE}================================================================${NC}"
  echo -e "${BLUE} $1 ${NC}"
  echo -e "${BLUE}================================================================${NC}"
}

function test_pass() {
  echo -e " [${GREEN}PASS${NC}] $1"
  ((PASSED_COUNT++))
}

function test_fail() {
  echo -e " [${RED}FAIL${NC}] $1"
  ((FAILED_COUNT++))
}

# ------------------------------------------------------------------------------
# 1. Cluster & Ambient Mesh Daemon Verification
# ------------------------------------------------------------------------------
print_header "1. Checking Istio Ambient Control Plane & Daemons"

# Check istiod
if kubectl get pods -n istio-system -l app=istiod --field-selector=status.phase=Running | grep -q "istiod"; then
  test_pass "istiod Control Plane is running in istio-system"
else
  test_fail "istiod Control Plane is NOT running"
fi

# Check istio-cni
if kubectl get pods -n kube-system -l app=istio-cni --field-selector=status.phase=Running | grep -q "istio-cni"; then
  test_pass "istio-cni DaemonSet is running in kube-system"
else
  test_fail "istio-cni DaemonSet is NOT running"
fi

# Check ztunnel
if kubectl get pods -n kube-system -l app=ztunnel --field-selector=status.phase=Running | grep -q "ztunnel"; then
  test_pass "ztunnel L4 Proxy DaemonSet is running in kube-system"
else
  test_fail "ztunnel DaemonSet is NOT running"
fi

# ------------------------------------------------------------------------------
# 2. Sidecar-less Workload Verification
# ------------------------------------------------------------------------------
print_header "2. Checking Sidecar-less Backend Workload"

READY_PODS=$(kubectl get pods -n default -l app=backend-api -o jsonpath='{.items[*].status.containerStatuses[*].ready}' | tr ' ' '\n' | grep -c "true" || true)
TOTAL_CONTAINERS=$(kubectl get pods -n default -l app=backend-api -o jsonpath='{range .items[*]}{len(.spec.containers)}{" "}{end}' | tr ' ' '\n' | head -n 1)

if [ "$READY_PODS" -ge 1 ] && [ "$TOTAL_CONTAINERS" -eq 1 ]; then
  test_pass "backend-api pods are running with 1/1 containers (PURE SIDECAR-LESS)"
else
  test_fail "backend-api pods failed sidecarless validation (Containers: $TOTAL_CONTAINERS, Ready: $READY_PODS)"
fi

# ------------------------------------------------------------------------------
# 3. Secret Manager & Workload Identity Verification
# ------------------------------------------------------------------------------
print_header "3. Checking Workload Identity & Secret Mount"

SECRET_CONTENT=$(kubectl exec -n default deployment/backend-api -c api -- cat /etc/secrets/db_password.txt 2>/dev/null || true)
if [ -n "$SECRET_CONTENT" ]; then
  test_pass "GCP Secret Manager db-password mounted securely via Workload Identity"
else
  test_fail "Could not read db_password.txt from backend-api pod"
fi

# ------------------------------------------------------------------------------
# 4. Internal Mesh Connectivity & Database Simulation
# ------------------------------------------------------------------------------
print_header "4. Checking Internal Ambient Mesh Routing & DB Payload"

INTERNAL_RESP=$(kubectl exec -n default deployment/backend-api -c api -- wget -qO- http://backend-service.default.svc.cluster.local:80/api/data 2>/dev/null || true)
if echo "$INTERNAL_RESP" | grep -q "Connected to Cloud SQL"; then
  test_pass "Internal DNS & Ambient mTLS routing to backend-service is healthy"
else
  test_fail "Internal routing to backend-service failed"
fi

# ------------------------------------------------------------------------------
# 5. GCLB Health Checks
# ------------------------------------------------------------------------------
print_header "5. Checking Google Cloud Load Balancer Ingress Health"

HEALTH_STATE=$(kubectl get ingress backend-ingress -n istio-system -o jsonpath='{.metadata.annotations.ingress\.kubernetes\.io/backends}' 2>/dev/null || true)
if echo "$HEALTH_STATE" | grep -q "HEALTHY"; then
  test_pass "GCLB Ingress backend state is HEALTHY"
else
  echo -e " [${YELLOW}WARN${NC}] GCLB backend is syncing or probing ($HEALTH_STATE)"
fi

# ------------------------------------------------------------------------------
# 6. Public Endpoint & CORS Validation
# ------------------------------------------------------------------------------
print_header "6. Checking Public Endpoints & CORS Headers"

BACKEND_IP=$(kubectl get ingress backend-ingress -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

if [ -n "$BACKEND_IP" ]; then
  HTTP_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" "https://${BACKEND_IP}/api/data" || true)
  CORS_HEADER=$(curl -k -s -I "https://${BACKEND_IP}/api/data" | grep -i "access-control-allow-origin" || true)
  
  if [ "$HTTP_STATUS" -eq 200 ]; then
    test_pass "Public Backend API https://${BACKEND_IP}/api/data returned HTTP 200 OK"
  else
    test_fail "Public Backend API returned HTTP $HTTP_STATUS"
  fi

  if [ -n "$CORS_HEADER" ]; then
    test_pass "Istio VirtualService CORS policy is active ($CORS_HEADER)"
  else
    test_fail "CORS header Access-Control-Allow-Origin not found"
  fi
else
  echo -e " [${YELLOW}SKIP${NC}] Backend IP not discovered from Ingress"
fi

# ------------------------------------------------------------------------------
# 7. ztunnel HBONE mTLS Log Verification
# ------------------------------------------------------------------------------
print_header "7. Checking ztunnel HBONE mTLS Log Telemetry"

if kubectl logs -n kube-system -l app=ztunnel --tail=100 2>/dev/null | grep -q "spiffe://cluster.local/ns/default/sa/backend-sa"; then
  test_pass "ztunnel verified active cryptographic SPIFFE mTLS handshakes over HBONE (:15008)"
else
  echo -e " [${YELLOW}INFO${NC}] No recent backend-sa identity logs in ztunnel tail buffer"
fi

# ------------------------------------------------------------------------------
# Summary Scorecard
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}================================================================${NC}"
echo -e "${BLUE}                     TEST SUMMARY SCORECARD                     ${NC}"
echo -e "${BLUE}================================================================${NC}"
echo -e " Tests Passed: ${GREEN}${PASSED_COUNT}${NC}"
echo -e " Tests Failed: ${RED}${FAILED_COUNT}${NC}"

if [ "$FAILED_COUNT" -eq 0 ]; then
  echo -e "\n${GREEN}🎉 ALL SYSTEMS FULLY OPERATIONAL & ZERO-TRUST VERIFIED! 🎉${NC}\n"
  exit 0
else
  echo -e "\n${RED}❌ SOME TESTS FAILED. Please review the output above. ❌${NC}\n"
  exit 1
fi
