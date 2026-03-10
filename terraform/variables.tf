# -----------------------------------------------------------------------------
# Kind cluster
# -----------------------------------------------------------------------------
variable "kind_cluster_name" {
  description = "Name of the Kind cluster"
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
}

variable "registry_docker_config_json" {
  description = "Docker config JSON (base64-decoded) for private registry auth. Leave empty to skip."
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Scaling / Service
# -----------------------------------------------------------------------------
variable "hub_replicas" {
  description = "Number of Hub deployment replicas"
  type        = number
}

variable "proxy_replicas" {
  description = "Number of proxy deployment replicas"
  type        = number
}

variable "proxy_service_type" {
  description = "Kubernetes Service type for the proxy (ClusterIP, NodePort, LoadBalancer)"
  type        = string
}

variable "proxy_node_port" {
  description = "NodePort number for the proxy service (must match Kind extra_port_mappings)"
  type        = number
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
}
