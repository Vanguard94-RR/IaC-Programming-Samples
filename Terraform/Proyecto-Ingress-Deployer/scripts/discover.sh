#!/usr/bin/env bash
# Discovers ingress configuration in a target project and generates environments/<project>.tfvars
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CENTRAL_PROJECT="${CENTRAL_PROJECT:-gnp-fleets-qa}"
TICKETS_BASE="${TICKETS_BASE:-$HOME/Documents/GNP/Tickets}"
# Set LOG_FILE before sourcing ui.sh so _log_persist writes to disk from first call
LOG_FILE="$TICKETS_BASE/discover-$(date +%Y%m%d).log"
mkdir -p "$TICKETS_BASE"
export LOG_FILE
# shellcheck source=../lib/ui.sh
. "$SCRIPT_DIR/lib/ui.sh"

PROJECT_ID="${1:-}"
if [[ -z "$PROJECT_ID" ]]; then
  error "Usage: $0 <project-id>"
  error "Example: $0 gnp-plus-qa"
  exit 1
fi

ENVS_DIR="$SCRIPT_DIR/environments"
TFVARS_OUT="$ENVS_DIR/${PROJECT_ID}.tfvars"
DUMP_FILE="/tmp/ingress-discovery-${PROJECT_ID}-$(date +%Y%m%d%H%M%S).yaml"

print_banner "Ingress Discovery — $PROJECT_ID"

# Discover cluster
step "Cluster discovery"
CLUSTER_NAME=$(gcloud container clusters list \
  --project="$PROJECT_ID" --format="value(name)" --limit=1 2>/dev/null || echo "")
CLUSTER_LOCATION=$(gcloud container clusters list \
  --project="$PROJECT_ID" --format="value(location)" --limit=1 2>/dev/null || echo "")

if [[ -z "$CLUSTER_NAME" ]]; then
  error "No GKE cluster found in project $PROJECT_ID"
  exit 1
fi
if [[ -z "$CLUSTER_LOCATION" ]]; then
  error "Could not determine cluster location for $CLUSTER_NAME in $PROJECT_ID"
  exit 1
fi
ok "Cluster: $CLUSTER_NAME ($CLUSTER_LOCATION)"

# Connect to cluster
step "Connecting to cluster"
_get_credentials "$PROJECT_ID" "$CLUSTER_NAME" "$CLUSTER_LOCATION"
ok "kubeconfig updated"

# Dump all ingresses
step "Dumping ingress resources"
kubectl get ingress -A -o yaml > "$DUMP_FILE"
INGRESS_COUNT=$(yq '.items | length' "$DUMP_FILE")
ok "Found $INGRESS_COUNT ingress resource(s) — saved to $DUMP_FILE"

if [[ "$INGRESS_COUNT" -eq 0 ]]; then
  warn "No ingresses found in $PROJECT_ID. Generating template tfvars."
  NAMESPACE="default"
  INGRESS_NAME="UNKNOWN"
  STATIC_IP_NAME="ingress-UNKNOWN"
else
  # Extract first ingress info (index 0) as representative
  NAMESPACE=$(yq '.items[0].metadata.namespace // "default"' "$DUMP_FILE")
  INGRESS_NAME=$(yq '.items[0].metadata.name // "UNKNOWN"' "$DUMP_FILE")
  STATIC_IP_NAME=$(yq \
    '.items[0].metadata.annotations["kubernetes.io/ingress.global-static-ip-name"] // "UNKNOWN"' \
    "$DUMP_FILE")
  info "Namespace:     $NAMESPACE"
  info "Ingress name:  $INGRESS_NAME"
  info "Static IP ref: $STATIC_IP_NAME"
fi

# Generate tfvars
step "Generating $TFVARS_OUT"
mkdir -p "$ENVS_DIR"
cat > "$TFVARS_OUT" << TFVARS
project_id       = "${PROJECT_ID}"
cluster_name     = "${CLUSTER_NAME}"
cluster_location = "${CLUSTER_LOCATION}"
namespace        = "${NAMESPACE}"
static_ip_name   = "${STATIC_IP_NAME}"
TFVARS

ok "tfvars written: $TFVARS_OUT"
info "Next: run ./scripts/deploy.sh to deploy the ingress"
