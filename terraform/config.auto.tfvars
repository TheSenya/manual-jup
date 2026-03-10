# =============================================================================
# Deployment Configuration  (auto-loaded by Terraform)
#
# Single source of truth for ALL configurable values.
# =============================================================================

# -----------------------------------------------------------------------------
# Kind cluster
# -----------------------------------------------------------------------------
kind_cluster_name = "jupyterhub"

# -----------------------------------------------------------------------------
# Namespace
# -----------------------------------------------------------------------------
namespace = "jupyterhub"

# -----------------------------------------------------------------------------
# Container images
#
# All images MUST be mirrored to your corporate private registry before
# deploying.  Replace YOUR_REGISTRY.corp with your actual registry hostname.
#
# Source images to mirror:
#   quay.io/jupyterhub/k8s-hub:4.1.6
#   quay.io/jupyterhub/configurable-http-proxy:4.6.2
#   quay.io/jupyterhub/k8s-singleuser-sample:4.1.6
# -----------------------------------------------------------------------------

# JupyterHub Hub process
hub_image     = "YOUR_REGISTRY.corp/jupyterhub/k8s-hub"
hub_image_tag = "4.1.6"

# Configurable HTTP Proxy
proxy_image     = "YOUR_REGISTRY.corp/jupyterhub/configurable-http-proxy"
proxy_image_tag = "4.6.2"

# Per-user notebook server (spawned by KubeSpawner)
singleuser_image     = "YOUR_REGISTRY.corp/jupyterhub/k8s-singleuser-sample"
singleuser_image_tag = "4.1.6"

# -----------------------------------------------------------------------------
# Private registry — TLS trust (containerd, Kind nodes)
#
# IMPORTANT: Kubernetes imagePullSecrets only carry credentials (username /
# password). They do NOT configure TLS certificate trust. Image pulls happen
# inside containerd on the Kind node. For a corporate CA or self-signed cert
# you MUST inject a containerd config patch so the node runtime trusts it.
#
# Uncomment and edit ONE of the blocks below:
#
# Option A — skip TLS verification (easiest, lower security):
#   containerd_config_patches = [
#     <<-TOML
#       [plugins."io.containerd.grpc.v1.cri".registry.configs]
#         [plugins."io.containerd.grpc.v1.cri".registry.configs."YOUR_REGISTRY.corp".tls]
#           insecure_skip_verify = true
#     TOML
#   ]
#
# Option B — trust a specific CA file (already present on the host and will be
#   bind-mounted into Kind nodes, or loaded via an extraMount):
#   containerd_config_patches = [
#     <<-TOML
#       [plugins."io.containerd.grpc.v1.cri".registry.configs]
#         [plugins."io.containerd.grpc.v1.cri".registry.configs."YOUR_REGISTRY.corp".tls]
#           ca_file = "/etc/ssl/certs/corp-ca.crt"
#     TOML
#   ]
# -----------------------------------------------------------------------------
containerd_config_patches = []

# -----------------------------------------------------------------------------
# Private registry — CA certificate for Kubernetes Secrets
# (Used to mount the cert into Hub / user-pod containers so app-level TLS
#  works.  Does NOT affect containerd image pulling — use the patch above.)
# Leave empty to skip.
# Set to the path of your CA certificate file, e.g. "./certs/ca.crt"
# -----------------------------------------------------------------------------
registry_ca_cert_file = ""

# Docker config JSON for pulling from private registries (credentials only).
# Generate with:
#   kubectl create secret docker-registry reg-creds \
#     --docker-server=YOUR_REGISTRY.corp \
#     --docker-username=<user> --docker-password=<pass> \
#     --dry-run=client -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
# Or leave empty to skip.
registry_docker_config_json = ""

# -----------------------------------------------------------------------------
# Scaling / Service
# -----------------------------------------------------------------------------
hub_replicas   = 1
proxy_replicas = 1

proxy_service_type = "NodePort"

# NodePort and host port for Kind port mapping (only used with NodePort).
# proxy_node_port MUST be in range 30000-32767.
proxy_node_port = 30080
proxy_host_port = 8080

# -----------------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------------
hub_storage_size = "1Gi"

# -----------------------------------------------------------------------------
# Secrets
# -----------------------------------------------------------------------------
# Leave empty to auto-generate a random 64-char token.
proxy_secret_token = ""
