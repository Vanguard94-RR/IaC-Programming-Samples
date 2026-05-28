#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CENTRAL_PROJECT="${CENTRAL_PROJECT:-gnp-fleets-qa}"
# shellcheck source=../lib/ui.sh
. "$SCRIPT_DIR/lib/ui.sh"

PROJECT_ID="${1:-}"
if [[ -z "$PROJECT_ID" ]]; then
  error "Usage: $0 <project-id>"
  exit 1
fi

BUCKET="${PROJECT_ID}-tf-state"
TF_DIR="$SCRIPT_DIR/terraform"

step "Backend init — $PROJECT_ID"
info "State bucket: gs://${BUCKET} (in project ${PROJECT_ID})"
info "State prefix: ingress/"

# Create bucket if it does not exist
if ! gcloud storage buckets describe "gs://${BUCKET}" \
       --project="$PROJECT_ID" &>/dev/null; then
  info "Creating bucket gs://${BUCKET}..."
  gcloud storage buckets create "gs://${BUCKET}" \
    --project="$PROJECT_ID" \
    --uniform-bucket-level-access
  ok "Bucket created: gs://${BUCKET}"
else
  ok "Bucket exists: gs://${BUCKET}"
fi

# Enable object versioning for state protection
gcloud storage buckets update "gs://${BUCKET}" --versioning 2>/dev/null \
  && ok "Versioning enabled" || warn "Could not enable versioning (check permissions)"

# Initialize Terraform with the project-specific backend
info "Running terraform init..."
cd "$TF_DIR"
terraform init -reconfigure -input=false \
  -backend-config="bucket=${BUCKET}" \
  -backend-config="prefix=ingress"
ok "Terraform initialized — state: gs://${BUCKET}/ingress/"
