# Enterprise GCP Architecture with Istio Ambient Mesh

This repository provisions a production-grade, zero-trust cloud infrastructure on Google Cloud Platform (GCP) using **Terraform**, **GKE (Google Kubernetes Engine)**, and **Istio Ambient Mode** (Sidecar-less Service Mesh).

---

## 🏗️ Architecture Diagram

```mermaid
graph TD
    User((Client / Browser))

    subgraph FrontendEdge ["1. Frontend Edge (Static Hosting & Cloud CDN)"]
        FLB["Frontend HTTPS Load Balancer<br/>(Global Anycast IP: 136.68.46.79)"]
        CDN(("Google Cloud CDN<br/>(Edge Caching)"))
        Bucket[("Cloud Storage Bucket<br/>(SPA index.html with SSL Helper)")]
    end

    subgraph BackendEdge ["2. Backend Edge (GCLB Ingress)"]
        BLB["Backend HTTPS Load Balancer<br/>(Global Static IP: 34.102.230.191)"]
    end

    subgraph VPC ["Custom VPC: learn-gcp-vpc (10.0.0.0/16)"]
        NAT("Cloud NAT Gateway: gke-nat<br/>(Secure Egress to Internet)")
        
        subgraph GKE ["GKE Private Cluster (us-central1-a • e2-standard-4 Nodes)"]
            
            subgraph KubeSystem ["kube-system Namespace (Node Daemons • system-node-critical)"]
                CNI["istio-cni DaemonSet<br/>(Kernel Traffic Redirection)"]
                ZTunnel["ztunnel DaemonSet<br/>(Rust L4 Zero-Trust Proxy • Port 15008 HBONE)"]
            end

            subgraph IstioSystem ["istio-system Namespace (Control Plane & Ingress)"]
                Istiod["istiod (Ambient Profile)<br/>(CA & xDS Engine • caTrustedNodeAccounts)"]
                Gateway["istio-ingressgateway<br/>(GCLB HTTP Backend • Port 80 / 443)"]
            end

            subgraph DefaultNS ["default Namespace (dataplane-mode: ambient)"]
                AuthPolicy["AuthorizationPolicy<br/>(Ingress-Only Principle of Least Privilege)"]
                PeerAuth["PeerAuthentication<br/>(Strict L4 mTLS Mode)"]
                Service("backend-service (ClusterIP: 80)")
                Pods["backend-api Pods (1/1 Ready)<br/>(Zero Sidecars • Pure Single Container)"]
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

    %% Zero Trust Enforcements
    AuthPolicy -. "Enforces Source Identity" .-> Pods
    PeerAuth -. "Rejects Plaintext Traffic" .-> Pods

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
    class Istiod,Gateway,ZTunnel,CNI,AuthPolicy,PeerAuth mesh;
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
    participant GCLB as Google Cloud HTTPS LB (34.102.230.191)
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
    Note over ZTunnelDst: Decrypts & Verifies Client Identity<br/>Evaluates AuthorizationPolicy & PeerAuth
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
* **Zero Pod Restarts & Bloat:** No `istio-proxy` Envoy sidecar containers injected into application pods (`1/1 Ready`), saving up to 90% in cluster memory.
* **Node-Level `ztunnel` in `kube-system`:** Deployed with `system-node-critical` priority class to guarantee scheduling on all worker nodes.
* **Kernel Traffic Interception:** `istio-cni` transparently routes pod traffic to `ztunnel` using Linux kernel routing (`eBPF`/`iptables`).
* **Authenticated Node Proxying:** Configured `istiod` with `caTrustedNodeAccounts = ["kube-system/ztunnel"]` for secure SPIFFE identity certificate generation.

### 2. Edge-to-Mesh TLS Termination Pattern
* **Public Internet ➔ GCLB:** Encrypted via **HTTPS (Port 443)** using SSL certificates.
* **GCLB ➔ Ingress Gateway:** High-performance **HTTP (Port 80)** across Google's private, encrypted internal VPC backbone, eliminating redundant double-encryption overhead.
* **Ingress Gateway ➔ Workload Pods:** Fully zero-trust encrypted with **mutual TLS (mTLS)** over **HBONE (Port 15008)** with cryptographic SPIFFE identities (`spiffe://cluster.local/ns/default/sa/backend-sa`).

### 3. Zero-Trust Security Policies
* **Strict `PeerAuthentication`:** Namespace-wide enforcement rejecting all non-mTLS plaintext connections.
* **Least-Privilege `AuthorizationPolicy`:** Workload pods only accept traffic verified to originate from `istio-ingressgateway`, actively blocking lateral east-west attacks.
* **Workload Identity Federation:** No static service account keys in pods. Kubernetes Service Account `backend-sa` binds directly to GCP IAM role `roles/secretmanager.secretAccessor`.
* **GCP Secret Manager:** Database passwords dynamically fetched at pod startup into `/etc/secrets/db_password.txt`.
* **Private Network Isolation:** GKE cluster and Cloud SQL instances have 0 public IPs; communication traverses internal VPC peering.

### 4. Cross-Origin Resource Sharing (CORS) & Cloud CDN
* **Preflight & Direct CORS Support:** Both the Istio `VirtualService` and backend Nginx configuration handle `OPTIONS`, `GET`, `POST` with `Access-Control-Allow-Origin: *`.
* **Frontend SSL Helper:** Interactive SPA featuring a 1-click certificate trust mechanism for testing self-signed certificates with zero friction.

---

## 📁 Repository Structure

```text
├── environments/
│   └── dev/                       # Root Terraform environment
│       ├── main.tf                # Module orchestration & outputs
│       ├── variables.tf           # Environment variables
│       └── provider.tf            # Google, Helm, Kubernetes, and TLS providers
├── modules/
│   ├── network/                   # VPC, Subnets, Firewalls (GCLB & GKE), Cloud NAT, Cloud Armor
│   ├── database/                  # Cloud SQL PostgreSQL & Private VPC Connection
│   ├── gke/                       # GKE Private Cluster & Node Pools
│   ├── secrets/                   # Secret Manager & Workload Identity IAM
│   ├── frontend/                  # Cloud Storage, Cloud CDN, HTTPS Load Balancer
│   ├── istio/                     # Istio Base, CNI, istiod (Ambient), ztunnel, and Gateway
│   └── backend_app/               # Helm Chart for Backend Deployment, Service, Ingress, VS, AuthPolicy
├── scripts/
│   └── test_ambient_mesh.sh       # Automated 7-Step End-to-End Test Suite & Scorecard
└── docs/
    └── IMPROVEMENTS.md            # In-depth security hardening & architectural guide
```

---

## 🧪 Automated Testing & Verification

Run the full end-to-end test suite anytime:

```bash
bash scripts/test_ambient_mesh.sh
```

### Automated Checks Performed:
1. **Control Plane & Daemons:** Checks `istiod`, `istio-cni`, and `ztunnel` across namespaces.
2. **Sidecar-less Status:** Verifies pods run in single-container mode (`1/1 Ready`).
3. **Secret Manager & Workload Identity:** Confirms `db-password` is mounted at `/etc/secrets/db_password.txt`.
4. **Internal Mesh Routing & Authorization:** Validates routing from authorized Ingress and verifies `AuthorizationPolicy` blocks lateral pod queries.
5. **GCLB Health Checks:** Asserts load balancer backend reports `HEALTHY`.
6. **Public API & CORS:** Verifies `HTTP 200 OK` on `https://34.102.230.191/api/data` with `Access-Control-Allow-Origin: *`.
7. **mTLS Handshake Telemetry:** Validates `ztunnel` HBONE Port 15008 SPIFFE connection logs.

---

## 🧹 Teardown

To cleanly destroy all cloud resources when finished testing:

```bash
cd environments/dev
terraform destroy -auto-approve
```
