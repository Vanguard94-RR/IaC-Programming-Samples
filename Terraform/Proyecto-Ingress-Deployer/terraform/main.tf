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
  manifests_dir       = "${path.module}/../manifests/${var.project_id}"
  frontendconfig_yaml = "${local.manifests_dir}/frontendconfig.yaml"
}

module "ingress" {
  source = "../modules/ingress"

  project_id          = var.project_id
  namespace           = var.namespace
  static_ip_name      = var.static_ip_name
  ingress_yaml        = "${local.manifests_dir}/ingress.yaml"
  frontendconfig_yaml = fileexists(local.frontendconfig_yaml) ? local.frontendconfig_yaml : ""
}
