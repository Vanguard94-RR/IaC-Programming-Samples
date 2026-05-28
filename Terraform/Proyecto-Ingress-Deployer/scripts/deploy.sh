#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CENTRAL_PROJECT="${CENTRAL_PROJECT:-gnp-fleets-qa}"
TICKETS_BASE="${TICKETS_BASE:-/home/admin/Documents/GNP/Tickets}"
# shellcheck source=../lib/ui.sh
. "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=../lib/downloader.sh
. "$SCRIPT_DIR/lib/downloader.sh"
# shellcheck source=../lib/yaml_cleaner.sh
. "$SCRIPT_DIR/lib/yaml_cleaner.sh"
# shellcheck source=../lib/cloud_armor.sh
. "$SCRIPT_DIR/lib/cloud_armor.sh"

TF_DIR="$SCRIPT_DIR/terraform"

# ── Interactive UI or CI env vars ──────────────────────────────────────────
_prompt() {
  local var_name="$1" prompt_text="$2" default_val="${3:-}"
  local value="${!var_name:-}"
  if [[ -z "$value" ]]; then
    if [[ -n "$default_val" ]]; then
      read -rp "${prompt_text} [${default_val}]: " value
      value="${value:-$default_val}"
    else
      read -rp "${prompt_text}: " value
    fi
  fi
  printf -v "$var_name" '%s' "$value"
}

_prompt_action() {
  local value="${ACTION:-}"
  if [[ -z "$value" ]]; then
    read -rp "Action [plan/apply/destroy]: " value
    value="${value:-plan}"
  fi
  ACTION="$value"
}

print_banner "Ingress Deployer — GNP QA"

if [[ "${CI:-false}" != "true" ]]; then
  step "Deployment configuration"

  # Ticket ID — detect from CWD or prompt
  if [[ "$PWD" =~ /Tickets/(CTASK[0-9]+|TASK[0-9]+) ]]; then
    TICKET_ID="${BASH_REMATCH[1]}"
    info "Ticket detected from directory: $TICKET_ID"
  else
    _prompt TICKET_ID "Ticket ID (e.g. CTASK0123456)"
    if ! [[ "$TICKET_ID" =~ ^(CTASK|TASK)[0-9]+$ ]]; then
      error "Invalid ticket format. Use CTASK######## or TASK########"
      exit 1
    fi
  fi

  _prompt PROJECT_ID "Project ID (e.g. gnp-plus-qa)"
  _prompt INGRESS_URL "Ingress YAML URL or path"
fi

# ── Validate early required values ────────────────────────────────────────
for var in TICKET_ID PROJECT_ID INGRESS_URL; do
  if [[ -z "${!var:-}" ]]; then
    error "Missing required value: $var"
    exit 1
  fi
done

MANIFESTS_DIR="$SCRIPT_DIR/manifests/${PROJECT_ID}"
INGRESS_YAML="$MANIFESTS_DIR/ingress.yaml"
FRONTENDCONFIG_YAML="$MANIFESTS_DIR/frontendconfig.yaml"
TFVARS="$SCRIPT_DIR/environments/${PROJECT_ID}.tfvars"
TICKET_DIR="$TICKETS_BASE/$TICKET_ID"
mkdir -p "$TICKET_DIR" "$MANIFESTS_DIR"

LOG_FILE="$TICKET_DIR/ingress-deployer-$(date +%Y%m%d).log"
export LOG_FILE

# ── Auth check ─────────────────────────────────────────────────────────────
step "Authentication check"
if ! gcloud auth print-access-token &>/dev/null; then
  error "Not authenticated. Run: gcloud auth application-default login"
  exit 1
fi
ok "gcloud authentication verified"

# ── Download ingress YAML ──────────────────────────────────────────────────
step "Downloading ingress YAML"
download_ingress_yaml "$INGRESS_URL" "$INGRESS_YAML"

# Validate the downloaded file is valid YAML
if ! yq . "$INGRESS_YAML" &>/dev/null; then
  error "Downloaded file is not valid YAML: $INGRESS_YAML"
  exit 1
fi

# ── Auto-detect namespace, static IP and SSL cert from YAML ───────────────
_yaml_namespace=$(yq '.metadata.namespace // ""' "$INGRESS_YAML")
_yaml_static_ip=$(yq '.metadata.annotations["kubernetes.io/ingress.global-static-ip-name"] // ""' "$INGRESS_YAML")
_yaml_ssl_cert=$(yq '.metadata.annotations["ingress.gcp.kubernetes.io/pre-shared-cert"] // ""' "$INGRESS_YAML")

# Auto-discover SSL cert from project (user never has this value)
SSL_CERT_NAME=$(gcloud compute ssl-certificates list \
  --project="$PROJECT_ID" --format="value(name)" --limit=1 2>/dev/null || true)
if [[ -n "$SSL_CERT_NAME" ]]; then
  info "SSL certificate detected: $SSL_CERT_NAME"
else
  warn "No SSL certificate found in $PROJECT_ID — HTTPS frontend will not be configured"
fi

if [[ "${CI:-false}" != "true" ]]; then
  _prompt NAMESPACE      "Namespace" "${_yaml_namespace:-}"
  _prompt STATIC_IP_NAME "Static IP name" "${_yaml_static_ip:-}"
  _prompt_action
else
  NAMESPACE="${NAMESPACE:-$_yaml_namespace}"
  STATIC_IP_NAME="${STATIC_IP_NAME:-$_yaml_static_ip}"
fi

# ── Validate all required values ──────────────────────────────────────────
for var in TICKET_ID PROJECT_ID NAMESPACE STATIC_IP_NAME INGRESS_URL ACTION; do
  if [[ -z "${!var:-}" ]]; then
    error "Missing required value: $var"
    exit 1
  fi
done

case "$ACTION" in
  plan|apply|destroy) ;;
  *) error "Action must be: plan, apply, or destroy"; exit 1 ;;
esac

ok "YAML valid: $(yq '.metadata.name' "$INGRESS_YAML")"

# Strip GKE controller-managed fields to prevent drift and field manager conflicts
step "Cleaning YAML"
clean_ingress_yaml "$INGRESS_YAML" "$INGRESS_YAML"
ok "Ingress YAML cleaned"

# Generate FrontendConfig from ingress annotation (always managed by this deployer)
_fc_name=$(yq '.metadata.annotations["networking.gke.io/v1.FrontendConfig"] // ""' "$INGRESS_YAML")
if [[ -n "$_fc_name" ]]; then
  cat > "$FRONTENDCONFIG_YAML" << FCEOF
apiVersion: networking.gke.io/v1beta1
kind: FrontendConfig
metadata:
  name: ${_fc_name}
  namespace: ${NAMESPACE}
spec:
  redirectToHttps:
    enabled: true
    responseCodeName: MOVED_PERMANENTLY_DEFAULT
  sslPolicy: sslsecure
FCEOF
  ok "FrontendConfig generated: $_fc_name"
else
  info "No FrontendConfig annotation — skipping"
fi

if [[ -f "$FRONTENDCONFIG_YAML" ]]; then
  clean_ingress_yaml "$FRONTENDCONFIG_YAML" "$FRONTENDCONFIG_YAML"
  ok "FrontendConfig YAML cleaned"
fi

# Inject namespace into manifests if absent (kubernetes_manifest requires explicit namespace)
if [[ "$(yq '.metadata.namespace' "$INGRESS_YAML")" == "null" ]]; then
  yq -i ".metadata.namespace = \"$NAMESPACE\"" "$INGRESS_YAML"
  info "Injected namespace '$NAMESPACE' into ingress YAML"
fi

# Inject SSL certificate annotation if provided
if [[ -n "${SSL_CERT_NAME:-}" ]]; then
  yq -i ".metadata.annotations[\"ingress.gcp.kubernetes.io/pre-shared-cert\"] = \"$SSL_CERT_NAME\"" "$INGRESS_YAML"
  info "Injected SSL cert: $SSL_CERT_NAME"
fi
if [[ -f "$FRONTENDCONFIG_YAML" ]] && \
   [[ "$(yq '.metadata.namespace' "$FRONTENDCONFIG_YAML")" == "null" ]]; then
  yq -i ".metadata.namespace = \"$NAMESPACE\"" "$FRONTENDCONFIG_YAML"
  info "Injected namespace '$NAMESPACE' into FrontendConfig YAML"
fi

# ── Generate / overwrite environments/<project>.tfvars ────────────────────
step "Generating tfvars"
CLUSTER_NAME=$(gcloud container clusters list \
  --project="$PROJECT_ID" --format="value(name)" --limit=1 2>/dev/null || echo "")
CLUSTER_LOCATION=$(gcloud container clusters list \
  --project="$PROJECT_ID" --format="value(location)" --limit=1 2>/dev/null || echo "")

if [[ -z "$CLUSTER_NAME" ]]; then
  error "No GKE cluster found in project $PROJECT_ID"
  exit 1
fi

cat > "$TFVARS" << TFVARS
project_id       = "${PROJECT_ID}"
cluster_name     = "${CLUSTER_NAME}"
cluster_location = "${CLUSTER_LOCATION:-us-central1}"
namespace        = "${NAMESPACE}"
static_ip_name   = "${STATIC_IP_NAME}"
TFVARS
ok "tfvars written: $TFVARS"

# Connect kubectl to target cluster for backup and import operations
step "Connecting to cluster"
_get_credentials "$PROJECT_ID" "$CLUSTER_NAME" "${CLUSTER_LOCATION:-us-central1}"
ok "Connected to $CLUSTER_NAME (${CLUSTER_LOCATION:-us-central1})"

# ── Parse ingress metadata for kubectl commands ────────────────────────────
INGRESS_NAME=$(yq '.metadata.name' "$INGRESS_YAML")
info "Project:      $PROJECT_ID"
info "Namespace:    $NAMESPACE"
info "Ingress:      $INGRESS_NAME"
info "Static IP:    $STATIC_IP_NAME"
info "Ticket:       $TICKET_ID"
info "Log:          $LOG_FILE"

# ── Backup existing ingress (apply only) ──────────────────────────────────
if [[ "$ACTION" == "apply" ]]; then
  step "Backup existing ingress"
  BACKUP_FILE="$TICKET_DIR/ingress_backup_$(date +%Y%m%d_%H%M%S).yaml"
  if kubectl get ingress -n "$NAMESPACE" "$INGRESS_NAME" &>/dev/null 2>&1; then
    kubectl get ingress -n "$NAMESPACE" "$INGRESS_NAME" -o yaml > "$BACKUP_FILE"
    ok "Backup saved: $BACKUP_FILE"
    info "Rollback: kubectl apply -f $BACKUP_FILE"
  else
    info "No existing ingress found — fresh deployment"
  fi
fi

# ── Init backend ───────────────────────────────────────────────────────────
step "Backend initialization"
"$SCRIPT_DIR/scripts/init-backend.sh" "$PROJECT_ID"

# ── Import pre-existing resources (idempotent, non-fatal) ─────────────────
_tf_import() {
  local addr="$1" import_id="$2" label="$3"
  if terraform state list 2>/dev/null | grep -qF "$addr"; then
    info "$label already in state"
    return 0
  fi
  terraform state rm "$addr" 2>/dev/null || true
  if terraform import -var-file="$TFVARS" "$addr" "$import_id"; then
    ok "$label imported"
  else
    warn "Import failed for $label — apply may encounter conflicts"
  fi
}

if [[ "$ACTION" != "destroy" ]]; then
  step "State import"
  cd "$TF_DIR"

  if kubectl get namespace "$NAMESPACE" &>/dev/null 2>&1; then
    _tf_import "module.ingress.kubernetes_namespace_v1.ingress" \
      "$NAMESPACE" "Namespace $NAMESPACE"
  fi

  if gcloud compute addresses describe "$STATIC_IP_NAME" \
       --global --project="$PROJECT_ID" &>/dev/null 2>&1; then
    _tf_import "module.ingress.google_compute_global_address.ingress" \
      "projects/${PROJECT_ID}/global/addresses/${STATIC_IP_NAME}" \
      "Static IP $STATIC_IP_NAME"
  fi

  if kubectl get ingress -n "$NAMESPACE" "$INGRESS_NAME" &>/dev/null 2>&1; then
    _tf_import "module.ingress.kubernetes_manifest.ingress" \
      "apiVersion=networking.k8s.io/v1,kind=Ingress,namespace=${NAMESPACE},name=${INGRESS_NAME}" \
      "Ingress $INGRESS_NAME"
  fi

  if [[ -f "$FRONTENDCONFIG_YAML" ]]; then
    fc_name=$(yq '.metadata.name' "$FRONTENDCONFIG_YAML" 2>/dev/null || true)
    if [[ -n "$fc_name" ]] && \
       kubectl get frontendconfig -n "$NAMESPACE" "$fc_name" &>/dev/null 2>&1; then
      _tf_import "module.ingress.kubernetes_manifest.frontendconfig[0]" \
        "apiVersion=networking.gke.io/v1beta1,kind=FrontendConfig,namespace=${NAMESPACE},name=${fc_name}" \
        "FrontendConfig $fc_name"
    fi
  fi
fi

# ── Terraform validate ─────────────────────────────────────────────────────
step "Terraform validate"
cd "$TF_DIR"
terraform validate -no-color
ok "Configuration valid"

# ── Terraform plan / apply / destroy ──────────────────────────────────────
PLAN_FILE="$TICKET_DIR/plan-$(date +%Y%m%d_%H%M%S).tfplan"

_do_apply() {
  terraform apply -input=false -no-color "$PLAN_FILE" \
    | tee -a "$LOG_FILE"
  ok "Apply complete"
  step "Waiting for ingress stabilization"
  wait_for_ingress_ip "$NAMESPACE" "$INGRESS_NAME" 420
  attach_cloud_armor "$PROJECT_ID" "$NAMESPACE"
}

step "Terraform $ACTION"
case "$ACTION" in
  plan)
    terraform plan -var-file="$TFVARS" -input=false -no-color -out="$PLAN_FILE" \
      | tee -a "$LOG_FILE"
    ok "Plan complete — saved: $PLAN_FILE"
    if [[ "${CI:-false}" != "true" ]]; then
      read -rp "Apply this plan? [y/N]: " _confirm
      if [[ "${_confirm,,}" == "y" ]]; then
        step "Terraform apply"
        _do_apply
      else
        info "Apply skipped"
      fi
    fi
    ;;
  apply)
    terraform plan -var-file="$TFVARS" -input=false -no-color -out="$PLAN_FILE" \
      | tee -a "$LOG_FILE"
    ok "Plan complete — saved: $PLAN_FILE"
    _do_apply
    ;;
  destroy)
    terraform destroy -var-file="$TFVARS" -input=false -auto-approve -no-color \
      | tee -a "$LOG_FILE"
    ok "Destroy complete"
    ;;
esac

ok "Done. Log: $LOG_FILE"
