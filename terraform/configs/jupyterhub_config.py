import os

# ---------------------------------------------------------------------------
# JupyterHub base config
# ---------------------------------------------------------------------------
c.JupyterHub.bind_url = "http://:8081/hub"

# The proxy lives in a separate pod; tell the Hub where to find it.
c.ConfigurableHTTPProxy.api_url = "http://jupyterhub-proxy-api:8001"
c.ConfigurableHTTPProxy.should_start = False

# ---------------------------------------------------------------------------
# KubeSpawner
# ---------------------------------------------------------------------------
c.JupyterHub.spawner_class = "kubespawner.KubeSpawner"

c.KubeSpawner.image = "${singleuser_image}:${singleuser_image_tag}"
c.KubeSpawner.namespace = "${namespace}"
c.KubeSpawner.service_account = "default"

c.KubeSpawner.start_timeout = 300
c.KubeSpawner.http_timeout = 120

c.KubeSpawner.cpu_limit = 1.0
c.KubeSpawner.cpu_guarantee = 0.25
c.KubeSpawner.mem_limit = "1G"
c.KubeSpawner.mem_guarantee = "256M"

# Storage — each user gets a 1 Gi PVC
c.KubeSpawner.storage_pvc_ensure = True
c.KubeSpawner.storage_capacity = "1Gi"
c.KubeSpawner.storage_access_modes = ["ReadWriteOnce"]

# Private registry — pull secret for user notebook pods
%{ if image_pull_secret_name != "" ~}
c.KubeSpawner.image_pull_secrets = ["${image_pull_secret_name}"]
%{ endif ~}

# ---------------------------------------------------------------------------
# Authenticator — dummy auth allows any password (replace for production)
# ---------------------------------------------------------------------------
c.JupyterHub.authenticator_class = "dummy"

# ---------------------------------------------------------------------------
# Proxy auth token (injected via environment variable)
# ---------------------------------------------------------------------------
c.ConfigurableHTTPProxy.auth_token = os.environ.get("CONFIGPROXY_AUTH_TOKEN", "")
