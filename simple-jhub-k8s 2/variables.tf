# =============================================================================
# VARIABLES: Configurable Parameters
# =============================================================================
# Variables make the deployment reusable and customizable without editing
# the main configuration. You can override them via:
#   1. terraform.tfvars file (see terraform.tfvars)
#   2. Command line: terraform apply -var="namespace=my-jhub"
#   3. Environment variables: TF_VAR_namespace=my-jhub
#
# Each variable has:
#   - description: What it controls
#   - type: Data type (string, number, etc.)
#   - default: Value used if not explicitly set
# =============================================================================


# ---- KUBERNETES CONNECTION ----

variable "kube_config_path" {
  description = <<-EOT
    Path to your kubeconfig file. This file tells Terraform how to connect
    to your Kubernetes cluster. Common locations:
      - minikube/kind/Docker Desktop: ~/.kube/config (default)
      - k3s: /etc/rancher/k3s/k3s.yaml
      - Custom: wherever you saved it
  EOT
  type        = string
  default     = "~/.kube/config"
}


# ---- NAMESPACE ----

variable "namespace" {
  description = <<-EOT
    Kubernetes namespace where all JupyterHub resources will be created.
    Using a dedicated namespace keeps JupyterHub isolated from other
    workloads and makes cleanup easy (delete the namespace = delete everything).
  EOT
  type        = string
  default     = "jupyterhub"
}


# ---- DOCKER IMAGES ----
# These variables control which container images are used for each component.
# Pinning to specific tags (instead of "latest") ensures reproducible deploys.

variable "hub_image" {
  description = <<-EOT
    Docker image for the JupyterHub process (the central "brain").
    This image contains JupyterHub itself, its Python dependencies, and
    the Tornado web server. We use the official image from Docker Hub.
    
    Tag "latest" is used here for simplicity, but in production you should
    pin to a specific version like "jupyterhub/jupyterhub:4.0.2" to avoid
    unexpected breaking changes on redeployment.
  EOT
  type        = string
  default     = "jupyterhub/jupyterhub:latest"
}

variable "notebook_image" {
  description = <<-EOT
    Docker image for single-user notebook servers (one per user).
    The base-notebook image includes Python, JupyterLab, and essential
    scientific computing libraries. Alternatives:
      - jupyter/minimal-notebook  : Lighter, fewer pre-installed packages
      - jupyter/scipy-notebook    : Adds scipy, pandas, matplotlib, etc.
      - jupyter/datascience-notebook : Adds R and Julia kernels
      - jupyter/tensorflow-notebook  : Adds TensorFlow + GPU support
    
    Choose based on what your users need. Larger images = slower first spawn.
  EOT
  type        = string
  default     = "jupyter/base-notebook:latest"
}

variable "proxy_image" {
  description = <<-EOT
    Docker image for the Configurable HTTP Proxy (CHP).
    This is a lightweight Node.js reverse proxy that routes traffic between
    users and their notebook servers. It's purpose-built for JupyterHub.
    
    The image is very small (~50MB) and rarely needs to be changed.
  EOT
  type        = string
  default     = "jupyterhub/configurable-http-proxy:latest"
}


# ---- NETWORKING ----

variable "proxy_node_port" {
  description = <<-EOT
    The port on your HOST machine where JupyterHub will be accessible.
    After deployment, open http://localhost:<this_port> in your browser.
    
    Must be in the range 30000-32767 (Kubernetes NodePort range).
    Default 30080 is chosen to avoid conflicts with common services.
    
    If you get "port already allocated", change this to another value.
  EOT
  type        = number
  default     = 30080

  validation {
    condition     = var.proxy_node_port >= 30000 && var.proxy_node_port <= 32767
    error_message = "NodePort must be between 30000 and 32767 (Kubernetes range)."
  }
}


# ---- AUTHENTICATION ----

variable "dummy_password" {
  description = <<-EOT
    Password for the DummyAuthenticator. ALL users log in with this password.
    This is for LOCAL DEVELOPMENT ONLY — it provides no real security.
    
    For production, replace DummyAuthenticator with:
      - OAuthenticator (GitHub, Google, Azure AD)
      - LDAPAuthenticator (Active Directory)
      - PAMAuthenticator (Linux system users)
    
    Marked as sensitive so it won't appear in terraform plan/apply output.
  EOT
  type        = string
  default     = "jupyterhub"
  sensitive   = true
}
