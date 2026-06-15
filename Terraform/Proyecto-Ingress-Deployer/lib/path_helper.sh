#!/usr/bin/env bash
# =============================================================================
# PATH Helper — Ensures installed tools are available in PATH
# Sourced by other scripts to load environment from setup.sh
# Expects: SCRIPT_DIR set by calling script
# =============================================================================

# Load GNP environment if setup has been run
_load_gnp_environment() {
    local gnp_home="${GNP_HOME:-$HOME/.gnp}"
    local config_file="$gnp_home/ingress/config.env"
    
    # If config exists, source it to load GITLAB_TOKEN and other vars
    if [[ -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file" 2>/dev/null || true
    fi
    
    # Ensure terraform bin is in PATH
    if [[ -d "$gnp_home/terraform/bin" ]]; then
        export PATH="$gnp_home/terraform/bin:$PATH"
    fi
}

# Verify that a command exists, with helpful error message
_require_command() {
    local cmd="$1"
    local package="${2:-$cmd}"
    
    if ! command -v "$cmd" &>/dev/null; then
        cat >&2 <<EOF
ERROR: '$cmd' not found in PATH

This tool is required to proceed. Install it with:
  make install

Or manually install: $package
EOF
        return 1
    fi
}

# Load environment on source
_load_gnp_environment
