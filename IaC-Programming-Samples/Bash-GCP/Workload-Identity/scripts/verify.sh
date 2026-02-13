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
    echo ""
    echo "Example:"
    echo "  $0 gnp-reveca-qa sa-backend-qa ka-backend-qa apps"
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
log "Verifying Workload Identity Setup"
log "========================================"

log ""
log "KSA Details:"
kubectl describe serviceaccount "$KSA_NAME" -n "$NAMESPACE" 2>/dev/null || {
    log "ERROR: KSA not found in namespace $NAMESPACE"
    exit 1
}

log ""
log "GCP SA IAM Policy:"
gcloud iam service-accounts get-iam-policy "$GCP_SA" --project "$PROJECT_ID" 2>/dev/null || {
    log "ERROR: GCP SA not found or not accessible"
    exit 1
}

log ""
log "Checking annotation:"
ANNOTATION=$(kubectl get serviceaccount "$KSA_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' 2>/dev/null)
if [ "$ANNOTATION" == "$GCP_SA" ]; then
    log "✓ Annotation is correct: $ANNOTATION"
else
    log "✗ Annotation mismatch or missing"
    log "  Expected: $GCP_SA"
    log "  Found: $ANNOTATION"
    exit 1
fi

log ""
log "========================================"
log "✓ Workload Identity is properly configured"
log "========================================"
