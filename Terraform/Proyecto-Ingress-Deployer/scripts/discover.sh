#!/usr/bin/env bash
# Discovers ingress configuration in a target project and generates environments/<project>.tfvars
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CENTRAL_PROJECT="${CENTRAL_PROJECT:-gnp-fleets-qa}"
# HOME guard — runs before any ${HOME} expansion and before lib sourcing
# Uses plain echo: ui.sh not sourced yet (error() would be "command not found")
if [[ -z "${HOME:-}" ]]; then
  if [[ -z "${USER:-}" ]]; then
    echo "ERROR: HOME and USER are both unset. Cannot resolve default paths." >&2
    exit 1
  fi
  export HOME="/home/$USER"
  mkdir -p "$HOME"
fi
TICKETS_BASE="${TICKETS_BASE:-${HOME}/.gnp/tickets}"
# Set LOG_FILE before sourcing ui.sh so _log_persist writes to disk from first call
LOG_FILE="$TICKETS_BASE/discover-$(date +%Y%m%d).log"
mkdir -p "$TICKETS_BASE"
export LOG_FILE
# shellcheck source=../lib/ui.sh
. "$SCRIPT_DIR/lib/ui.sh"
[[ "${TICKETS_BASE:-}" == */home/admin/* ]] && \
  warn "TICKETS_BASE contains a machine-specific path. Export TICKETS_BASE=\${HOME}/.gnp/tickets in your shell profile."

PROJECT_ID="${1:-}"
if [[ -z "$PROJECT_ID" ]]; then
  error "Usage: $0 <project-id>"
  error "Example: $0 gnp-plus-qa"
  exit 1
fi

ENVS_DIR="$SCRIPT_DIR/environments"
TFVARS_OUT="$ENVS_DIR/${PROJECT_ID}.tfvars"
DUMP_FILE="/tmp/ingress-discovery-${PROJECT_ID}-$(date +%Y%m%d%H%M%S).yaml"
trap 'rm -f "$DUMP_FILE"' EXIT INT TERM

print_banner "Ingress Discovery — $PROJECT_ID"

# Discover cluster
step "Cluster discovery"
_all_clusters=$(gcloud container clusters list \
  --project="$PROJECT_ID" --format="value(name)" 2>/dev/null || echo "")
_cluster_count=$(echo "$_all_clusters" | grep -c . || true)

if [[ "$_cluster_count" -gt 1 ]]; then
  if [[ "${CI:-false}" == "true" ]]; then
    error "Multiple clusters found in $PROJECT_ID. Set CLUSTER_NAME to disambiguate."
    exit 1
  else
    warn "Multiple clusters found in $PROJECT_ID — using first. Set CLUSTER_NAME to override."
  fi
fi

CLUSTER_NAME=$(echo "$_all_clusters" | head -1)
CLUSTER_LOCATION=$(gcloud container clusters list \
  --project="$PROJECT_ID" --format="value(location)" \
  --filter="name=$CLUSTER_NAME" 2>/dev/null | head -1 || echo "")

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
  if [[ "$INGRESS_COUNT" -gt 1 ]]; then
    _ingress_list=$(yq '.items[].metadata.name' "$DUMP_FILE" | tr '\n' ' ')
    if [[ "${CI:-false}" == "true" ]]; then
      error "Multiple ingresses found: $_ingress_list. Set INGRESS_NAME to disambiguate."
      exit 1
    else
      warn "Multiple ingresses found: $_ingress_list — using first. Set INGRESS_NAME to override."
    fi
  fi
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
