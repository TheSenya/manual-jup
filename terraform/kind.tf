# =============================================================================
# Kind Cluster — local Kubernetes for development
# =============================================================================
resource "kind_cluster" "jupyterhub" {
  name           = var.kind_cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

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
