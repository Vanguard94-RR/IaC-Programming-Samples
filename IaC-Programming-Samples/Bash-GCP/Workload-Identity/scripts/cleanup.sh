#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/../logs/workload_identity.log"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

usage() {
    echo "Usage: $0 <project_id> <gcp_sa> <ksa_name> <namespace>"
    exit 1
}

if [ $# -lt 4 ]; then
    usage
fi

PROJECT_ID="$1"
GCP_SA="$2"
KSA_NAME="$3"
NAMESPACE="$4"

# Convert SA name to email if needed
if [[ ! "$GCP_SA" =~ @ ]]; then
    GCP_SA="${GCP_SA}@${PROJECT_ID}.iam.gserviceaccount.com"
fi

log "========================================"
log "Removing Workload Identity Binding"
log "========================================"

log "Removing IAM binding..."
gcloud iam service-accounts remove-iam-policy-binding "$GCP_SA" \
    --project "$PROJECT_ID" \
    --role "roles/iam.workloadIdentityUser" \
    --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]" \
    >/dev/null 2>&1 || log "(info) Binding may not exist"

log "Deleting KSA..."
kubectl delete serviceaccount "$KSA_NAME" -n "$NAMESPACE" 2>/dev/null || {
    log "ERROR: Failed to delete KSA"
    exit 1
}

log ""
log "========================================"
log "✓ Binding removed"
log "========================================"
