output "static_ip_address" {
  description = "The reserved static IP address. Empty string when static_ip_name is not set."
  value       = var.static_ip_name != "" ? google_compute_global_address.ingress[0].address : ""
}

output "ingress_name" {
  description = "Ingress resource name"
  value       = try(kubernetes_manifest.ingress.manifest.metadata.name, kubernetes_manifest.ingress.object.metadata.name, null)
}
