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
  description = "Absolute path to ingress YAML manifest (derived from manifests_dir in root module)."
  type        = string
}

variable "ingress_name" {
  description = "Name of the Ingress resource — used by finalizer cleanup provisioner destroy trigger"
  type        = string

  validation {
    condition     = var.ingress_name != null && var.ingress_name != ""
    error_message = "ingress_name could not be read from ingress.yaml metadata.name — check YAML has metadata.name set."
  }
}

variable "companion_manifests" {
  description = "Map of Kind-namespace-name => absolute file path for IaC companion resources (BackendConfig, FrontendConfig, ManagedCertificate, etc.)."
  type        = map(string)
  default     = {}
}
