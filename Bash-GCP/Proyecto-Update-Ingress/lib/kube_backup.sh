#!/usr/bin/env bash
# Backup helpers for Ingress resources

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui.sh"

# Ensure temp cleanup is invoked if provided by other modules
if declare -f cleanup_temp_files >/dev/null 2>&1; then
    trap cleanup_temp_files EXIT INT TERM
fi

backup_current_ingress() {
    step "Backing up current Ingress"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)

    # Determine destination backups directory:
    # Priority: BACKUP_DIR env var -> detect Tickets/<ticket> ancestor -> current dir
    local detected_ticket_dir=""
    if [ -n "${TICKET_DIR:-}" ]; then
        detected_ticket_dir="$TICKET_DIR"
    else
        # Try to detect a path segment like .../Tickets/CTASK12345 under $PWD
        IFS='/' read -r -a _parts <<< "$PWD"
        for idx in "${!_parts[@]}"; do
            if [ "${_parts[$idx]}" = "Tickets" ] && [ -n "${_parts[$((idx+1))]:-}" ]; then
                # build path up to and including the ticket folder
                ticket_path=""
                for ((j=0;j<=idx+1;j++)); do
                    if [ -z "${_parts[$j]}" ]; then
                        ticket_path="/"
                    else
                        if [ "$ticket_path" = "/" ]; then
                            ticket_path="${ticket_path}${_parts[$j]}"
                        else
                            ticket_path="${ticket_path}/${_parts[$j]}"
                        fi
                    fi
                done
                detected_ticket_dir="$ticket_path"
                break
            fi
        done
    fi

    if [ -n "${BACKUP_DIR:-}" ]; then
        # If BACKUP_DIR explicitly provided, prefer a 'backups' subdirectory
        # when the provided dir looks like a ticket root (e.g. .../Tickets/CTASK12345)
        case "${BACKUP_DIR%/}" in
            */backups|backups)
                DEST_DIR="${BACKUP_DIR%/}"
                ;;
            *)
                DEST_DIR="${BACKUP_DIR%/}/backups"
                ;;
        esac
    elif [ -n "$detected_ticket_dir" ]; then
        DEST_DIR="${detected_ticket_dir%/}/backups"
    else
        DEST_DIR="."
    fi
    mkdir -p "$DEST_DIR" 2>/dev/null || true
    info "Backups will be saved in: $DEST_DIR"

    SAFE_PROJECT=${PROJECT_ID//[^A-Za-z0-9._-]/}
    SAFE_TICKET=${TICKET_ID:-unknown}
    BACKUP_FILE="$DEST_DIR/ingress_old_${SAFE_TICKET}_${SAFE_PROJECT}_$TIMESTAMP.yaml"
    CLEAN_FILE="$DEST_DIR/ingress_rollback_${SAFE_TICKET}_${SAFE_PROJECT}_$TIMESTAMP.yaml"
    if kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" -o yaml > "$BACKUP_FILE"; then
        success "Deployed Ingress Backup saved as $BACKUP_FILE"
        if command -v yq &> /dev/null; then
            # Use a single-line yq expression to remove fields that should not be present in a rollback file.
            # Avoid embedding literal \n sequences which can be interpreted as text by yq.
            yq eval 'del(.metadata.creationTimestamp, .metadata.resourceVersion, .metadata.uid, .metadata.generation, .metadata.finalizers, .metadata.managedFields, .status, .metadata.annotations."ingress.kubernetes.io/backends", .metadata.annotations."ingress.kubernetes.io/forwarding-rule", .metadata.annotations."ingress.kubernetes.io/target-proxy", .metadata.annotations."ingress.kubernetes.io/url-map", .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration")' "$BACKUP_FILE" > "$CLEAN_FILE"
            success "Rollback-ready backup saved as $CLEAN_FILE"
            info "To rollback, run:"
            info "kubectl apply -f $CLEAN_FILE -n $NAMESPACE"
        else
            warn "yq not available. Only the original backup will be created."
            error "The original backup cannot be applied directly. You must clean it first using yq or manually before rollback."
            info "To clean manually, use:"
            info "yq eval 'del(.metadata.creationTimestamp) | del(.metadata.resourceVersion) | del(.metadata.uid) | del(.metadata.generation) | del(.metadata.finalizers) | del(.metadata.managedFields) | del(.status)' $BACKUP_FILE > cleaned_backup.yaml"
            info "Then rollback with:"
            info "kubectl apply -f cleaned_backup.yaml -n $NAMESPACE"
        fi
    else
        echo -e "${RED}Failed to backup Ingress. Exiting.${NC}"
        exit 1
    fi
}
