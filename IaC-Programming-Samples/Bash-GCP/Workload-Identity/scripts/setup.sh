#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/../logs/workload_identity.log"

# Ensure logs directory exists
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

usage() {
    echo "Usage: $0 <project_id> <gcp_sa> <ksa_name> <namespace> [new_namespace]"
    echo ""
    echo "Examples:"
    echo "  $0 gnp-reveca-qa sa-backend-qa ka-backend-qa default apps"
    echo "  $0 gnp-reveca-qa sa-backend-qa@gnp-reveca-qa.iam.gserviceaccount.com ka-backend-qa default apps"
    exit 1
}

if [ $# -lt 4 ]; then
    usage
fi

PROJECT_ID="$1"
GCP_SA="$2"
KSA_NAME="$3"
NAMESPACE="$4"
NEW_NAMESPACE="${5:-$NAMESPACE}"

# Convert SA name to email if needed
if [[ ! "$GCP_SA" =~ @ ]]; then
    GCP_SA="${GCP_SA}@${PROJECT_ID}.iam.gserviceaccount.com"
fi

log "========================================"
log "Workload Identity Setup"
log "========================================"
log "Project: $PROJECT_ID"
log "GCP SA: $GCP_SA"
log "KSA: $KSA_NAME"
log "Namespace: $NAMESPACE -> $NEW_NAMESPACE"

# Verify GCP SA exists
log ""
log "Verifying GCP Service Account..."
if ! gcloud iam service-accounts describe "$GCP_SA" --project "$PROJECT_ID" &>/dev/null; then
    log "ERROR: GCP SA not found: $GCP_SA"
    exit 1
fi
log "✓ GCP SA verified"

# Cleanup source namespace if different from target
if [ "$NAMESPACE" != "$NEW_NAMESPACE" ]; then
    log ""
    log "Cleaning up source namespace ($NAMESPACE)..."
    
    gcloud iam service-accounts remove-iam-policy-binding "$GCP_SA" \
        --project "$PROJECT_ID" \
        --role "roles/iam.workloadIdentityUser" \
        --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]" \
        2>/dev/null || true
    
    kubectl delete serviceaccount "$KSA_NAME" -n "$NAMESPACE" 2>/dev/null || true
fi

# Create target namespace
log ""
log "Creating namespace: $NEW_NAMESPACE"
kubectl create namespace "$NEW_NAMESPACE" 2>/dev/null || log "(info) Namespace already exists"

# Create KSA
log "Creating KSA: $KSA_NAME"
kubectl create serviceaccount "$KSA_NAME" -n "$NEW_NAMESPACE" 2>/dev/null || log "(info) KSA already exists"

# Add IAM binding
log "Adding IAM binding..."
gcloud iam service-accounts add-iam-policy-binding "$GCP_SA" \
    --project "$PROJECT_ID" \
    --role "roles/iam.workloadIdentityUser" \
    --member "serviceAccount:${PROJECT_ID}.svc.id.goog[${NEW_NAMESPACE}/${KSA_NAME}]" \
    >/dev/null 2>&1 || true

# Annotate KSA
log "Annotating KSA..."
kubectl annotate serviceaccount "$KSA_NAME" \
    --namespace "$NEW_NAMESPACE" \
    "iam.gke.io/gcp-service-account=${GCP_SA}" \
    --overwrite

log ""
log "Verification:"
kubectl describe serviceaccount "$KSA_NAME" -n "$NEW_NAMESPACE" | grep -A1 "Annotations"

log ""
log "========================================"
log "✓ Setup completed"
log "========================================"
