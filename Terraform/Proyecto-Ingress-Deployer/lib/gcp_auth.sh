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

# Verify and refresh Google Cloud credentials
verify_gcloud_auth() {
  step "Verifying Google Cloud credentials..."
  
  # Check if gcloud is authenticated
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
    error "gcloud authentication check failed"
    return 1
  fi
  
  local active_account
  active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || true)
  
  if [[ -z "$active_account" ]]; then
    error "No active gcloud account"
    error "Run: gcloud auth login"
    return 1
  fi
  
  ok "Active account: $active_account"
  
  # Check Application Default Credentials validity
  if ! gcloud auth application-default print-access-token &>/dev/null 2>&1; then
    warn "Application Default Credentials expired or invalid"
    step "Attempting to refresh Application Default Credentials..."
    
    # Try to refresh the current user's credentials
    if gcloud auth refresh &>/dev/null 2>&1; then
      ok "User credentials refreshed"
    else
      warn "User credential refresh didn't help"
    fi
    
    # Remove potentially stale ADC file and recreate it
    step "Recreating Application Default Credentials..."
    rm -f ~/.config/gcloud/application_default_credentials.json
    
    # Generate new ADC from current user credentials
    if gcloud auth application-default login --no-launch-browser 2>&1 >/dev/null; then
      ok "Application Default Credentials created"
    else
      # Last resort: suggest manual login
      warn "Automatic ADC creation requires browser authentication"
      error "Please run: gcloud auth application-default login"
      return 1
    fi
  else
    ok "Application Default Credentials valid"
  fi
  
  return 0
}

