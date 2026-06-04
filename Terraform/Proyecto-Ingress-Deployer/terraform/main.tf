terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.7, < 3.0"
    }
  }

  backend "gcs" {}
}

provider "google" {
  project = var.project_id
}

data "google_client_config" "default" {}

data "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.cluster_location
  project  = var.project_id
}

provider "kubernetes" {
  host  = "https://${data.google_container_cluster.primary.endpoint}"
  token = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(
    data.google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  )
}

locals {
  manifests_dir  = "${path.module}/../manifests/${var.project_id}"
  companions_dir = "${local.manifests_dir}/companions"

  # Build companion_manifests map from companions/*.yaml files.
  # Key: "Kind/namespace/name" (read from YAML content, not filename)
  # Value: absolute path to companion YAML file
  # try() handles the case where companions/ dir doesn't exist yet.
  _companion_yaml_files = try(fileset(local.companions_dir, "*.yaml"), toset([]))

  _companion_data = {
    for f in local._companion_yaml_files :
    f => yamldecode(file("${local.companions_dir}/${f}"))
  }

  companion_manifests = {
    for f, d in local._companion_data :
    "${d.kind}/${d.metadata.namespace}/${d.metadata.name}"
    => "${local.companions_dir}/${f}"
  }
}

module "ingress" {
  source = "../modules/ingress"

  project_id          = var.project_id
  namespace           = var.namespace
  static_ip_name      = var.static_ip_name
  ingress_yaml        = "${local.manifests_dir}/ingress.yaml"
  companion_manifests = local.companion_manifests
}
