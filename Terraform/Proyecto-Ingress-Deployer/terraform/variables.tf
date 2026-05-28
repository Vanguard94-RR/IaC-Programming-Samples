variable "project_id" {
  description = "Target GCP project ID (e.g. gnp-plus-qa)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID."
  }
}

variable "cluster_name" {
  description = "GKE cluster name in the target project (e.g. gke-gnp-plus-qa)"
  type        = string
}

variable "cluster_location" {
  description = "GKE cluster zone (e.g. us-central1-a) or region (e.g. us-central1)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace — created by Terraform if missing"
  type        = string
}

variable "static_ip_name" {
  description = "Name for google_compute_global_address. Must match ingress annotation kubernetes.io/ingress.global-static-ip-name"
  type        = string
}
