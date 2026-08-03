# Enterprise GCP Architecture with Istio Ambient Mesh

This repository provisions a production-grade, zero-trust cloud infrastructure on Google Cloud Platform (GCP) using **Terraform**, **GKE (Google Kubernetes Engine)**, and **Istio Ambient Mode** (Sidecar-less Service Mesh).

---

## 🏗️ Architecture Diagram

```mermaid
graph TD
    User((Client / Browser))

    subgraph FrontendEdge ["1. Frontend Edge (Static Hosting & Cloud CDN)"]
        FLB["Frontend HTTPS Load Balancer<br/>(Global Anycast IP)"]
        CDN(("Google Cloud CDN<br/>(Edge Caching)"))
        Bucket[("Cloud Storage Bucket<br/>(Static SPA index.html)")]
    end

    subgraph BackendEdge ["2. Backend Edge (GCLB Ingress)"]
        BLB["Backend HTTPS Load Balancer<br/>(Global Static IP: 8.232.214.150)"]
    end

    subgraph VPC ["Custom VPC: learn-gcp-vpc (10.0.0.0/16)"]
        NAT("Cloud NAT Gateway: gke-nat<br/>(Secure Egress to Internet)")
        
        subgraph GKE ["GKE Private Cluster (us-central1-a • e2-standard-4 Nodes)"]
            
            subgraph KubeSystem ["kube-system Namespace (Node Daemons • system-node-critical)"]
                CNI["istio-cni DaemonSet<br/>(eBPF / iptables Traffic Capture)"]
                ZTunnel["ztunnel DaemonSet<br/>(Rust L4 Zero-Trust Proxy • Port 15008 HBONE)"]
            end

            subgraph IstioSystem ["istio-system Namespace (Control Plane & Ingress)"]
                Istiod["istiod (Ambient Profile)<br/>(CA & xDS Engine • caTrustedNodeAccounts)"]
                Gateway["istio-ingressgateway<br/>(GCLB HTTP Backend • Port 80 / 443)"]
            end

            subgraph DefaultNS ["default Namespace (dataplane-mode: ambient)"]
                Service("backend-service (ClusterIP: 80)")
                Pods["backend-api Pods (1/1 Ready)<br/>(Zero Sidecars • Pure Container)"]
            end

        end
    end

    subgraph GoogleServices ["Google Managed Services (Zero Public IPs)"]
        DB[("Cloud SQL PostgreSQL<br/>(Private IP via VPC Peering 10.0.0.0/16)")]
        SM["Google Secret Manager<br/>(DB Credentials via Workload Identity)"]
    end

    %% Flow 1: Frontend Website Loading
    User -- "1. Visit Frontend (HTTPS :443)" --> FLB
    FLB --> CDN
    CDN --> Bucket

    %% Flow 2: API Request
    User -- "2. API fetch('/api/data')" --> BLB
    BLB -- "Terminates Public TLS<br/>Forwards HTTP :80 inside VPC" --> Gateway
    Gateway -- "Routes via VirtualService & CORS" --> ZTunnel
    ZTunnel -- "Encrypted L4 mTLS (HBONE :15008)<br/>SPIFFE: spiffe://cluster.local/ns/default/sa/backend-sa" --> Pods

    %% Control Plane & Node Daemon Orchestration
    Istiod -. "xDS Config & SPIFFE CA Signer" .-> ZTunnel
    CNI -. "Intercepts Kernel Traffic" .-> ZTunnel

    %% Flow 3: Security & DB Access
    Pods -. "3. Fetch db-password (Workload Identity)" .-> SM
    Pods -. "4. Execute SQL Queries (Private IP)" .-> DB

    %% Outbound Internet
    GKE -. "Secure Outbound Access" .-> NAT

    %% Styling
    classDef edge fill:#4285F4,stroke:#fff,stroke-width:2px,color:#fff;
    classDef mesh fill:#673AB7,stroke:#fff,stroke-width:2px,color:#fff;
    classDef compute fill:#0F9D58,stroke:#fff,stroke-width:2px,color:#fff;
    classDef db fill:#EA4335,stroke:#fff,stroke-width:2px,color:#fff;
    classDef storage fill:#FBBC05,stroke:#fff,stroke-width:2px,color:#000;
    
    class FLB,BLB edge;
    class Istiod,Gateway,ZTunnel,CNI mesh;
    class Pods,Service compute;
    class DB,SM db;
    class Bucket storage;
```

---

## 🔄 Detailed Request Lifecycle (Sequence Diagram)

```mermaid
sequenceDiagram
    autonumber
    actor Client as Browser / User
    participant GCLB as Google Cloud HTTPS LB
    participant Ingress as istio-ingressgateway (istio-system)
    participant ZTunnelSrc as ztunnel (Source Node)
    participant ZTunnelDst as ztunnel (Destination Node)
    participant Backend as backend-api Pod (default)
    participant SM as Secret Manager
    participant DB as Cloud SQL (PostgreSQL)

    %% Flow: Edge to Mesh
    Client->>GCLB: HTTPS GET /api/data (Port 443)
    Note over GCLB: Terminates Public TLS using SSL Certificate
    GCLB->>Ingress: HTTP GET /api/data (Port 80 via VPC)
    
    %% Flow: Ambient Mesh L4 mTLS
    Note over Ingress: Evaluates Gateway & VirtualService CORS Policy
    Ingress->>ZTunnelSrc: Outbound Traffic Intercepted (istio-cni)
    Note over ZTunnelSrc: Wraps in HBONE Tunnel (Port 15008)<br/>Authenticates SPIFFE SAN Identity
    ZTunnelSrc->>ZTunnelDst: mTLS Handshake over HBONE (:15008)
    Note over ZTunnelDst: Decrypts & Verifies Client Identity
    ZTunnelDst->>Backend: Plain HTTP to localhost (Port 80)

    %% Flow: Workload Identity & Database
    Note over Backend: Pod startup initializes DB connection
    Backend->>SM: Authenticate via Workload Identity & Read db-password
    SM-->>Backend: Secure DB Password
    Backend->>DB: Query over Private IP (VPC Peering)
    DB-->>Backend: Query Results

    %% Return
    Backend-->>ZTunnelDst: HTTP 200 OK + JSON
    ZTunnelDst-->>ZTunnelSrc: Encrypted Response
    ZTunnelSrc-->>Ingress: Decrypted Response
    Ingress-->>GCLB: HTTP 200 + CORS Headers
    GCLB-->>Client: HTTPS 200 OK (Data Rendered on Frontend)
```

---

## 🌟 Key Architectural Highlights

### 1. Istio Ambient Mode (Sidecar-less Service Mesh)
* **Zero Pod Restarts & Bloat:** No `istio-proxy` Envoy sidecar containers injected into application pods (`1/1 Ready`).
* **Node-Level `ztunnel` in `kube-system`:** Deployed with `system-node-critical` priority class to guarantee scheduling on all worker nodes.
* **Kernel Traffic Interception:** `istio-cni` transparently routes pod traffic to `ztunnel` using Linux kernel routing (`eBPF`/`iptables`).
* **Authenticated Node Proxying:** Configured `istiod` with `caTrustedNodeAccounts = ["kube-system/ztunnel", "istio-system/ztunnel"]` for secure SPIFFE identity certificate generation.

### 2. Edge-to-Mesh TLS Termination Pattern
* **Public Internet ➔ GCLB:** Encrypted via **HTTPS (Port 443)** using SSL certificates.
* **GCLB ➔ Ingress Gateway:** High-performance **HTTP (Port 80)** across Google's private, encrypted internal VPC backbone, eliminating redundant double-encryption overhead.
* **Ingress Gateway ➔ Workload Pods:** Fully zero-trust encrypted with **mutual TLS (mTLS)** over **HBONE (Port 15008)** with cryptographic SPIFFE identities (`spiffe://cluster.local/ns/default/sa/backend-sa`).

### 3. Enterprise Security & Zero-Trust
* **Workload Identity Federation:** No static service account keys in pods. Kubernetes Service Accounts bind directly to GCP IAM roles.
* **GCP Secret Manager:** Database passwords dynamically fetched at runtime.
* **Private Network Isolation:** GKE cluster and Cloud SQL instances have 0 public IPs; communication traverses internal VPC peering and Cloud NAT handles outbound internet egress.
* **CORS Support:** Native cross-origin resource sharing (`corsPolicy`) configured on Istio `VirtualService` to seamlessly connect the Cloud CDN frontend with the backend API.

---

## 📁 Repository Structure

```text
├── environments/
│   └── dev/                       # Root Terraform environment
│       ├── main.tf                # Module orchestration & outputs
│       ├── variables.tf           # Environment variables
│       └── provider.tf            # Google, Helm, Kubernetes, and TLS providers
├── modules/
│   ├── network/                   # VPC, Subnets, Firewalls (GCLB & GKE), Cloud NAT
│   ├── database/                  # Cloud SQL PostgreSQL & Private VPC Connection
│   ├── gke/                       # GKE Private Cluster & Node Pools
│   ├── secrets/                   # Secret Manager & Workload Identity IAM
│   ├── frontend/                  # Cloud Storage, Cloud CDN, HTTPS Load Balancer
│   ├── istio/                     # Istio Base, CNI, istiod (Ambient), ztunnel, and Gateway
│   └── backend_app/               # Helm Chart for Backend Deployment, Service, Ingress, VS
```

---

## 🛠️ Verification & Testing

### 1. Verify Istio Ambient Components
```bash
# Check ztunnel and istio-cni daemons
kubectl get daemonsets,pods -n kube-system -l app=ztunnel
kubectl get daemonsets,pods -n kube-system -l app=istio-cni

# Check istiod control plane
kubectl get pods -n istio-system -l app=istiod
```

### 2. Verify Backend Pods (Sidecar-less)
```bash
# Confirm pods are 1/1 (Zero Sidecars)
kubectl get pods -n default -l app=backend-api
```

### 3. Verify Load Balancer Health & Ingress
```bash
kubectl describe ingress backend-ingress -n istio-system | grep backends
# Output: {"k8s1-...-istio-ingressgateway-80-...": "HEALTHY"}
```

### 4. Test Public Endpoints
```bash
# Test Backend API via GCLB + Ambient Mesh
curl -k -i https://<BACKEND_STATIC_IP>/api/data

# Test Frontend Website via Cloud CDN
curl -k -i https://<FRONTEND_STATIC_IP>
```

---

## 🧹 Teardown

To destroy all cloud resources when finished testing:

```bash
cd environments/dev
terraform destroy -auto-approve
```
