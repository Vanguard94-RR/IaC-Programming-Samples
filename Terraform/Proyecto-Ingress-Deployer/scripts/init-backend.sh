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
STATE_PREFIX="ingress/"

step "Backend initialization — $PROJECT_ID"
info "State bucket: gs://${BUCKET}"
info "State prefix: ${STATE_PREFIX}"

# ── Idempotency check: bucket exists? ──────────────────────────────────────
_bucket_exists() {
  gcloud storage buckets describe "gs://${BUCKET}" \
    --project="$PROJECT_ID" &>/dev/null
}

if _bucket_exists; then
  ok "Bucket exists: gs://${BUCKET}"
else
  step "Creating bucket gs://${BUCKET}..."
  gcloud storage buckets create "gs://${BUCKET}" \
    --project="$PROJECT_ID" \
    --uniform-bucket-level-access || {
      error "Bucket creation failed. Check permissions in $PROJECT_ID"
      exit 1
    }
  ok "Bucket created: gs://${BUCKET}"
fi

# ── Idempotency check: versioning already enabled? ────────────────────────
step "Enabling versioning (state protection)"
if gcloud storage buckets describe "gs://${BUCKET}" --project="$PROJECT_ID" \
     --format="value(versioning.enabled)" | grep -q "true"; then
  ok "Versioning already enabled"
else
  if gcloud storage buckets update "gs://${BUCKET}" \
       --project="$PROJECT_ID" --versioning 2>/dev/null; then
    ok "Versioning enabled"
  else
    warn "Could not enable versioning (check IAM permissions)"
  fi
fi

# ── Idempotency check: terraform already initialized? ──────────────────────
step "Terraform initialization"
if [[ -d "$TF_DIR/.terraform" ]]; then
  ok "Terraform working directory exists"
  # Check if backend is already configured for this bucket
  if grep -q "$BUCKET" "$TF_DIR/.terraform/terraform.tfstate" 2>/dev/null; then
    ok "Backend already configured for: $BUCKET"
  else
    warn "Backend may be configured for different bucket, reconfiguring..."
    cd "$TF_DIR"
    terraform init -reconfigure -input=false \
      -backend-config="bucket=${BUCKET}" \
      -backend-config="prefix=${STATE_PREFIX}" || {
        error "Terraform reconfiguration failed"
        exit 1
      }
  fi
else
  step "Running terraform init..."
  cd "$TF_DIR"
  terraform init -input=false \
    -backend-config="bucket=${BUCKET}" \
    -backend-config="prefix=${STATE_PREFIX}" || {
      error "Terraform initialization failed"
      exit 1
    }
fi

ok "Backend ready: gs://${BUCKET}/${STATE_PREFIX}"
info "State file will be stored at: gs://${BUCKET}/${STATE_PREFIX}terraform.tfstate"
