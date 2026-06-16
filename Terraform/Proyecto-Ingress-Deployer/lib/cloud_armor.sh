#!/usr/bin/env bash
# Cloud Armor policy attachment for ingress backend services

attach_cloud_armor() {
  local project_id="$1" namespace="$2" ingress_name="$3"

  if ! command -v gcloud &>/dev/null; then
    warn "gcloud not available — skipping Cloud Armor"
    return 0
  fi

  if ! command -v jq &>/dev/null; then
    warn "jq not available — skipping Cloud Armor"
    return 0
  fi

  step "Cloud Armor policy attachment"

  # Auto-detect policy in project
  local policy
  policy=$(gcloud compute security-policies list \
    --project="$project_id" --format="value(name)" --limit=1 2>/dev/null || true)

  if [[ -z "$policy" ]]; then
    warn "No Cloud Armor security policy found in $project_id — skipping"
    return 0
  fi
  info "Policy detected: $policy"

  # Discover backends from ingress annotation (works on both k8s1- and k8s2- clusters)
  local annotation_json
  annotation_json=$(kubectl get ingress "$ingress_name" -n "$namespace" \
    -o jsonpath='{.metadata.annotations.ingress\.kubernetes\.io/backends}' \
    2>/dev/null || true)

  if [[ -z "$annotation_json" ]]; then
    warn "ingress.kubernetes.io/backends annotation not found on $ingress_name — LB may not be provisioned yet"
    return 0
  fi

  local backends
  backends=$(printf '%s' "$annotation_json" | jq -r 'keys[]' 2>/dev/null || true)

  if [[ -z "$backends" ]]; then
    warn "No backend services found in annotation for $ingress_name — skipping Cloud Armor"
    return 0
  fi

  local attached=0 skipped=0 already=0

  while IFS= read -r backend; do
    [[ -z "$backend" ]] && continue

    local current
    current=$(gcloud compute backend-services describe "$backend" --global \
      --project="$project_id" --format="value(securityPolicy)" 2>/dev/null || true)

    if printf '%s' "$current" | grep -qF "/$policy"; then
      info "  ● $backend [already attached]"
      already=$((already + 1))
      continue
    fi

    if gcloud compute backend-services update "$backend" \
         --security-policy "$policy" --global \
         --project="$project_id" &>/dev/null; then
      ok "  + $backend [attached]"
      attached=$((attached + 1))
    else
      warn "  ✖ $backend [attach failed]"
      skipped=$((skipped + 1))
    fi
  done <<< "$backends"

  ok "Cloud Armor done — attached: $attached, already set: $already, failed: $skipped"
}

# Entry point when invoked directly by Terraform local-exec provisioner
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  . "${_SCRIPT_DIR}/ui.sh"
  attach_cloud_armor "$1" "$2" "$3"
fi
