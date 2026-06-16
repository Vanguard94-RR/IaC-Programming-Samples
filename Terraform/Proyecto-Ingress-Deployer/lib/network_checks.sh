#!/usr/bin/env bash
# Requires: lib/ui.sh sourced first (ok, warn, error, info functions)

# check_ip_conflicts <project_id> <static_ip_name>
# Pre-flight: detect forwarding rules that would block GKE LB from using the static IP.
# Classifies rules and offers to delete them. Exits 1 if conflicts remain unresolved.
check_ip_conflicts() {
  local project_id="$1" static_ip_name="$2"

  local ip
  ip=$(gcloud compute addresses describe "$static_ip_name" \
    --global --project="$project_id" --format="value(address)" 2>/dev/null || true)
  [[ -z "$ip" ]] && return 0

  local rules
  rules=$(gcloud compute forwarding-rules list \
    --project="$project_id" \
    --filter="IPAddress=$ip" \
    --format="value(name)" 2>/dev/null || true)
  [[ -z "$rules" ]] && return 0

  info "Found forwarding rules using $ip — checking for conflicts..."
  local has_conflict=false

  while IFS= read -r rule; do
    [[ -z "$rule" ]] && continue

    local target target_base
    target=$(gcloud compute forwarding-rules describe "$rule" --global \
      --project="$project_id" --format="value(target)" 2>/dev/null || true)
    target_base="${target##*/}"

    if [[ "$rule" =~ ^k8s2- ]]; then
      # GKE-managed rule (k8s2-* name). Orphan = target proxy no longer exists.
      local _tp_exists
      _tp_exists=$(gcloud compute target-https-proxies describe "$target_base" \
        --global --project="$project_id" --format="value(name)" 2>/dev/null || \
        gcloud compute target-http-proxies describe "$target_base" \
        --global --project="$project_id" --format="value(name)" 2>/dev/null || true)
      if [[ -z "$_tp_exists" ]]; then
        warn "GKE orphan rule '$rule' (target proxy missing: $target_base) — deleting stale fragment"
        gcloud compute forwarding-rules delete "$rule" --global --project="$project_id" -q
        ok "Deleted orphan GKE rule: $rule"
      else
        info "GKE-managed rule '$rule' (target: $target_base) — active LB stack, skipping"
      fi
      continue
    fi

    # Non-k8s2 rule pointing at a GKE resource = manual rule hijacking GKE IP.
    # Treat as conflict (same path as fully manual rules below).
    if [[ "$target_base" =~ ^k8s2- ]]; then
      warn "Manual rule '$rule' targets GKE resource '$target_base' — occupying $ip"
    fi

    warn "Manual forwarding rule '$rule' uses $ip — will conflict with GKE LB"
    if [[ "${CI:-false}" == "true" ]]; then
      error "CI mode: delete manually → gcloud compute forwarding-rules delete $rule --global --project=$project_id"
      has_conflict=true
    else
      local _confirm
      read -rp "Delete manual rule '$rule'? [y/N]: " _confirm
      if [[ "${_confirm,,}" == "y" ]]; then
        gcloud compute forwarding-rules delete "$rule" --global --project="$project_id" -q
        ok "Deleted manual rule: $rule"
      else
        error "Conflict not resolved: $rule still uses $ip"
        has_conflict=true
      fi
    fi

  done <<< "$rules"

  if [[ "$has_conflict" == "true" ]]; then
    error "IP conflict check failed — resolve conflicts before proceeding"
    return 1
  fi

  ok "IP conflict check passed: $ip is available"
}
