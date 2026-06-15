#!/usr/bin/env bash

# Find and source ui.sh
_find_ui_sh() {
  local ui_candidates=(
    "$(dirname "$0")/ui.sh"
    "$(dirname "$0")/../lib/ui.sh"
    "$(dirname "$0")/../ui.sh"
  )
  for candidate in "${ui_candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

_ui_path=$(_find_ui_sh) && . "$_ui_path"

# Wait for ingress to get an IP address assigned
# Usage: wait_for_ingress_ip <namespace> <ingress_name> <timeout_seconds>
wait_for_ingress_ip() {
  local namespace="$1"
  local ingress_name="$2"
  local timeout="${3:-1800}"  # Default 30 minutes
  
  local start_time=$(date +%s)
  local max_time=$((start_time + timeout))
  
  while true; do
    # Check if ingress has an IP assigned
    local ingress_ip=$(kubectl get ingress "$ingress_name" -n "$namespace" \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    
    if [[ -n "$ingress_ip" ]]; then
      ok "Ingress IP assigned: $ingress_ip"
      return 0
    fi
    
    # Check timeout
    local current_time=$(date +%s)
    if [[ $current_time -gt $max_time ]]; then
      error "Ingress IP assignment timeout after ${timeout}s"
      return 1
    fi
    
    # Wait before retrying (every 10 seconds)
    local elapsed=$((current_time - start_time))
    info "Waiting for ingress IP... (${elapsed}s / ${timeout}s)"
    sleep 10
  done
}
