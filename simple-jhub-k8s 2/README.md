# JupyterHub on Local Kubernetes — Terraform Deployment

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster (local)                    │
│  Namespace: jupyterhub                                          │
│                                                                 │
│  ┌──────────────────────────────────┐                           │
│  │  Configurable HTTP Proxy (CHP)   │ ◄── NodePort :30080      │
│  │  image: jupyterhub/              │     (browser connects     │
│  │    configurable-http-proxy       │      here)                │
│  │                                  │                           │
│  │  :8000 (public)  :8001 (API)     │                           │
│  └──────┬───────────────┬───────────┘                           │
│         │               ▲                                       │
│         │ (routes       │ (Hub registers routes                 │
│         │  traffic)     │  via API + auth token)                │
│         ▼               │                                       │
│  ┌──────────────────────┴───────────┐                           │
│  │  JupyterHub (Hub)                │                           │
│  │  image: jupyterhub/jupyterhub    │                           │
│  │                                  │                           │
│  │  :8081 (hub web + API)           │                           │
│  │  - Authenticates users           │                           │
│  │  - Spawns notebook Pods          │                           │
│  │  - Manages proxy routes          │                           │
│  └──────┬───────────────────────────┘                           │
│         │                                                       │
│         │ (KubeSpawner creates Pods via K8s API)                │
│         ▼                                                       │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐               │
│  │ Notebook Pod │ │ Notebook Pod │ │ Notebook Pod │  ...        │
│  │ (user: alice)│ │ (user: bob) │ │ (user: carol)│              │
│  │ :8888        │ │ :8888        │ │ :8888        │             │
│  │ jupyter/     │ │ jupyter/     │ │ jupyter/     │             │
│  │ base-notebook│ │ base-notebook│ │ base-notebook│             │
│  └─────────────┘ └─────────────┘ └─────────────┘               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Request Flow

```
1. User opens http://localhost:30080
2. Request hits the CHP (Configurable HTTP Proxy)
3. CHP checks its route table:
   a. No route for this user → forward to Hub at :8081
   b. Hub shows login page → user enters credentials
   c. Hub authenticates user → tells KubeSpawner to create a Pod
   d. KubeSpawner creates a new Pod running jupyter/base-notebook
   e. Hub registers route with CHP: "/user/alice → pod-ip:8888"
   f. Hub redirects browser to /user/alice
   g. CHP now routes /user/alice to the notebook Pod
4. User is now working in their own isolated Jupyter environment
```

## Prerequisites

1. **A local Kubernetes cluster** (pick one):
   - [minikube](https://minikube.sigs.k8s.io/docs/start/) — `minikube start`
   - [kind](https://kind.sigs.k8s.io/) — `kind create cluster`
   - [Docker Desktop](https://www.docker.com/products/docker-desktop) — Enable Kubernetes in settings
   - [k3s](https://k3s.io/) — `curl -sfL https://get.k3s.io | sh -`

2. **Terraform** (>= 1.0):
   ```bash
   # macOS
   brew install terraform
   
   # Linux
   wget https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_amd64.zip
   unzip terraform_1.7.0_linux_amd64.zip && sudo mv terraform /usr/local/bin/
   ```

3. **kubectl** (for debugging):
   ```bash
   # macOS
   brew install kubectl
   
   # Linux
   curl -LO "https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   chmod +x kubectl && sudo mv kubectl /usr/local/bin/
   ```

## Quick Start

```bash
# 1. Initialize Terraform (downloads the kubernetes provider plugin)
terraform init

# 2. Preview what will be created (dry run)
terraform plan

# 3. Deploy everything
terraform apply

# 4. Wait for pods to be ready (may take 1-2 minutes for image pulls)
kubectl get pods -n jupyterhub --watch

# 5. Open JupyterHub
open http://localhost:30080   # macOS
xdg-open http://localhost:30080   # Linux
```

## Login

- **Username**: Any name you want (e.g., `alice`, `testuser`)
- **Password**: `jupyterhub` (configurable in `terraform.tfvars`)

Each username gets its own isolated notebook server (Pod).

## Files Explained

| File | Purpose |
|---|---|
| `main.tf` | All Kubernetes resources (namespace, deployments, services, RBAC, secrets) |
| `variables.tf` | Input variable declarations with descriptions and defaults |
| `terraform.tfvars` | Actual values for variables (this is what you edit) |
| `outputs.tf` | Values printed after deployment (URL, instructions) |

## Customization

### Change the notebook image
Edit `terraform.tfvars`:
```hcl
notebook_image = "jupyter/scipy-notebook:latest"   # includes scipy, pandas, matplotlib
```

### Change the access port
```hcl
proxy_node_port = 31000   # must be 30000-32767
```

### Change resource limits
Edit `main.tf` → `kubernetes_config_map.hub_config` → the KubeSpawner section.

## Debugging

```bash
# Check pod status
kubectl get pods -n jupyterhub

# View Hub logs
kubectl logs -n jupyterhub deployment/jupyterhub

# View Proxy logs  
kubectl logs -n jupyterhub deployment/configurable-http-proxy

# Check if Services are working
kubectl get svc -n jupyterhub

# Interactive shell into Hub pod
kubectl exec -it -n jupyterhub deployment/jupyterhub -- /bin/bash
```

## Teardown

```bash
terraform destroy
```

This removes ALL resources including the namespace and everything in it.
