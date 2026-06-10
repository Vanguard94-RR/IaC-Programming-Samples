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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
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
  # manifests_work_dir override: deploy.sh sets this to a TICKET_DIR working copy.
  # Fallback to committed manifests when running terraform directly.
  manifests_dir  = var.manifests_work_dir != "" ? var.manifests_work_dir : "${path.module}/../manifests/${var.project_id}"
  companions_dir = "${local.manifests_dir}/companions"

  # Extract ingress name from YAML for null_resource.ingress_finalizer_cleanup trigger.
  _ingress_yaml_content = yamldecode(file("${local.manifests_dir}/ingress.yaml"))
  ingress_name          = try(local._ingress_yaml_content.metadata.name, "")

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
  ingress_name        = local.ingress_name
  companion_manifests = local.companion_manifests
}
