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

variable "frontendconfig_yaml" {
  description = "Absolute path to FrontendConfig YAML manifest. Empty string skips FrontendConfig."
  type        = string
  default     = ""
}
