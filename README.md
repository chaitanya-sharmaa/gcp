# Enterprise GCP Architecture with Istio Ambient Mesh

This repository provisions an end-to-end, enterprise-grade cloud architecture on Google Cloud Platform (GCP) using **Terraform**, **Kubernetes (GKE)**, and **Istio Ambient Mode** (Sidecar-less Service Mesh).

---

## 🏗️ Architecture Diagram

```mermaid
graph TD
    User((User Browser))

    subgraph FrontendEdge ["Frontend Edge (CDN & Static Hosting)"]
        WAF1{{"Cloud Armor Edge Policy"}}
        FLB["Frontend HTTPS Load Balancer<br/>Global Anycast IP"]
        CDN(("Cloud CDN (Edge Cache)"))
        Bucket[("Cloud Storage Bucket<br/>Static Frontend Website")]
    end

    subgraph BackendEdge ["Backend Edge (GCLB & Ingress)"]
        WAF2{{"Cloud Armor Security Policy"}}
        BLB["Backend HTTPS Load Balancer<br/>Static Global IP"]
    end

    subgraph VPC ["Custom VPC: learn-gcp-vpc (10.0.0.0/16)"]
        NAT("Cloud NAT Gateway: gke-nat<br/>(Secure Egress)")
        
        subgraph GKE ["GKE Private Cluster (e2-standard-4 Nodes)"]
            
            subgraph KubeSystem ["kube-system Namespace"]
                CNI["Istio CNI DaemonSet<br/>(Traffic Interception)"]
            end

            subgraph IstioSystem ["istio-system Namespace (Ambient Mesh)"]
                Istiod["istiod (Control Plane)"]
                Gateway["Istio Ingress Gateway<br/>(GCLB Backend)"]
                ZTunnel["ztunnel DaemonSet<br/>(Rust L4 Zero-Trust Proxy)"]
            end

            subgraph DefaultNS ["default Namespace (Workload)"]
                Service("backend-service (ClusterIP)")
                Pods["backend-api Pods<br/>(Zero Sidecars • Pure Container)"]
            end

        end
    end

    subgraph GoogleServices ["Google Managed Services"]
        DB[("Cloud SQL PostgreSQL<br/>(Private IP via VPC Peering)")]
        SM["Secret Manager<br/>(DB Credentials via Workload Identity)"]
    end

    %% Flow 1: Frontend Website Loading
    User -- "1. Visit Website (HTTPS)" --> WAF1
    WAF1 --> FLB
    FLB --> CDN
    CDN --> Bucket

    %% Flow 2: API Request
    User -- "2. API fetch() Request" --> WAF2
    WAF2 --> BLB
    BLB -- "Terminates Public TLS" --> Gateway
    Gateway -- "Routes via VirtualService" --> ZTunnel
    ZTunnel -- "Encrypted L4 mTLS (HBONE)" --> Pods

    %% Control Plane Stream
    Istiod -. "xDS Config" .-> ZTunnel
    CNI -. "Redirects Node Traffic" .-> ZTunnel

    %% Flow 3: Security & DB Access
    Pods -. "3. Read Credentials" .-> SM
    Pods -. "4. Private SQL Query" .-> DB

    %% Outbound
    GKE -. "Secure Outbound Access" .-> NAT

    %% Styling
    classDef edge fill:#4285F4,stroke:#fff,stroke-width:2px,color:#fff;
    classDef mesh fill:#673AB7,stroke:#fff,stroke-width:2px,color:#fff;
    classDef compute fill:#0F9D58,stroke:#fff,stroke-width:2px,color:#fff;
    classDef db fill:#EA4335,stroke:#fff,stroke-width:2px,color:#fff;
    classDef storage fill:#FBBC05,stroke:#fff,stroke-width:2px,color:#000;
    
    class FLB,BLB,WAF1,WAF2 edge;
    class Istiod,Gateway,ZTunnel,CNI mesh;
    class Pods,Service compute;
    class DB,SM db;
    class Bucket storage;
```

---

## 🚀 Key Architectural Innovations

### 1. Istio Ambient Mode (Sidecar-less Mesh)
* **Zero Pod Bloat:** Unlike classic Istio which injects an `istio-proxy` Envoy container into every application pod, Ambient mode runs pure single-container pods (`1/1 Ready`).
* **Node-Level `ztunnel`:** A dedicated Rust-based zero-trust tunnel daemonset runs on each node, handling L4 mutual TLS (mTLS) and telemetry with minimal memory footprint (~15MB vs ~150MB per pod).
* **`istio-cni` in `kube-system`:** Transparently captures pod network traffic at the kernel level and redirects it to `ztunnel` without mutating pod specifications.

### 2. Dual-Layer Edge Security & Performance
* **Frontend:** Google Cloud Armor WAF + Cloud CDN caching on Cloud Storage bucket objects.
* **Backend:** Google Cloud Armor + External HTTP(S) Load Balancer bound to a reserved static IP, routing to the GKE Ingress Gateway.

### 3. Enterprise Security & Secrets
* **Workload Identity Federation:** No static GCP service account keys in pods. The backend pod authenticates directly to Google Cloud APIs using Kubernetes Service Accounts.
* **Secret Manager Integration:** Database credentials are securely injected at runtime from GCP Secret Manager.
* **Private Network Isolation:** GKE cluster and Cloud SQL instances have 0 public IPs; communication traverses internal VPC peering and Cloud NAT handles outbound traffic.

---

## 📁 Repository Structure

```
├── environments/
│   └── dev/                  # Root Terraform environment (wires all modules)
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── modules/
│   ├── network/              # VPC, Subnets, Firewalls (GKE Master & GCLB), Cloud NAT
│   ├── database/             # Cloud SQL PostgreSQL & Private Service Access
│   ├── gke/                  # GKE Private Cluster & e2-standard-4 Node Pools
│   ├── secrets/              # GCP Secret Manager & Workload Identity IAM bindings
│   ├── frontend/             # Cloud Storage, Cloud CDN, HTTPS Load Balancer, WAF
│   ├── istio/                # Istio Base, Ambient CNI, istiod, ztunnel, and Ingress
│   └── backend_app/          # Helm chart for Backend Deployment & Gateway routing
```

---

## 🛠️ Verification & Testing Commands

```bash
# 1. Verify Istio Ambient Mode components
kubectl get daemonsets,pods -n kube-system -l app=istio-cni
kubectl get daemonsets,pods -n istio-system -l app=ztunnel

# 2. Verify backend pod is running without sidecars (1/1)
kubectl get pods -l app=backend-api

# 3. Test API connectivity
curl -k https://<BACKEND_STATIC_IP>/api/data
```
