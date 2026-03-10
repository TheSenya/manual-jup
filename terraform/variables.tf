# -----------------------------------------------------------------------------
# Kind cluster
# -----------------------------------------------------------------------------
variable "kind_cluster_name" {
  description = "Name of the Kind cluster"
  type        = string
}

variable "kind_node_image" {
  description = "Docker image used for Kind cluster nodes. Must be a mirror of kindest/node at the correct Kubernetes version. Example: YOUR_REGISTRY.corp/kindest/node:v1.31.0"
  type        = string
}

# -----------------------------------------------------------------------------
# Namespace
# -----------------------------------------------------------------------------
variable "namespace" {
  description = "Kubernetes namespace for JupyterHub resources"
  type        = string
}

# -----------------------------------------------------------------------------
# Hub image
# -----------------------------------------------------------------------------
variable "hub_image" {
  description = "Container image for the JupyterHub Hub process"
  type        = string
}

variable "hub_image_tag" {
  description = "Tag for the Hub container image"
  type        = string
}

# -----------------------------------------------------------------------------
# Configurable HTTP Proxy image
# -----------------------------------------------------------------------------
variable "proxy_image" {
  description = "Container image for the configurable-http-proxy"
  type        = string
}

variable "proxy_image_tag" {
  description = "Tag for the proxy container image"
  type        = string
}

# -----------------------------------------------------------------------------
# Single-user notebook image (spawned per user)
# -----------------------------------------------------------------------------
variable "singleuser_image" {
  description = "Container image for per-user notebook servers"
  type        = string
}

variable "singleuser_image_tag" {
  description = "Tag for the single-user notebook image"
  type        = string
}

# -----------------------------------------------------------------------------
# Private registry
# -----------------------------------------------------------------------------
variable "registry_ca_cert_file" {
  description = "Path to CA certificate file for private registry TLS. Leave empty to skip."
  type        = string
  default     = ""
}

variable "registry_docker_config_json" {
  description = "Docker config JSON (base64-decoded) for private registry auth. Leave empty to skip."
  type        = string
  sensitive   = true
  default     = ""
}

# containerd_config_patches are TOML snippets injected into every Kind node's
# containerd configuration at cluster creation time.  This is the ONLY supported
# way to make Kind nodes trust a private registry CA certificate — Kubernetes
# imagePullSecrets only carry credentials, not TLS trust.
#
# Example for a self-signed corporate registry:
#
#   containerd_config_patches = [
#     <<-TOML
#       [plugins."io.containerd.grpc.v1.cri".registry.configs]
#         [plugins."io.containerd.grpc.v1.cri".registry.configs."myregistry.corp".tls]
#           insecure_skip_verify = true
#     TOML
#   ]
#
# Or with a CA certificate file pre-loaded on the host:
#
#   containerd_config_patches = [
#     <<-TOML
#       [plugins."io.containerd.grpc.v1.cri".registry.configs]
#         [plugins."io.containerd.grpc.v1.cri".registry.configs."myregistry.corp".tls]
#           ca_file = "/etc/ssl/certs/corp-ca.crt"
#     TOML
#   ]
variable "containerd_config_patches" {
  description = "List of containerd TOML config patch strings applied to every Kind node. Required to trust a corporate private registry CA certificate."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Scaling / Service
# -----------------------------------------------------------------------------
variable "hub_replicas" {
  # JupyterHub Hub uses SQLite on a ReadWriteOnce PVC. Only one replica can
  # mount the PVC at a time and JupyterHub Hub is not designed for active-active
  # HA without switching to an external database (e.g. PostgreSQL). Enforce 1.
  description = "Number of Hub deployment replicas. Must be 1; the Hub uses SQLite on a ReadWriteOnce PVC and cannot run as multiple concurrent replicas."
  type        = number

  validation {
    condition     = var.hub_replicas == 1
    error_message = "hub_replicas must be 1. JupyterHub Hub uses SQLite on a ReadWriteOnce PVC and does not support multiple concurrent replicas."
  }
}

variable "proxy_replicas" {
  description = "Number of proxy deployment replicas"
  type        = number
}

variable "proxy_service_type" {
  description = "Kubernetes Service type for the proxy (ClusterIP, NodePort, LoadBalancer)"
  type        = string

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.proxy_service_type)
    error_message = "proxy_service_type must be one of: ClusterIP, NodePort, LoadBalancer."
  }
}

variable "proxy_node_port" {
  description = "NodePort number for the proxy service (must match Kind extra_port_mappings). Must be in the Kubernetes NodePort range 30000-32767."
  type        = number

  validation {
    condition     = var.proxy_node_port >= 30000 && var.proxy_node_port <= 32767
    error_message = "proxy_node_port must be in the Kubernetes NodePort range 30000-32767."
  }
}

variable "proxy_host_port" {
  description = "Host port that Kind maps to the proxy NodePort"
  type        = number
}

# -----------------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------------
variable "hub_storage_size" {
  description = "Size of the PersistentVolumeClaim for the Hub SQLite database"
  type        = string
}

# -----------------------------------------------------------------------------
# Secrets
# -----------------------------------------------------------------------------
variable "proxy_secret_token" {
  description = "Shared secret token between the Hub and the proxy. Leave empty to auto-generate."
  type        = string
  sensitive   = true
  default     = ""
}
