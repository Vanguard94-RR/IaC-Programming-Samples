#!/usr/bin/env bash
# Download ingress YAML from a URL.
# Supports public URLs and private GitLab instances using a gcloud access token.
# Requires: curl, ui.sh sourced before this file.

# download_ingress_yaml <url> <destination-path>
# Returns 0 on success, 1 on failure.
download_ingress_yaml() {
  local url="$1"
  local dest="$2"

  if [[ -z "$url" ]] || [[ -z "$dest" ]]; then
    error "download_ingress_yaml: url and dest are required"
    return 1
  fi

  mkdir -p "$(dirname "$dest")"

  # Handle local file paths (file:// scheme or absolute path)
  local local_path=""
  if [[ "$url" == file://* ]]; then
    local_path="${url#file://}"
  elif [[ "$url" == /* ]]; then
    local_path="$url"
  fi

  if [[ -n "$local_path" ]]; then
    if [[ ! -f "$local_path" ]]; then
      error "Local file not found: $local_path"
      return 1
    fi
    cp "$local_path" "$dest"
    ok "Copied local YAML → $dest"
    return 0
  fi

  info "Downloading ingress YAML from: $url"

  # Use gcloud token for private GitLab/GCP URLs; fall back to unauthenticated
  local token
  token=$(gcloud auth print-access-token 2>/dev/null || true)

  local http_code
  if [[ -n "$token" ]]; then
    http_code=$(curl -fsSL \
      -H "Authorization: Bearer ${token}" \
      -H "PRIVATE-TOKEN: ${GITLAB_TOKEN:-}" \
      --output "$dest" \
      --write-out "%{http_code}" \
      "$url" 2>/dev/null)
  else
    http_code=$(curl -fsSL \
      --output "$dest" \
      --write-out "%{http_code}" \
      "$url" 2>/dev/null)
  fi

  if [[ "$http_code" -ge 200 ]] && [[ "$http_code" -lt 300 ]]; then
    ok "Downloaded ingress YAML (HTTP ${http_code}) → $dest"
    return 0
  else
    error "Download failed (HTTP ${http_code}): $url"
    rm -f "$dest"
    return 1
  fi
}
