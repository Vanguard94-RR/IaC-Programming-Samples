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

  timeouts {
    delete = "30m"
  }

  field_manager {
    force_conflicts = true
  }

  depends_on = [
    kubernetes_namespace_v1.ingress,
    kubernetes_manifest.companion,
    google_compute_global_address.ingress,
  ]
}

# Destroy-time finalizer cleanup.
# GKE adds kubernetes.io/ingress finalizer — the LB controller won't honor
# DELETE until the load balancer is deprovisioned. This provisioner patches
# the finalizer out before TF issues DELETE, unblocking terraform destroy.
#
# Dependency ordering (TF destroys dependents first):
#   null_resource depends_on ingress → null_resource destroyed first (runs
#   kubectl patch) → kubernetes_manifest.ingress deleted cleanly.
resource "null_resource" "ingress_finalizer_cleanup" {
  triggers = {
    ingress_name = var.ingress_name
    namespace    = var.namespace
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    environment = {
      INGRESS_NAME = self.triggers.ingress_name
      NAMESPACE    = self.triggers.namespace
    }
    command = <<-EOT
      kubectl patch ingress "$INGRESS_NAME" \
        -n "$NAMESPACE" \
        -p '{"metadata":{"finalizers":[]}}' \
        --type=merge 2>/dev/null || true
    EOT
  }

  depends_on = [kubernetes_manifest.ingress]
}

# Cloud Armor policy attachment.
# Runs after ingress is applied — GKE creates backend services dynamically,
# so attachment must happen post-provisioning. Registered in TF state so
# drift (manually detached policy) is visible on next plan.
resource "null_resource" "cloud_armor" {
  triggers = {
    ingress_manifest = sha256(file(var.ingress_yaml))
    project_id       = var.project_id
    namespace        = var.namespace
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "'${path.module}/../../lib/cloud_armor.sh' '${var.project_id}' '${var.namespace}'"
  }

  depends_on = [
    kubernetes_manifest.ingress,
    null_resource.ingress_finalizer_cleanup,
  ]
}
