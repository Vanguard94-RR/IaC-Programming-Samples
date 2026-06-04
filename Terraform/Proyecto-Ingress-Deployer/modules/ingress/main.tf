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

# 3. Companion IaC resources — BackendConfig, FrontendConfig, ManagedCertificate, etc.
#    Extracted from source YAML by deploy.sh into manifests/<project>/companions/.
resource "kubernetes_manifest" "companion" {
  for_each = var.companion_manifests
  manifest = yamldecode(file(each.value))

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
    kubernetes_manifest.companion,
    google_compute_global_address.ingress,
  ]
}
