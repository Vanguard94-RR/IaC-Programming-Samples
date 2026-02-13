#!/usr/bin/env bash
# Minimal downloader wrapper for update_ingress v2

set -o errexit
set -o nounset
set -o pipefail

# download_gitlab_raw <gitlab-blob-url> -> writes ingress.yaml when the file is an Ingress
download_gitlab_raw() {
    local blob_url="$1"
    if [ -z "$blob_url" ]; then
        echo "Usage: download_gitlab_raw <gitlab-blob-url>" >&2
        return 2
    fi
    # Discover PRIVATE TOKEN: prefer env var, then common repo file locations
    local token=""
    if [ -n "${GITLAB_PRIVATE_TOKEN-}" ]; then
        token="$GITLAB_PRIVATE_TOKEN"
    else
        # Prefer a well-known absolute path if available (user-provided in workspace)
        local abs_token_path="/home/admin/Documents/GNP/Repos/token-gitlab-jmcm"
        local cand1
        local cand2
        cand1="$(pwd)/Repos/token-gitlab-jmcm"
        cand2="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/Repos/token-gitlab-jmcm"
        if [ -f "$abs_token_path" ]; then
            token=$(sed -n '1p' "$abs_token_path" 2>/dev/null || true)
        fi
        if [ -z "$token" ] && [ -f "$cand1" ]; then
            token=$(sed -n '1p' "$cand1" 2>/dev/null || true)
        fi
        if [ -z "$token" ] && [ -f "$cand2" ]; then
            token=$(sed -n '1p' "$cand2" 2>/dev/null || true)
        fi
    fi

    vprint "Using token: ${token:+present}${token:+' (hidden)'}"

    # Convert blob URL to raw API URL (simple heuristic)
    # Convert blob URL to API raw URL. Blob URL usually: https://gitlab.com/<group>/<proj>/-/blob/<ref>/<path>
    # We need to URL-encode the path and construct: https://gitlab.com/api/v4/projects/<group%2Fproj>/repository/files/<encoded_path>/raw?ref=<ref>
    local api_url=""
    # naive parse using awk to split ref and path
    # remove trailing slash
    local tmp
    tmp=${blob_url%/}
    # extract ref (the part after /-/blob/<ref>/)
    if echo "$tmp" | grep -q "/-/blob/"; then
        local before_ref
        before_ref=${tmp%%/-/blob/*}
        local after_ref
        after_ref=${tmp#*/-/blob/}
        local ref_part
        ref_part=${after_ref%%/*}
        local file_path
        file_path=${after_ref#${ref_part}/}
        # extract project path (domain removed)
        local project_path
        project_path=${before_ref#https://gitlab.com/}

        # URL-encode file_path using python3 if available, else fallback to sed-ish encoding for slashes
        local encoded_path
        if command -v python3 >/dev/null 2>&1; then
            encoded_path=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$file_path")
        else
            # encode slashes and spaces conservatively
            encoded_path=$(printf '%s' "$file_path" | sed -e 's/ /%20/g' -e 's#/##g')
        fi

        # URL-encode project_path for project id
        local encoded_project
        if command -v python3 >/dev/null 2>&1; then
            encoded_project=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$project_path")
        else
            encoded_project=$(printf '%s' "$project_path" | sed -e 's/\//%2F/g')
        fi

        api_url="https://gitlab.com/api/v4/projects/${encoded_project}/repository/files/${encoded_path}/raw?ref=${ref_part}"
    fi

    if [ -z "$api_url" ]; then
        echo "Failed to parse GitLab blob URL: $blob_url" >&2
        return 6
    fi

    # Download to tmp
    local tmpfile
    tmpfile=$(mktemp /tmp/gitlab_raw_XXXXXX)
    echo "[INFO] Downloading $api_url to $tmpfile"

    if [ "${DRY_RUN}" = "true" ]; then
        vprint "DRY_RUN: would download $api_url"
        rm -f "$tmpfile" 2>/dev/null || true
        return 0
    fi

    if command -v curl &>/dev/null; then
        if [ -n "$token" ]; then
            curl -sSL -H "PRIVATE-TOKEN: $token" -o "$tmpfile" "$api_url" || { rm -f "$tmpfile"; return 3; }
        else
            curl -sSL -o "$tmpfile" "$api_url" || { rm -f "$tmpfile"; return 3; }
        fi
    elif command -v wget &>/dev/null; then
        if [ -n "$token" ]; then
            wget --header="PRIVATE-TOKEN: $token" -q -O "$tmpfile" "$api_url" || { rm -f "$tmpfile"; return 3; }
        else
            wget -q -O "$tmpfile" "$api_url" || { rm -f "$tmpfile"; return 3; }
        fi
    else
        echo "Neither curl nor wget available to download files" >&2
        rm -f "$tmpfile" 2>/dev/null || true
        return 4
    fi

    # Basic detection: check if file contains 'kind: Ingress'
    if grep -qE '^\s*kind:\s*Ingress\b' "$tmpfile"; then
        mv "$tmpfile" "ingress.yaml"
        echo "[OK] ingress.yaml created"
        return 0
    else
        # preserve for inspection
        mv "$tmpfile" "downloaded_file"
        echo "[WARN] downloaded file does not look like an Ingress; saved as downloaded_file"
        # Print a short snippet to help diagnose common API errors (404, auth, HTML error pages)
        echo "[DEBUG] Showing first 200 bytes of the server response to help debugging:"
        if [ -s "downloaded_file" ]; then
            head -c 200 "downloaded_file" | sed 's/\r/\\r/g' | sed 's/\n/\\n/g' | awk '{print}'
            echo
        else
            echo "[DEBUG] downloaded_file is empty"
        fi
        echo "[HINT] If the project is private, set GITLAB_PRIVATE_TOKEN env var (read_repository scope) or place token in Repos/token-gitlab-jmcm"
        return 5
    fi
}
