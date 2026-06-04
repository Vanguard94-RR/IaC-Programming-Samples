variable "project_id" {
  description = "Target GCP project ID"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to create if missing"
  type        = string
}

variable "static_ip_name" {
  description = "google_compute_global_address name. Empty string = ephemeral IP (no GCP address created)."
  type        = string
  default     = ""
}

variable "ingress_yaml" {
  description = "Absolute path to ingress YAML manifest (set by root module from path.module)"
  type        = string
}

variable "companion_manifests" {
  description = "Map of Kind-namespace-name => absolute file path for IaC companion resources (BackendConfig, FrontendConfig, ManagedCertificate, etc.)."
  type        = map(string)
  default     = {}
}
