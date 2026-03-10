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
# -----------------------------------------------------------------------------

# JupyterHub Hub process
hub_image     = "quay.io/jupyterhub/k8s-hub"
hub_image_tag = "4.1.6"

# Configurable HTTP Proxy
proxy_image     = "quay.io/jupyterhub/configurable-http-proxy"
proxy_image_tag = "4.6.2"

# Per-user notebook server (spawned by KubeSpawner)
singleuser_image     = "quay.io/jupyterhub/k8s-singleuser-sample"
singleuser_image_tag = "4.1.6"

# -----------------------------------------------------------------------------
# Private registry — CA certificate for image pulling
# Leave empty to skip (public registries don't need this).
# Set to the path of your CA certificate file, e.g. "./certs/ca.crt"
# -----------------------------------------------------------------------------
registry_ca_cert_file = ""

# Docker config JSON for pulling from private registries.
# Generate with:  kubectl create secret docker-registry --dry-run=client -o jsonpath='{.data.\.dockerconfigjson}' ...
# Or leave empty to skip.
registry_docker_config_json = ""

# -----------------------------------------------------------------------------
# Scaling / Service
# -----------------------------------------------------------------------------
hub_replicas       = 1
proxy_replicas     = 1
proxy_service_type = "NodePort"

# NodePort and host port for Kind port mapping (only used with NodePort)
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
