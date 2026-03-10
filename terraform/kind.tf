# =============================================================================
# Kind Cluster — local Kubernetes for development
# =============================================================================
resource "kind_cluster" "jupyterhub" {
  name           = var.kind_cluster_name
  node_image     = var.kind_node_image
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    # containerd_config_patches lets you inject TOML snippets into every node's
    # containerd config.  This is the ONLY way to make Kind nodes trust a
    # corporate private registry CA certificate — Kubernetes imagePullSecrets
    # only carry credentials, not TLS trust roots.  Set the
    # containerd_config_patches variable in config.auto.tfvars (see its
    # commented-out example) before applying if your registry uses a
    # self-signed or corporate CA.
    containerd_config_patches = var.containerd_config_patches

    node {
      role = "control-plane"

      # Map container port 80 → host port 8080 so you can reach JupyterHub
      # via http://localhost:8080 when using NodePort service type.
      extra_port_mappings {
        container_port = var.proxy_node_port
        host_port      = var.proxy_host_port
        protocol       = "TCP"
      }
    }

    node {
      role = "worker"
    }
  }
}
