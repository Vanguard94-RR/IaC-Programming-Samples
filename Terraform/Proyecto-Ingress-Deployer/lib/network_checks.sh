#!/usr/bin/env bash
# Requires: lib/ui.sh sourced first (ok, warn, error, info functions)

# check_ip_conflicts <project_id> <static_ip_name> <ingress_name>
# Pre-flight: detect forwarding rules that would block GKE LB from using the static IP.
# Classifies rules and offers to delete them. Exits 1 if conflicts remain unresolved.
check_ip_conflicts() {
  local project_id="$1" static_ip_name="$2" ingress_name="$3"

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

    if [[ "$target_base" =~ ^k8s2- ]]; then
      # GKE-managed target proxy — check ownership via target name
      if echo "$target_base" | grep -q "$ingress_name"; then
        warn "GKE orphan rule '$rule' (target: $target_base) — incomplete LB stack from previous deploy"
        if [[ "${CI:-false}" == "true" ]]; then
          error "CI mode: delete manually → gcloud compute forwarding-rules delete $rule --global --project=$project_id"
          has_conflict=true
        else
          local _confirm
          read -rp "Delete orphan GKE rule '$rule'? [y/N]: " _confirm
          if [[ "${_confirm,,}" == "y" ]]; then
            gcloud compute forwarding-rules delete "$rule" --global --project="$project_id" -q
            ok "Deleted orphan GKE rule: $rule"
          else
            error "Conflict not resolved: $rule still uses $ip"
            has_conflict=true
          fi
        fi
      else
        # GKE-managed target — belongs to the current or a live ingress, not a conflict
        info "GKE-managed rule '$rule' (target: $target_base) — owned by active ingress, skipping"
      fi
      continue
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
