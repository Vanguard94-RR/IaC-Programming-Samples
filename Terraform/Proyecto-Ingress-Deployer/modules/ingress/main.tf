# 1. Namespace — created if missing; ignore label/annotation drift from other tools
resource "kubernetes_namespace_v1" "ingress" {
  metadata {
    name = var.namespace
  }

  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

# 2. Static IP — must exist in GCP before GKE's ingress controller processes the Ingress.
#    GKE reads kubernetes.io/ingress.global-static-ip-name at LB provisioning time.
#    If the address does not exist yet, the LB is provisioned with an ephemeral IP.
resource "google_compute_global_address" "ingress" {
  name    = var.static_ip_name
  project = var.project_id
}

# 3. FrontendConfig — referenced by ingress annotation networking.gke.io/v1.FrontendConfig
resource "kubernetes_manifest" "frontendconfig" {
  count    = var.frontendconfig_yaml != "" ? 1 : 0
  manifest = yamldecode(file(var.frontendconfig_yaml))

  field_manager {
    force_conflicts = true
  }

  depends_on = [kubernetes_namespace_v1.ingress]
}

# 4. Ingress — applied after all dependencies exist
resource "kubernetes_manifest" "ingress" {
  manifest = yamldecode(file(var.ingress_yaml))

  field_manager {
    force_conflicts = true
  }

  depends_on = [
    kubernetes_namespace_v1.ingress,
    google_compute_global_address.ingress,
    kubernetes_manifest.frontendconfig,
  ]
}
