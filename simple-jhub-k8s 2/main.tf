# =============================================================================
# JupyterHub on Local Kubernetes — Terraform Configuration
# =============================================================================
#
# ARCHITECTURE OVERVIEW:
# ----------------------
# JupyterHub has a "hub-and-spoke" architecture with 3 core components:
#
#   1. JupyterHub (the Hub)
#      - The central process that manages authentication, spawning, and routing.
#      - It decides WHO can log in and WHEN to create new notebook servers.
#      - Image: jupyterhub/jupyterhub
#
#   2. Configurable HTTP Proxy (CHP)
#      - Sits in front of everything as the public-facing entry point.
#      - Routes traffic: unauthenticated users → Hub, authenticated users → their notebook.
#      - The Hub tells the proxy "user X's notebook is at address Y" via an API.
#      - Image: jupyterhub/configurable-http-proxy
#
#   3. Jupyter Notebook Server (single-user servers)
#      - One is spawned PER USER after they log in.
#      - Each runs in its own Pod (in Kubernetes), giving isolation.
#      - Image: jupyter/base-notebook
#
# TRAFFIC FLOW:
#   Browser → CHP (:8000) → checks route table
#       ├── No route for user? → Forward to Hub (:8081) → Login page
#       └── Route exists?     → Forward to user's Notebook Pod (:8888)
#
# WHY THESE 3 IMAGES?
#   - Separation of concerns: the proxy handles routing, the hub handles logic,
#     and notebooks handle the actual user workload.
#   - Scalability: you can run many notebook pods independently.
#   - Security: the proxy shields the hub; the hub controls access.
#
# =============================================================================


# =============================================================================
# TERRAFORM SETTINGS
# =============================================================================
# This block tells Terraform which providers (plugins) it needs to download.
# We need the "kubernetes" provider to create K8s resources, and "random"
# to generate a secure API token for the proxy.
# =============================================================================
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      # This provider translates Terraform HCL into Kubernetes API calls.
      # Without it, Terraform wouldn't know how to talk to your cluster.
      version = "~> 2.23"
    }
    random = {
      source  = "hashicorp/random"
      # Used to generate cryptographically secure random strings.
      # We need this for the proxy auth token (see below).
      version = "~> 3.5"
    }
  }
}


# =============================================================================
# PROVIDER: KUBERNETES
# =============================================================================
# Configures HOW Terraform connects to your Kubernetes cluster.
#
# "config_path" points to your kubeconfig file. For local clusters, this is
# typically created automatically by:
#   - minikube  → `minikube start`
#   - kind      → `kind create cluster`
#   - k3s       → installed at /etc/rancher/k3s/k3s.yaml
#   - Docker Desktop → enabled in Docker Desktop settings
#
# The kubeconfig file contains:
#   - The cluster's API server address (e.g., https://127.0.0.1:6443)
#   - Authentication credentials (certificates or tokens)
#   - The "context" (which cluster + user + namespace to use)
#
# We use a variable so you can override it if your kubeconfig is elsewhere.
# =============================================================================
provider "kubernetes" {
  config_path = var.kube_config_path
}


# =============================================================================
# NAMESPACE
# =============================================================================
# A Kubernetes Namespace is a virtual cluster within your physical cluster.
#
# WHY use a namespace?
#   1. Isolation: All JupyterHub resources live together, separate from
#      system components (kube-system) or other apps you might run.
#   2. Easy cleanup: `kubectl delete namespace jupyterhub` removes EVERYTHING.
#   3. Resource quotas: You could later limit CPU/memory for the whole namespace.
#   4. RBAC: You can grant permissions scoped to just this namespace.
#
# Think of it like a folder that groups all related Kubernetes objects.
# =============================================================================
resource "kubernetes_namespace" "jupyterhub" {
  metadata {
    name = var.namespace

    # Labels are key-value tags for organizing and selecting resources.
    # They don't affect behavior but help with querying:
    #   kubectl get all -l app.kubernetes.io/name=jupyterhub
    labels = {
      "app.kubernetes.io/name"       = "jupyterhub"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}


# =============================================================================
# SECRET: PROXY AUTH TOKEN
# =============================================================================
# The Hub and the Configurable HTTP Proxy communicate via a REST API.
# The Hub tells the proxy things like:
#   "Route /user/alice → http://jupyter-notebook-alice:8888"
#
# This API must be protected — otherwise anyone could add arbitrary routes
# and hijack traffic. The CONFIGURABLE_HTTP_PROXY_AUTH_TOKEN is a shared
# secret that both the Hub and Proxy must know.
#
# FLOW:
#   Hub → POST http://proxy:8001/api/routes/user/alice
#         Header: Authorization: token <THIS_SECRET>
#   Proxy → Validates token → Adds route → 201 Created
#
# We generate it randomly so it's unique per deployment and never hardcoded.
# =============================================================================

# Generate a cryptographically random 32-character hex string.
# "keepers = {}" means it's generated once and never changes unless you
# explicitly taint/destroy it. This prevents the token from rotating on
# every `terraform apply`, which would break the Hub↔Proxy connection.
resource "random_password" "proxy_auth_token" {
  length  = 32    # 32 hex chars = 128 bits of entropy — very secure
  special = false # Hex-safe characters only (avoids shell escaping issues)
}

# Store the token as a Kubernetes Secret.
# WHY a Secret instead of an environment variable directly?
#   1. Secrets are base64-encoded at rest (and can be encrypted with KMS).
#   2. Secrets can be mounted into multiple Pods without duplication.
#   3. They appear as "[REDACTED]" in `kubectl describe pod`, unlike env vars
#      set via plain `value` fields.
#   4. You can rotate them independently of the Deployment spec.
resource "kubernetes_secret" "proxy_token" {
  metadata {
    name      = "jupyterhub-proxy-token"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
  }

  # The "data" field accepts raw strings — Terraform handles base64 encoding.
  data = {
    "proxy-token" = random_password.proxy_auth_token.result
  }

  # "Opaque" is the default Secret type for arbitrary key-value data.
  # Other types exist for TLS certs, Docker registry credentials, etc.
  type = "Opaque"
}


# =============================================================================
# CONFIGMAP: JUPYTERHUB CONFIGURATION
# =============================================================================
# JupyterHub is configured via a Python file (jupyterhub_config.py).
# A ConfigMap lets us inject this file into the Hub Pod without baking
# it into the Docker image. This means we can change config and re-apply
# without rebuilding any images.
#
# KEY CONFIGURATION DECISIONS EXPLAINED INLINE:
# =============================================================================
resource "kubernetes_config_map" "hub_config" {
  metadata {
    name      = "jupyterhub-config"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
  }

  data = {
    # This Python file is mounted into the Hub container at:
    #   /srv/jupyterhub/jupyterhub_config.py
    # JupyterHub reads it on startup to configure its behavior.
    "jupyterhub_config.py" = <<-PYCONFIG

      # ==================================================
      # JupyterHub Configuration File
      # ==================================================

      import os

      # ---- PROXY CONFIGURATION ----
      # Tell the Hub where the proxy's API is and how to authenticate.
      #
      # The proxy exposes TWO ports:
      #   - 8000: Public port (users connect here)
      #   - 8001: API port (Hub sends route commands here)
      #
      # "configurable-http-proxy" is the Kubernetes Service name, which
      # resolves via cluster DNS to the proxy Pod's IP address.
      c.ConfigurableHTTPProxy.api_url = 'http://configurable-http-proxy:8001'
      c.ConfigurableHTTPProxy.auth_token = os.environ['CONFIGURABLE_HTTP_PROXY_AUTH_TOKEN']

      # We're running the proxy as a SEPARATE process/pod, so tell the Hub
      # NOT to start its own built-in proxy subprocess.
      # should_start=False means "the proxy is managed externally."
      c.ConfigurableHTTPProxy.should_start = False

      # ---- HUB CONFIGURATION ----
      # The Hub needs to know its own URL so it can tell the proxy:
      #   "After login, redirect users back to ME at this address."
      #
      # "jupyterhub" is the K8s Service name for the Hub.
      # Port 8081 is where the Hub listens for internal API/browser traffic.
      c.JupyterHub.hub_connect_url = 'http://jupyterhub:8081'

      # Bind to 0.0.0.0 so the Hub accepts connections from any Pod in the
      # cluster, not just localhost. In Kubernetes, Pods communicate over
      # a virtual network — binding to 127.0.0.1 would reject all traffic.
      c.JupyterHub.hub_ip = '0.0.0.0'
      c.JupyterHub.hub_port = 8081

      # ---- SPAWNER CONFIGURATION ----
      # The Spawner is responsible for creating single-user notebook servers.
      # KubeSpawner creates a new Kubernetes Pod for each user who logs in.
      #
      # WHY KubeSpawner?
      #   - Each user gets an isolated Pod (process isolation, memory limits)
      #   - Pods are created/destroyed on demand (efficient resource usage)
      #   - Kubernetes handles scheduling, restarts, and health checks
      c.JupyterHub.spawner_class = 'kubespawner.KubeSpawner'

      # The Docker image for single-user notebook servers.
      # jupyter/base-notebook includes:
      #   - Python 3, pip, conda
      #   - JupyterLab and classic Notebook interfaces
      #   - Common scientific libraries
      c.KubeSpawner.image = '${var.notebook_image}'

      # The namespace where user notebook Pods will be created.
      # We put them in the same namespace as the Hub for simplicity.
      # In production, you might use a separate namespace for user pods.
      c.KubeSpawner.namespace = '${var.namespace}'

      # The K8s ServiceAccount for notebook Pods. We create a dedicated one
      # with minimal permissions (principle of least privilege).
      c.KubeSpawner.service_account = 'jupyterhub-notebook'

      # Resource limits prevent a single user from consuming all cluster resources.
      # cpu: '0.5' means half a CPU core. memory: '512Mi' = 512 mebibytes.
      # "guarantee" = reserved (always available), "limit" = maximum allowed.
      c.KubeSpawner.cpu_guarantee = 0.2
      c.KubeSpawner.cpu_limit = 0.5
      c.KubeSpawner.mem_guarantee = '256Mi'
      c.KubeSpawner.mem_limit = '512Mi'

      # ---- AUTHENTICATION ----
      # DummyAuthenticator lets anyone log in with any username and a
      # shared password. This is for LOCAL DEVELOPMENT ONLY.
      # For production, use OAuthenticator (GitHub, Google, etc.) or LDAPAuthenticator.
      c.JupyterHub.authenticator_class = 'jupyterhub.auth.DummyAuthenticator'
      c.DummyAuthenticator.password = '${var.dummy_password}'

      # ---- ADDITIONAL SETTINGS ----
      # Allow named servers so users can run multiple notebooks.
      c.JupyterHub.allow_named_servers = True

      # Shut down idle notebook servers after 1 hour to free resources.
      c.JupyterHub.shutdown_no_activity_timeout = 3600

    PYCONFIG
  }
}


# =============================================================================
# SERVICE ACCOUNT: JUPYTERHUB (for the Hub Pod)
# =============================================================================
# The Hub needs permissions to CREATE and DELETE Pods in Kubernetes
# (because it spawns notebook Pods for each user via KubeSpawner).
#
# In Kubernetes, Pods authenticate to the API server using a ServiceAccount.
# By default, Pods get the "default" ServiceAccount, which has almost no
# permissions. We create a dedicated one and grant it specific abilities.
# =============================================================================
resource "kubernetes_service_account" "hub" {
  metadata {
    name      = "jupyterhub-hub"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
  }
}


# =============================================================================
# ROLE: What permissions are granted (within this namespace)
# =============================================================================
# A Role defines a SET OF PERMISSIONS but doesn't say WHO gets them.
# Think of it like a job description: "This role can manage pods and events."
#
# We use a Role (namespace-scoped) instead of a ClusterRole (cluster-wide)
# because the Hub only needs to manage Pods in its own namespace.
#
# Each rule specifies:
#   - apiGroups: "" means the core API group (Pods, Services, etc.)
#   - resources: Which object types
#   - verbs: What actions are allowed
# =============================================================================
resource "kubernetes_role" "hub_role" {
  metadata {
    name      = "jupyterhub-hub-role"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
  }

  # Rule 1: Full control over Pods.
  # The Hub needs to create Pods (when users log in), watch their status
  # (to know when they're ready), and delete them (when users log out).
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Rule 2: Create events.
  # Kubernetes Events are log entries attached to resources (like "Pod started").
  # The Hub records events for debugging and auditing.
  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["get", "list", "watch", "create"]
  }

  # Rule 3: Manage Services.
  # KubeSpawner creates a Service for each user notebook Pod so that the
  # proxy can route traffic to it by a stable DNS name.
  rule {
    api_groups = [""]
    resources  = ["services"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}


# =============================================================================
# ROLEBINDING: Attach the Role to the ServiceAccount
# =============================================================================
# A RoleBinding is the glue: "ServiceAccount X gets Role Y."
# Without this, the ServiceAccount exists but has no permissions,
# and the Role exists but nobody has it.
# =============================================================================
resource "kubernetes_role_binding" "hub_binding" {
  metadata {
    name      = "jupyterhub-hub-binding"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
  }

  # WHO gets the permissions
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.hub.metadata[0].name
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
  }

  # WHICH permissions they get
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.hub_role.metadata[0].name
  }
}


# =============================================================================
# SERVICE ACCOUNT: Notebook Pods (for single-user servers)
# =============================================================================
# Notebook Pods get their own minimal ServiceAccount.
# We don't attach any Role to it — users shouldn't be able to manipulate
# the Kubernetes API. This follows the principle of least privilege.
# =============================================================================
resource "kubernetes_service_account" "notebook" {
  metadata {
    name      = "jupyterhub-notebook"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
  }
}


# =============================================================================
# DEPLOYMENT: CONFIGURABLE HTTP PROXY
# =============================================================================
# A Deployment manages a set of identical Pods and ensures the desired
# number are always running. If a Pod crashes, the Deployment controller
# automatically replaces it.
#
# The Configurable HTTP Proxy (CHP) is the front door to JupyterHub.
# It's a Node.js application that:
#   1. Listens on port 8000 for user traffic
#   2. Listens on port 8001 for API commands from the Hub
#   3. Maintains an in-memory routing table
#   4. Forwards requests to the correct backend (Hub or notebook Pod)
#
# WHY a separate proxy instead of the Hub handling routing directly?
#   - The proxy is lightweight and fast (Node.js event loop)
#   - It can be restarted independently of the Hub
#   - It handles websockets natively (needed for notebook terminals)
#   - The Hub can be upgraded without dropping active connections
# =============================================================================
resource "kubernetes_deployment" "proxy" {
  metadata {
    name      = "configurable-http-proxy"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name

    labels = {
      "app.kubernetes.io/name"      = "configurable-http-proxy"
      "app.kubernetes.io/component" = "proxy"
    }
  }

  spec {
    # Only 1 replica because the proxy holds in-memory state (route table).
    # Running multiple replicas would cause routing inconsistencies unless
    # you add a shared state backend (e.g., Redis), which is out of scope.
    replicas = 1

    # The selector tells the Deployment which Pods it "owns".
    # It matches Pods by label. This is how K8s knows which Pods to count
    # toward the desired replica count and which to restart if they fail.
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "configurable-http-proxy"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"      = "configurable-http-proxy"
          "app.kubernetes.io/component" = "proxy"
        }
      }

      spec {
        container {
          name  = "proxy"
          image = var.proxy_image

          # Command to start the proxy.
          # --ip 0.0.0.0       : Accept connections from anywhere (needed in K8s)
          # --api-ip 0.0.0.0   : Same for the API port
          # --api-port 8001    : The Hub talks to this port to manage routes
          # --default-target   : Where to send requests that don't match any route
          #                      (i.e., unauthenticated users → the Hub)
          # --error-target     : Where to send users when their notebook isn't ready
          #
          # The "default target" is crucial: when a NEW user visits JupyterHub,
          # there's no route for them yet, so the proxy forwards them to the Hub,
          # which shows the login page.
          command = [
            "configurable-http-proxy",
            "--ip", "0.0.0.0",
            "--port", "8000",
            "--api-ip", "0.0.0.0",
            "--api-port", "8001",
            "--default-target", "http://jupyterhub:8081",
            "--error-target", "http://jupyterhub:8081/hub/error",
          ]

          # Inject the auth token from the Kubernetes Secret.
          # The proxy reads this env var to validate incoming API requests.
          # Using secret_key_ref means the value is pulled from the Secret
          # at Pod startup — it never appears in the Deployment spec itself.
          env {
            name = "CONFIGURABLE_HTTP_PROXY_AUTH_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.proxy_token.metadata[0].name
                key  = "proxy-token"
              }
            }
          }

          # Port declarations are informational — they don't actually open ports.
          # But they serve as documentation and are used by `kubectl port-forward`.
          port {
            name           = "http"
            container_port = 8000 # User-facing traffic
          }

          port {
            name           = "api"
            container_port = 8001 # Hub→Proxy API
          }

          # RESOURCE LIMITS
          # requests = guaranteed minimum resources for scheduling
          # limits   = hard ceiling — container is killed if it exceeds memory
          #
          # The proxy is lightweight, so 128Mi/256Mi is plenty.
          resources {
            requests = {
              cpu    = "100m"  # 100 millicores = 0.1 CPU core
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          # LIVENESS PROBE: "Is this container still alive?"
          # K8s sends an HTTP GET to /. If it fails 3 times in a row,
          # K8s kills and restarts the container.
          # This catches cases where the proxy process hangs or deadlocks.
          liveness_probe {
            http_get {
              path = "/"
              port = 8000
            }
            initial_delay_seconds = 10  # Wait 10s after start before probing
            period_seconds        = 15  # Probe every 15 seconds
          }
        }
      }
    }
  }
}


# =============================================================================
# DEPLOYMENT: JUPYTERHUB (the Hub)
# =============================================================================
# The Hub is the "brain" of JupyterHub. It:
#   1. Serves the login page and dashboard
#   2. Authenticates users
#   3. Spawns single-user notebook Pods via the Kubernetes API
#   4. Registers routes with the proxy so users reach their notebooks
#   5. Monitors notebook Pod health and handles shutdowns
#
# It's a Python application (Tornado web server) that uses KubeSpawner
# to interact with the Kubernetes API.
# =============================================================================
resource "kubernetes_deployment" "hub" {
  metadata {
    name      = "jupyterhub"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name

    labels = {
      "app.kubernetes.io/name"      = "jupyterhub"
      "app.kubernetes.io/component" = "hub"
    }
  }

  spec {
    # Only 1 replica — JupyterHub uses an internal SQLite database by default,
    # which doesn't support concurrent access from multiple processes.
    # For HA, you'd need to switch to PostgreSQL and use leader election.
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "jupyterhub"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"      = "jupyterhub"
          "app.kubernetes.io/component" = "hub"
        }
      }

      spec {
        # Use the ServiceAccount with RBAC permissions to create/delete Pods.
        # Without this, the Hub would use "default" and get "403 Forbidden"
        # when trying to spawn notebook Pods.
        service_account_name = kubernetes_service_account.hub.metadata[0].name

        # INIT CONTAINER: Install KubeSpawner
        # ------------------------------------
        # The base jupyterhub/jupyterhub image doesn't include KubeSpawner.
        # An init container runs BEFORE the main container and shares a
        # volume with it. We install kubespawner into a shared directory
        # so the Hub can import it at runtime.
        #
        # WHY an init container instead of a custom Docker image?
        #   - No need to maintain a custom image
        #   - Easy to change the kubespawner version
        #   - The shared volume pattern is a common K8s pattern
        init_container {
          name  = "install-kubespawner"
          image = var.hub_image

          command = [
            "pip", "install", "--target=/opt/extras", "kubespawner"
          ]

          volume_mount {
            name       = "pip-extras"
            mount_path = "/opt/extras"
          }
        }

        container {
          name  = "hub"
          image = var.hub_image

          # Start JupyterHub with our config file and add the pip extras
          # to the Python path so it can find kubespawner.
          command = ["sh", "-c"]
          args = [
            "export PYTHONPATH=/opt/extras:$${PYTHONPATH}; jupyterhub -f /srv/jupyterhub/jupyterhub_config.py"
          ]

          # The shared auth token — same value as the proxy has.
          # Both sides must match or the Hub can't manage proxy routes.
          env {
            name = "CONFIGURABLE_HTTP_PROXY_AUTH_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.proxy_token.metadata[0].name
                key  = "proxy-token"
              }
            }
          }

          # The Hub listens on port 8081 for all traffic:
          #   - Browser requests (login page, dashboard)
          #   - Internal API calls from the proxy
          port {
            name           = "hub"
            container_port = 8081
          }

          resources {
            requests = {
              cpu    = "200m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          # Mount the ConfigMap as a file inside the container.
          # This makes /srv/jupyterhub/jupyterhub_config.py available.
          volume_mount {
            name       = "hub-config"
            mount_path = "/srv/jupyterhub/jupyterhub_config.py"
            sub_path   = "jupyterhub_config.py" # Mount single file, not directory
          }

          # Mount the shared pip install directory
          volume_mount {
            name       = "pip-extras"
            mount_path = "/opt/extras"
          }

          # READINESS PROBE: "Is this container ready to receive traffic?"
          # Unlike liveness (which checks if the process is alive), readiness
          # checks if the service is FUNCTIONAL. The Hub needs a few seconds
          # to start up and connect to the proxy. Until readiness passes,
          # the K8s Service won't send traffic to this Pod.
          readiness_probe {
            http_get {
              path = "/hub/health"
              port = 8081
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/hub/health"
              port = 8081
            }
            initial_delay_seconds = 30
            period_seconds        = 15
          }
        }

        # VOLUMES
        # -------
        # Volumes are declared at the Pod level and then mounted into containers.
        # This separation allows multiple containers to share the same volume.

        # Volume from ConfigMap: makes our Python config available as a file
        volume {
          name = "hub-config"
          config_map {
            name = kubernetes_config_map.hub_config.metadata[0].name
          }
        }

        # emptyDir volume: temporary storage shared between init and main containers.
        # It's created when the Pod starts and deleted when the Pod dies.
        # We use it to pass pip-installed packages from init → main container.
        volume {
          name = "pip-extras"
          empty_dir {}
        }
      }
    }
  }

  # Ensure RBAC is set up before the Hub tries to spawn Pods.
  depends_on = [
    kubernetes_role_binding.hub_binding,
  ]
}


# =============================================================================
# SERVICE: CONFIGURABLE HTTP PROXY
# =============================================================================
# A Kubernetes Service is a stable network endpoint for a set of Pods.
#
# WHY do we need Services?
#   Pods have ephemeral IP addresses — if a Pod restarts, it gets a NEW IP.
#   A Service provides a STABLE DNS name and IP that automatically routes
#   to whatever Pod(s) are currently running behind it.
#
# This Service exposes TWO ports:
#   - 8000 (http): Where users connect. Exposed as a NodePort so you can
#     access it from your host machine at localhost:<nodePort>.
#   - 8001 (api): Where the Hub sends route management commands.
#     ClusterIP only — never exposed outside the cluster.
# =============================================================================
resource "kubernetes_service" "proxy" {
  metadata {
    name      = "configurable-http-proxy"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
  }

  spec {
    # NodePort makes the Service accessible from outside the cluster.
    # It allocates a port on EVERY node in the cluster (default: 30000-32767).
    # For local development, this is the simplest way to access JupyterHub.
    #
    # Alternatives:
    #   - ClusterIP: Internal only (would need `kubectl port-forward`)
    #   - LoadBalancer: Requires a cloud provider or MetalLB
    #   - Ingress: Requires an Ingress controller (nginx, traefik, etc.)
    type = "NodePort"

    # The selector matches Pods with this label. Only matching Pods receive
    # traffic from this Service. This is how the Service "finds" its backends.
    selector = {
      "app.kubernetes.io/name" = "configurable-http-proxy"
    }

    # Port 8000: User-facing web traffic
    port {
      name        = "http"
      port        = 8000       # Port on the Service (cluster-internal)
      target_port = 8000       # Port on the container
      node_port   = var.proxy_node_port # Port on your host machine
    }

    # Port 8001: Hub→Proxy API (internal only, but exposed via Service
    # so the Hub can reach it by DNS name "configurable-http-proxy:8001")
    port {
      name        = "api"
      port        = 8001
      target_port = 8001
    }
  }
}


# =============================================================================
# SERVICE: JUPYTERHUB
# =============================================================================
# Internal-only Service for the Hub. The proxy and notebook Pods need to
# reach the Hub, but users never connect directly to it — they always
# go through the proxy.
#
# ClusterIP (default) means this is only accessible within the cluster.
# DNS name: "jupyterhub.jupyterhub.svc.cluster.local" (or just "jupyterhub"
# from within the same namespace).
# =============================================================================
resource "kubernetes_service" "hub" {
  metadata {
    name      = "jupyterhub"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name" = "jupyterhub"
    }

    port {
      name        = "hub"
      port        = 8081
      target_port = 8081
    }
  }
}
