# =============================================================================
# TERRAFORM.TFVARS — Default Variable Overrides
# =============================================================================
# This file sets values for the variables defined in variables.tf.
# Terraform automatically loads any file named "terraform.tfvars".
#
# To use a DIFFERENT file, run:
#   terraform apply -var-file="production.tfvars"
#
# You can also create "terraform.tfvars.example" and git-ignore the real
# tfvars file to avoid committing secrets (like passwords).
# =============================================================================

# Kubernetes connection
kube_config_path = "~/.kube/config"

# Namespace
namespace = "jupyterhub"

# Docker images — pin versions for reproducibility in production
hub_image      = "jupyterhub/jupyterhub:latest"
notebook_image = "jupyter/base-notebook:latest"
proxy_image    = "jupyterhub/configurable-http-proxy:latest"

# Networking — access JupyterHub at http://localhost:30080
proxy_node_port = 30080

# Authentication (CHANGE THIS if you care about even basic security)
dummy_password = "jupyterhub"
