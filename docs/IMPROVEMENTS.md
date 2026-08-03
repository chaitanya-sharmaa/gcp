# Production Hardening & Architectural Improvements

This branch (`feature/production-hardening-and-improvements`) introduces enterprise security, zero-trust policies, WAF protection, and an automated end-to-end testing suite.

---

## 🛡️ 1. Zero-Trust Security Policies

### A. Strict PeerAuthentication (`STRICT` mTLS)
* **File:** `modules/backend_app/chart/templates/authorizationpolicy.yaml`
* **Purpose:** Forces **strict mutual TLS** across all workloads in the `default` namespace. Any plaintext unauthenticated TCP connection will be immediately dropped at the `ztunnel` layer.

### B. Istio `AuthorizationPolicy` (Ingress-Only Principle of Least Privilege)
* **File:** `modules/backend_app/chart/templates/authorizationpolicy.yaml`
* **Purpose:** Rejects all lateral traffic from any unauthorized pod/namespace inside the cluster. Only traffic carrying the cryptographic identity `spiffe://cluster.local/ns/istio-system/sa/istio-ingressgateway-service-account` is permitted to communicate with `backend-api`.

---

## 🌐 2. Google Cloud Armor WAF & Rate Limiting

* **File:** `modules/network/armor.tf`
* **Features:**
  * **Layer 7 DDoS & Brute-Force Mitigation:** Throttles abusive clients exceeding 100 requests/minute per IP address.
  * **Banning:** Automatically issues HTTP 429 and bans offending IPs for 5 minutes (300 seconds).

---

## 🧪 3. Automated End-to-End Test Suite

* **File:** `scripts/test_ambient_mesh.sh`
* **Usage:**
  ```bash
  ./scripts/test_ambient_mesh.sh
  ```
* **Verifications Performed:**
  1. Istio Control Plane (`istiod`) and Node Daemons (`ztunnel`, `istio-cni`).
  2. Sidecar-less Workload Validation (`1/1 Ready` pure container pods).
  3. Google Secret Manager mount via Workload Identity.
  4. Internal Ambient Mesh DNS and mTLS payload query.
  5. Google Cloud Load Balancer Ingress `HEALTHY` state.
  6. Public HTTPS API endpoint response code (`HTTP 200`) and CORS header validation.
  7. `ztunnel` HBONE Port 15008 SPIFFE cryptographic log verification.
  8. Colored summary scorecard.
