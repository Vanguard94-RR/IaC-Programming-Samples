#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui.sh"

# Global state — set by entrypoint
: "${DRY_RUN:=false}"
: "${VERBOSE:=false}"
: "${LOG_FILE:=/dev/null}"

# run_or_dry: wraps every gcloud/kubectl call
# Usage: run_or_dry gcloud container clusters create ...
run_or_dry() {
    if [ "$DRY_RUN" = "true" ]; then
        info "[DRY-RUN] $*"
        return 0
    fi
    "$@"
}

# prompt_or_arg: prompt that respects a pre-loaded CLI flag value
# Usage: prompt_or_arg <varname> <preloaded> <prompt_text> <default>
prompt_or_arg() {
    local __var="$1"
    local preloaded="$2"
    local prompt_text="$3"
    local default="$4"
    if [ -n "$preloaded" ]; then
        printf -v "$__var" '%s' "$preloaded"
        info "Using ${__var}: ${preloaded} (from flag)"
        return 0
    fi
    read_input "$__var" "${WHITE}>> ${prompt_text} (default: ${CYAN}${default}${NC}): "
    if [ -z "${!__var}" ]; then
        printf -v "$__var" '%s' "$default"
    fi
}

# log: write to terminal and log file simultaneously
log() {
    printf '%b\n' "$1" | tee -a "$LOG_FILE"
}

# validate_number: returns 0 if input is integer between 1 and max
validate_number() {
    local input=$1
    local max=$2
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        error "Invalid input. Please enter a number."
        return 1
    fi
    if [ "$input" -lt 1 ] || [ "$input" -gt "$max" ]; then
        error "Invalid selection. Please enter a number between 1 and $max."
        return 1
    fi
    return 0
}

# usage: print help and exit
usage() {
    print_banner_box "GKE Cluster Creation"
    info "Usage: create_gke_cluster.sh [SUBCOMMAND] [FLAGS]"
    info ""
    info "Subcommands:"
    info "  create (default)   Full 10-step GKE cluster creation"
    info "  update-armor       Apply/update Cloud Armor rules"
    info "  rollback-armor     Restore Cloud Armor rules from JSON backup"
    info "  fix-shared-vpc     Associate service project to Shared VPC host"
    info "  log4j              Apply or backup log4j WAF rules"
    info ""
    info "Global flags:"
    info "  --dry-run          Print gcloud/kubectl calls without executing"
    info "  --verbose          Print verbose diagnostic output"
    info "  -h, --help         Print this help and exit"
    info ""
    info "Create flags (pre-load params, skip prompts):"
    info "  --project <id>     GCP project ID"
    info "  --cluster <name>   GKE cluster name"
    info "  --region <region>  GCP region (e.g. us-central1)"
    info "  --env <qa|uat|pro> Environment (sets machine type, channel, fleet)"
}
