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
    if [[ "$local_path" -ef "$dest" ]]; then
      ok "Local YAML already in place: $dest"
      return 0
    fi
    cp "$local_path" "$dest"
    ok "Copied local YAML → $dest"
    return 0
  fi

  # Convert GitLab blob URL → GitLab API /repository/files/:path/raw endpoint
  # Pattern: https://gitlab.com/<namespace>/<project>/-/blob/<ref>/<file_path>
  if [[ "$url" =~ ^(https://gitlab\.[^/]+)/(.+)/-/blob/([^/]+)/(.+)$ ]]; then
    local gl_host="${BASH_REMATCH[1]}"
    local gl_project="${BASH_REMATCH[2]}"
    local gl_ref="${BASH_REMATCH[3]}"
    local gl_file="${BASH_REMATCH[4]%%\?*}"  # strip ?ref_type=tags and any query params
    local gl_project_enc gl_file_enc
    gl_project_enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1],''))" "$gl_project")
    gl_file_enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1],''))" "$gl_file")
    url="${gl_host}/api/v4/projects/${gl_project_enc}/repository/files/${gl_file_enc}/raw?ref=${gl_ref}"
    info "GitLab URL → API: $url"
  fi

  info "Downloading ingress YAML from: $url"

  local http_code
  # GitLab API: use PRIVATE-TOKEN only — gcloud Bearer token causes SAML redirect
  if [[ "$url" =~ /api/v4/projects/ ]] && [[ -n "${GITLAB_TOKEN:-}" ]]; then
    http_code=$(curl -fsSL \
      -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      --output "$dest" \
      --write-out "%{http_code}" \
      "$url" 2>/dev/null)
  else
    # GCP/other URLs: use gcloud Bearer token; fall back to unauthenticated
    local token
    token=$(gcloud auth print-access-token 2>/dev/null || true)
    if [[ -n "$token" ]]; then
      http_code=$(curl -fsSL \
        -H "Authorization: Bearer ${token}" \
        --output "$dest" \
        --write-out "%{http_code}" \
        "$url" 2>/dev/null)
    else
      http_code=$(curl -fsSL \
        --output "$dest" \
        --write-out "%{http_code}" \
        "$url" 2>/dev/null)
    fi
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
