# =============================================================================
# OUTPUTS: Values displayed after `terraform apply`
# =============================================================================
# Outputs are like "return values" for your Terraform configuration.
# After deployment, Terraform prints these so you know how to access
# your JupyterHub instance without hunting through `kubectl` output.
# =============================================================================

output "jupyterhub_url" {
  description = "URL to access JupyterHub in your browser"
  value       = "http://localhost:${var.proxy_node_port}"
}

output "namespace" {
  description = "Kubernetes namespace where JupyterHub is deployed"
  value       = kubernetes_namespace.jupyterhub.metadata[0].name
}

output "login_instructions" {
  description = "How to log in to JupyterHub"
  value       = <<-EOT
    
    ========================================
    JupyterHub is deployed!
    ========================================
    
    URL:      http://localhost:${var.proxy_node_port}
    Username: (any username you want — it creates a session for that name)
    Password: (the dummy_password you configured)
    
    USEFUL COMMANDS:
      kubectl get pods -n ${var.namespace}          # Check pod status
      kubectl logs -n ${var.namespace} -l app.kubernetes.io/name=jupyterhub  # Hub logs
      kubectl logs -n ${var.namespace} -l app.kubernetes.io/name=configurable-http-proxy  # Proxy logs

    TO TEAR DOWN:
      terraform destroy
    
  EOT
}

output "proxy_auth_token_note" {
  description = "Note about the proxy auth token"
  value       = "Proxy auth token is stored in K8s Secret 'jupyterhub-proxy-token' in namespace '${var.namespace}'"
}
