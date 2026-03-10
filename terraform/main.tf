# =============================================================================
# Locals
# =============================================================================
locals {
  # Use provided token or auto-generated one
  proxy_token = var.proxy_secret_token != "" ? var.proxy_secret_token : random_password.proxy_token[0].result

  common_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "jupyterhub"
  }
}

# =============================================================================
# Random proxy auth token (only when not supplied)
# =============================================================================
resource "random_password" "proxy_token" {
  count   = var.proxy_secret_token == "" ? 1 : 0
  length  = 64
  special = false
}

# =============================================================================
# Namespace
# =============================================================================
resource "kubernetes_namespace" "jupyterhub" {
  metadata {
    name   = var.namespace
    labels = local.common_labels
  }
}

# =============================================================================
# Secret — shared proxy token + JupyterHub config secrets
# =============================================================================
resource "kubernetes_secret" "hub" {
  metadata {
    name      = "jupyterhub-hub"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    labels    = local.common_labels
  }

  data = {
    "proxy.token"          = local.proxy_token
    "jupyterhub_config.py" = "" # placeholder for secret config
    "values.yaml"          = "" # placeholder
  }
}

# =============================================================================
# Secret — Private registry CA certificate (optional)
# =============================================================================
resource "kubernetes_secret" "registry_ca_cert" {
  count = var.registry_ca_cert_file != "" ? 1 : 0

  metadata {
    name      = "registry-ca-cert"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    labels    = local.common_labels
  }

  data = {
    "ca.crt" = file(var.registry_ca_cert_file)
  }
}

# =============================================================================
# Secret — Private registry image pull credentials (optional)
# =============================================================================
resource "kubernetes_secret" "registry_pull" {
  count = var.registry_docker_config_json != "" ? 1 : 0

  metadata {
    name      = "registry-pull-secret"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    labels    = local.common_labels
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = var.registry_docker_config_json
  }
}

# =============================================================================
# Service Account + RBAC — Hub needs to manage pods in this namespace
# =============================================================================
resource "kubernetes_service_account" "hub" {
  metadata {
    name      = "jupyterhub-hub"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    labels    = local.common_labels
  }

  dynamic "image_pull_secret" {
    for_each = var.registry_docker_config_json != "" ? [1] : []
    content {
      name = kubernetes_secret.registry_pull[0].metadata[0].name
    }
  }
}

resource "kubernetes_role" "hub" {
  metadata {
    name      = "jupyterhub-hub"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    labels    = local.common_labels
  }

  # Manage user notebook pods
  rule {
    api_groups = [""]
    resources  = ["pods", "events"]
    verbs      = ["get", "list", "watch", "create", "delete", "patch", "update"]
  }

  # Manage per-user services
  rule {
    api_groups = [""]
    resources  = ["services"]
    verbs      = ["get", "list", "watch", "create", "delete"]
  }

  # Manage per-user PVCs
  rule {
    api_groups = [""]
    resources  = ["persistentvolumeclaims"]
    verbs      = ["get", "list", "watch", "create", "delete"]
  }

  # Read secrets
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding" "hub" {
  metadata {
    name      = "jupyterhub-hub"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    labels    = local.common_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.hub.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.hub.metadata[0].name
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
  }
}

# =============================================================================
# ConfigMap — jupyterhub_config.py
# =============================================================================
resource "kubernetes_config_map" "hub" {
  metadata {
    name      = "jupyterhub-hub-config"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    labels    = local.common_labels
  }

  data = {
    "jupyterhub_config.py" = templatefile("${path.module}/configs/jupyterhub_config.py", {
      singleuser_image       = var.singleuser_image
      singleuser_image_tag   = var.singleuser_image_tag
      namespace              = var.namespace
      image_pull_secret_name = var.registry_docker_config_json != "" ? kubernetes_secret.registry_pull[0].metadata[0].name : ""
    })
  }
}

# =============================================================================
# PVC — Hub Database
# =============================================================================
resource "kubernetes_persistent_volume_claim" "hub_db" {
  metadata {
    name      = "jupyterhub-hub-db"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    labels    = local.common_labels
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.hub_storage_size
      }
    }
  }
}

# =============================================================================
# Deployment — Hub
# =============================================================================
resource "kubernetes_deployment" "hub" {
  metadata {
    name      = "jupyterhub-hub"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "hub" })
  }

  spec {
    replicas = var.hub_replicas

    selector {
      match_labels = {
        "app.kubernetes.io/component" = "hub"
        "app.kubernetes.io/part-of"   = "jupyterhub"
      }
    }

    template {
      metadata {
        labels = merge(local.common_labels, { "app.kubernetes.io/component" = "hub" })
      }

      spec {
        service_account_name = kubernetes_service_account.hub.metadata[0].name

        dynamic "image_pull_secrets" {
          for_each = var.registry_docker_config_json != "" ? [1] : []
          content {
            name = kubernetes_secret.registry_pull[0].metadata[0].name
          }
        }

        container {
          name  = "hub"
          image = "${var.hub_image}:${var.hub_image_tag}"

          port {
            name           = "http"
            container_port = 8081
          }

          env {
            name = "CONFIGPROXY_AUTH_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.hub.metadata[0].name
                key  = "proxy.token"
              }
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/usr/local/etc/jupyterhub/jupyterhub_config.py"
            sub_path   = "jupyterhub_config.py"
            read_only  = true
          }

          volume_mount {
            name       = "hub-db"
            mount_path = "/srv/jupyterhub"
          }

          readiness_probe {
            http_get {
              path = "/hub/health"
              port = 8081
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/hub/health"
              port = 8081
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.hub.metadata[0].name
          }
        }

        volume {
          name = "hub-db"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.hub_db.metadata[0].name
          }
        }
      }
    }
  }
}

# =============================================================================
# Service — Hub  (ClusterIP, internal only)
# =============================================================================
resource "kubernetes_service" "hub" {
  metadata {
    name      = "jupyterhub-hub"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "hub" })
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/component" = "hub"
      "app.kubernetes.io/part-of"   = "jupyterhub"
    }

    port {
      name        = "http"
      port        = 8081
      target_port = 8081
    }
  }
}

# =============================================================================
# Deployment — Configurable HTTP Proxy
# =============================================================================
resource "kubernetes_deployment" "proxy" {
  metadata {
    name      = "jupyterhub-proxy"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "proxy" })
  }

  spec {
    replicas = var.proxy_replicas

    selector {
      match_labels = {
        "app.kubernetes.io/component" = "proxy"
        "app.kubernetes.io/part-of"   = "jupyterhub"
      }
    }

    template {
      metadata {
        labels = merge(local.common_labels, { "app.kubernetes.io/component" = "proxy" })
      }

      spec {
        dynamic "image_pull_secrets" {
          for_each = var.registry_docker_config_json != "" ? [1] : []
          content {
            name = kubernetes_secret.registry_pull[0].metadata[0].name
          }
        }

        container {
          name  = "proxy"
          image = "${var.proxy_image}:${var.proxy_image_tag}"

          args = [
            "configurable-http-proxy",
            "--ip=0.0.0.0",
            "--port=8000",
            "--api-ip=0.0.0.0",
            "--api-port=8001",
            "--default-target=http://jupyterhub-hub:8081",
            "--error-target=http://jupyterhub-hub:8081/hub/error",
          ]

          port {
            name           = "http"
            container_port = 8000
          }

          port {
            name           = "api"
            container_port = 8001
          }

          env {
            name = "CONFIGPROXY_AUTH_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.hub.metadata[0].name
                key  = "proxy.token"
              }
            }
          }

          readiness_probe {
            http_get {
              path = "/_chp_healthz"
              port = 8000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/_chp_healthz"
              port = 8000
            }
            initial_delay_seconds = 15
            period_seconds        = 30
          }
        }
      }
    }
  }
}

# =============================================================================
# Service — Proxy  (public-facing, user-configurable type)
# =============================================================================
resource "kubernetes_service" "proxy" {
  metadata {
    name      = "jupyterhub-proxy-public"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "proxy" })
  }

  spec {
    type = var.proxy_service_type

    selector = {
      "app.kubernetes.io/component" = "proxy"
      "app.kubernetes.io/part-of"   = "jupyterhub"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 8000
      node_port   = var.proxy_service_type == "NodePort" ? var.proxy_node_port : null
    }
  }
}

# =============================================================================
# Service — Proxy API  (ClusterIP, internal only — used by Hub)
# =============================================================================
resource "kubernetes_service" "proxy_api" {
  metadata {
    name      = "jupyterhub-proxy-api"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    labels    = merge(local.common_labels, { "app.kubernetes.io/component" = "proxy" })
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/component" = "proxy"
      "app.kubernetes.io/part-of"   = "jupyterhub"
    }

    port {
      name        = "api"
      port        = 8001
      target_port = 8001
    }
  }
}
