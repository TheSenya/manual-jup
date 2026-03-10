terraform {
  required_version = ">= 1.3"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.7"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Kind provider — creates the local cluster
provider "kind" {}

# Kubernetes provider — wired to the Kind cluster's kubeconfig
provider "kubernetes" {
  host                   = kind_cluster.jupyterhub.endpoint
  client_certificate     = kind_cluster.jupyterhub.client_certificate
  client_key             = kind_cluster.jupyterhub.client_key
  cluster_ca_certificate = kind_cluster.jupyterhub.cluster_ca_certificate
}
