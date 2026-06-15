#!/usr/bin/env bash
# Requires: lib/ui.sh sourced first (ok, warn, error, info functions)

# Source UI functions if not already sourced
if ! declare -f error >/dev/null 2>&1; then
  # Helper: Find ui.sh by searching from current script location
  _find_ui_sh() {
      local search_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || search_dir="$(pwd)"
      if [[ -f "$search_dir/ui.sh" ]]; then
          echo "$search_dir/ui.sh"
      elif [[ -f "$(dirname "$search_dir")/ui.sh" ]]; then
          echo "$(dirname "$search_dir")/ui.sh"
      elif [[ -f "$(dirname "$search_dir")/../lib/ui.sh" ]]; then
          echo "$(dirname "$search_dir")/../lib/ui.sh"
      fi
  }
  UI_SH_PATH="$(_find_ui_sh)" || { echo "ERROR: Could not find ui.sh" >&2; exit 1; }
  # shellcheck source=./ui.sh
  . "$UI_SH_PATH"
fi

# normalize_static_ip_name <value>
# Converts ephemeral keyword variants to "". Passes other values through unchanged.
normalize_static_ip_name() {
  local val="${1:-}"
  case "${val,,}" in
    ephemeral|efimera|efim|eph) echo "" ;;
    *) echo "$val" ;;
  esac
}

# validate_static_ip <project_id> <ip_name>
# Checks IP existence in GCP. If missing: prompts to create (interactive) or warns (CI).
# Sets global STATIC_IP_NAME if user re-enters a different name.
validate_static_ip() {
  local project_id="$1" ip_name="$2"
  [[ -z "$ip_name" ]] && return 0

  local addr
  addr=$(gcloud compute addresses describe "$ip_name" \
    --global --project="$project_id" --format="value(address)" 2>/dev/null || true)

  if [[ -z "$addr" ]]; then
    if [[ "${CI:-false}" == "true" ]]; then
      info "Static IP '$ip_name' not found in GCP — will be created by Terraform"
      return 0
    fi
    local _confirm
    read -rp "Static IP '$ip_name' not found in GCP. Create new? [y/N]: " _confirm
    if [[ "${_confirm,,}" != "y" ]]; then
      local _new_name
      while true; do
        read -rp "Enter a different IP name (or 'ephemeral' to skip): " _new_name
        STATIC_IP_NAME=$(normalize_static_ip_name "${_new_name:-}")
        if [[ -z "$STATIC_IP_NAME" ]]; then
          info "No static IP — GKE will assign an ephemeral IP"
          return 0
        fi
        addr=$(gcloud compute addresses describe "$STATIC_IP_NAME" \
          --global --project="$project_id" --format="value(address)" 2>/dev/null || true)
        if [[ -n "$addr" ]]; then
          break
        fi
        warn "Static IP '$STATIC_IP_NAME' not found in GCP — try again or enter 'ephemeral'"
      done
      ip_name="$STATIC_IP_NAME"
    else
      info "Will create static IP '$ip_name' via Terraform"
      return 0
    fi
  fi

  local users
  users=$(gcloud compute forwarding-rules list \
    --project="$project_id" --filter="IPAddress=$addr" \
    --format="value(name)" 2>/dev/null || true)

  if [[ -n "$users" ]]; then
    info "Static IP '$ip_name' exists: $addr (in use — conflict check will run later)"
  else
    ok "Static IP '$ip_name' exists: $addr (free)"
  fi
}

# detect_ingress_cluster <project_id> <ingress_name>
# For each cluster in project, checks if ingress exists. Only called when >=2 clusters.
# Outputs "cluster_name location namespace" lines for matches. Silent if none found.
detect_ingress_cluster() {
  local project_id="$1" ingress_name="$2"
  [[ -z "$ingress_name" ]] && return 0

  local clusters
  mapfile -t clusters < <(gcloud container clusters list \
    --project="$project_id" --format="value(name,location)" 2>/dev/null || true)
  [[ ${#clusters[@]} -le 1 ]] && return 0

  local _saved_ctx
  _saved_ctx=$(kubectl config current-context 2>/dev/null || true)

  local c cname cloc ns
  for c in "${clusters[@]}"; do
    [[ -z "$c" ]] && continue
    read -r cname cloc <<< "$c"
    _get_credentials "$project_id" "$cname" "$cloc" &>/dev/null 2>&1 || continue
    ns=$(kubectl get ingress "$ingress_name" -A \
      --no-headers -o custom-columns='NS:.metadata.namespace' 2>/dev/null | head -1 || true)
    [[ -n "$ns" ]] && printf "%s %s %s\n" "$cname" "$cloc" "$ns"
  done

  if [[ -n "$_saved_ctx" ]]; then
    kubectl config use-context "$_saved_ctx" &>/dev/null 2>&1 || true
  fi
}

# validate_namespace <namespace> <current_ingress_namespace>
# Warns if namespace missing in cluster or if ingress is being moved between namespaces.
# Never blocks (non-fatal). current_ingress_namespace="" suppresses migration warning.
validate_namespace() {
  local namespace="$1" current_ingress_ns="${2:-}"

  if ! kubectl get namespace "$namespace" --no-headers &>/dev/null 2>&1; then
    warn "Namespace '$namespace' not found in cluster — Terraform will create it"
  fi

  if [[ -n "$current_ingress_ns" ]] && [[ "$current_ingress_ns" != "$namespace" ]]; then
    warn "Ingress currently in namespace '$current_ingress_ns' — deploying to '$namespace'"
    warn "Confirm this is intentional (namespace migration)"
  fi
}
