output "static_ip_address" {
  description = "Reserved static IP address, or empty string when ephemeral IP mode is active."
  value       = module.ingress.static_ip_address
}

output "namespace" {
  description = "Kubernetes namespace where the ingress is deployed"
  value       = var.namespace
}
