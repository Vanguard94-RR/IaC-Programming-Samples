# 1. Namespace — created if missing; ignore label/annotation drift from other tools
resource "kubernetes_namespace_v1" "ingress" {
  metadata {
    name = var.namespace
  }

  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

# 2. Static IP — optional. Empty static_ip_name = GKE provisions an ephemeral IP.
#    When set, must exist before ingress controller processes the Ingress.
resource "google_compute_global_address" "ingress" {
  count   = var.static_ip_name != "" ? 1 : 0
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
    kubernetes_manifest.frontendconfig,
    google_compute_global_address.ingress,
  ]
}
