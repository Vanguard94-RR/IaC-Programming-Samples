#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Source all modules
for _lib in ui utils shared_vpc vpc twistlock ssl workload_identity hardening log4j cluster; do
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/lib/${_lib}.sh"
done

# Early --help / -h check before subcommand parsing
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage; exit 0
fi

# Subcommand is first positional arg (default: create)
SUBCOMMAND="${1:-create}"
shift || true

# Global flags
DRY_RUN=false
VERBOSE=false
export DRY_RUN VERBOSE

# Optional pre-load params
ARG_PROJECT=""
ARG_CLUSTER=""
ARG_REGION=""
ARG_ENV=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --dry-run)   DRY_RUN=true; shift ;;
        --verbose)   VERBOSE=true; shift ;;
        --project)   ARG_PROJECT="$2"; shift 2 ;;
        --cluster)   ARG_CLUSTER="$2"; shift 2 ;;
        --region)    ARG_REGION="$2"; shift 2 ;;
        --env)       ARG_ENV="$2"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        *)           error "Unknown flag: $1"; usage; exit 1 ;;
    esac
done

# Centralized log
mkdir -p "$SCRIPT_DIR/logs"
LOG_FILE="$SCRIPT_DIR/logs/$(date +%Y%m%d_%H%M%S)-${SUBCOMMAND}.log"
export LOG_FILE

trap 'error "Aborted. See log: $LOG_FILE"' ERR INT TERM

print_banner_box "GKE Cluster Creation — GNP"

case "$SUBCOMMAND" in
    create)         cmd_create ;;
    update-armor)   cmd_update_armor ;;
    rollback-armor) cmd_rollback_armor ;;
    fix-shared-vpc) cmd_fix_shared_vpc ;;
    log4j)          cmd_log4j ;;
    *)              error "Unknown subcommand: $SUBCOMMAND"; usage; exit 1 ;;
esac
