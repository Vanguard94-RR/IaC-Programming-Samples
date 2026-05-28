output "static_ip_address" {
  description = "Static IP address assigned to the ingress load balancer"
  value       = module.ingress.static_ip_address
}

output "namespace" {
  description = "Kubernetes namespace where the ingress is deployed"
  value       = var.namespace
}
