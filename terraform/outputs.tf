output "namespace" {
  description = "Kubernetes namespace where JupyterHub is deployed"
  value       = kubernetes_namespace.jupyterhub.metadata[0].name
}

output "hub_service_name" {
  description = "Name of the Hub ClusterIP service"
  value       = kubernetes_service.hub.metadata[0].name
}

output "proxy_service_name" {
  description = "Name of the proxy service"
  value       = kubernetes_service.proxy.metadata[0].name
}

output "proxy_service_type" {
  description = "Type of the proxy Kubernetes Service"
  value       = var.proxy_service_type
}

output "access_instructions" {
  description = "How to access JupyterHub"
  value       = var.proxy_service_type == "NodePort" ? "Access JupyterHub at http://localhost:${var.proxy_host_port}" : var.proxy_service_type == "ClusterIP" ? "Run: kubectl port-forward -n ${var.namespace} svc/${kubernetes_service.proxy.metadata[0].name} ${var.proxy_host_port}:80" : "Access the external IP/port of the '${kubernetes_service.proxy.metadata[0].name}' service in namespace '${var.namespace}'."
}

output "kind_cluster_name" {
  description = "Name of the Kind cluster"
  value       = kind_cluster.jupyterhub.name
}

output "proxy_host_port" {
  description = "Host port mapped to the proxy NodePort"
  value       = var.proxy_host_port
}
