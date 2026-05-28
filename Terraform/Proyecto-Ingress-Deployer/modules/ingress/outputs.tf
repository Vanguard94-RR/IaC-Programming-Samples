output "static_ip_address" {
  description = "The reserved static IP address"
  value       = google_compute_global_address.ingress.address
}

output "ingress_name" {
  description = "Ingress resource name"
  value       = try(kubernetes_manifest.ingress.manifest.metadata.name, kubernetes_manifest.ingress.object.metadata.name, null)
}
