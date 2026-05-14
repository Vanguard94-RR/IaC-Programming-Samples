#!/bin/bash
# =============================================================================
# Workload Identity Manager for GCP/GKE
# Configure GCP Workload Identity between GCP SA and Kubernetes SA
# 
# Project: GCP Infrastructure Management
# Version: 4.5.0
# Author: Infrastructure Team
# License: Internal Use
#
# Features:
#   - Interactive menu system with colored output
#   - GCS remote state sync (integrated with gs://gnp-workloadidentity, can override via WI_GCS_BUCKET)
#   - Automatic ticket-based log organization
#   - CSV registry of all operations with status tracking
#   - Robust error handling and validation
#
# Usage:
#   ./workload-identity.sh              # Run interactive menu
#   ./workload-identity.sh --help       # Show help
#   ./workload-identity.sh --version    # Show version
# =============================================================================

# Script safety settings
set -euo pipefail
IFS=$'\n\t'

# Metadata
readonly G_VERSION="4.5.0"
readonly G_SCRIPT_NAME="Workload Identity Manager"
readonly G_SCRIPT_DESC="Configure GCP Workload Identity between GCP SA and Kubernetes SA"

# Trap errors and cleanup
trap 'handle_error $? $LINENO' ERR
handle_error() {
    local exit_code=$1
    local line_no=$2
    echo -e "\n${RED}✗ Error at line $line_no (exit code: $exit_code)${NC}" >&2
    exit "$exit_code"
}

# --- Global Variables (prefixed with G_) ---
readonly G_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly G_BASE_DIR="$(dirname "$G_SCRIPT_DIR")"
readonly G_TICKETS_DIR="$G_BASE_DIR/Tickets"
readonly G_CONTROL_FILE="${WI_REGISTRY_FILE:-$G_SCRIPT_DIR/workload-identity-registry.csv}"
# Use mktemp for secure temporary directory (prevents symlink attacks)
readonly G_TEMP_DIR="$(mktemp -d -t workload-identity.XXXXXX)"

G_LOG_DIR=""
G_LOG_FILE=""
G_TICKET_ID=""
G_PROJECT_ID=""
G_CLUSTER_NAME=""
G_NAMESPACE="apps"

# --- Load Configuration ---
# Source external configuration file if it exists
if [[ -f "$G_SCRIPT_DIR/config.sh" ]]; then
    # shellcheck source=config.sh
    source "$G_SCRIPT_DIR/config.sh"
fi

# --- Source Library Files ---
[[ -f "$G_SCRIPT_DIR/lib/registry.sh" ]] || { echo "ERROR: lib/registry.sh not found" >&2; exit 1; }
source "$G_SCRIPT_DIR/lib/registry.sh"
[[ -f "$G_SCRIPT_DIR/lib/core.sh" ]] || { echo "ERROR: lib/core.sh not found" >&2; exit 1; }
source "$G_SCRIPT_DIR/lib/core.sh"
[[ -f "$G_SCRIPT_DIR/lib/ui.sh" ]] || { echo "ERROR: lib/ui.sh not found" >&2; exit 1; }
source "$G_SCRIPT_DIR/lib/ui.sh"

# Use configuration values with fallbacks to defaults
readonly G_IAM_ROLE="${WI_IAM_ROLE:-roles/iam.workloadIdentityUser}"
readonly G_DEFAULT_NS="${WI_DEFAULT_NAMESPACE:-apps}"
readonly G_ANNOTATION_KEY="${WI_ANNOTATION_KEY:-iam.gke.io/gcp-service-account}"
# Remote sync settings (default: gs://gnp-workloadidentity, override via WI_GCS_BUCKET)
G_GCS_BUCKET="${WI_GCS_BUCKET:-gs://gnp-workloadidentity}"

# Cleanup on exit
trap 'cleanup' EXIT
cleanup() {
    # Cleanup temp directory
    rm -rf "$G_TEMP_DIR" 2>/dev/null || true
}
mkdir -p "$G_TEMP_DIR"

# register_execution kept for backward compat; status arg ($8) intentionally dropped:
# registry_upsert always writes "activo" (cleanup uses update_registry_status instead)
register_execution() {
    registry_upsert "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}

# =============================================================================
# Main Menu Loop
# =============================================================================

main() {
    check_gcloud_auth || { print_error "Unable to authenticate with gcloud"; exit 1; }
    while true; do
        show_main_menu
        local option
        read -r option
        case $option in
            1) interactive_bind ;;
            2) interactive_setup ;;
            3) interactive_verify ;;
            4) interactive_cleanup ;;
            5) interactive_list ;;
            6) interactive_registry ;;
            0) clear; echo -e "${LGREEN}Goodbye!${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# =============================================================================
# Entry Point
# =============================================================================

# ─── Entry Point Guard ───────────────────────────────────────────────────────
# When WI_UNIT_TEST=1, the script is being sourced by the test suite.
# Skip dependency checks, file initialization and entry-point dispatch so the
# test suite can call individual functions in isolation.
if [[ "${WI_UNIT_TEST:-0}" != "1" ]]; then

    # Check dependencies
    for cmd in gcloud kubectl jq; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}✗ Error: $cmd is not installed${NC}"
            echo -e "${GRAY}Please install the required tools and try again${NC}"
            exit 1
        fi
    done

    # Initialize control file
    init_control_file

    # Handle --help and --version flags
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --version|-v)
            show_version
            exit 0
            ;;
    esac

    # Start interactive menu
    main

fi  # end WI_UNIT_TEST guard
