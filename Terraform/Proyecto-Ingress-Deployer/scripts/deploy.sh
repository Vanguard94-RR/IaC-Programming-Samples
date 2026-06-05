#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CENTRAL_PROJECT="${CENTRAL_PROJECT:-gnp-fleets-qa}"
TICKETS_BASE="${TICKETS_BASE:-/home/admin/Documents/GNP/Tickets}"
# Same bucket as Terraform state — set after PROJECT_ID is known
# shellcheck source=../lib/ui.sh
. "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=../lib/downloader.sh
. "$SCRIPT_DIR/lib/downloader.sh"
# shellcheck source=../lib/yaml_cleaner.sh
. "$SCRIPT_DIR/lib/yaml_cleaner.sh"
# shellcheck source=../lib/cloud_armor.sh
. "$SCRIPT_DIR/lib/cloud_armor.sh"
# shellcheck source=../lib/network_checks.sh
. "$SCRIPT_DIR/lib/network_checks.sh"

TF_DIR="$SCRIPT_DIR/terraform"

# ── Idempotency Flags ──────────────────────────────────────────────────────
SKIP_DOWNLOAD="${SKIP_DOWNLOAD:-false}"
DRY_RUN_ONLY="${DRY_RUN_ONLY:-false}"

# Parse command-line flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-download)
      SKIP_DOWNLOAD="true"
      shift
      ;;
    --dry-run-only)
      DRY_RUN_ONLY="true"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

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

# ── GitLab token resolution ────────────────────────────────────────────────
# Auto-load from well-known path if URL is GitLab and token not in env
_GITLAB_TOKEN_FILE="${GITLAB_TOKEN_FILE:-/home/admin/Documents/GNP/PersonalGitLabToken}"
if [[ "$INGRESS_URL" =~ gitlab\. ]] && [[ -z "${GITLAB_TOKEN:-}" ]]; then
  if [[ -f "$_GITLAB_TOKEN_FILE" ]]; then
    GITLAB_TOKEN=$(tr -d '[:space:]' < "$_GITLAB_TOKEN_FILE")
    export GITLAB_TOKEN
    info "GitLab token loaded from $_GITLAB_TOKEN_FILE"
  elif [[ "${CI:-false}" != "true" ]]; then
    read -rsp "GitLab Personal Access Token: " GITLAB_TOKEN
    echo
    export GITLAB_TOKEN
  else
    error "GitLab URL requires GITLAB_TOKEN env var"
    exit 1
  fi
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
COMPANIONS_DIR="$MANIFESTS_DIR/companions"
TFVARS="$SCRIPT_DIR/environments/${PROJECT_ID}.tfvars"
TICKET_DIR="$TICKETS_BASE/$TICKET_ID"
mkdir -p "$TICKET_DIR" "$MANIFESTS_DIR" "$COMPANIONS_DIR"

LOG_FILE="$TICKET_DIR/ingress-deployer-$(date +%Y%m%d).log"
export LOG_FILE

# Bucket = same as Terraform state: gs://<project>-tf-state
# Path: ingress-artifacts/<ticket>/<date>/
GCS_BUCKET="${GCS_BUCKET:-gs://${PROJECT_ID}-tf-state}"
_GCS_PREFIX="${GCS_BUCKET}/ingress-artifacts/${TICKET_ID}/$(date +%Y%m%d)"

# Upload a file to GCS — non-fatal, warn on failure
_gcs_upload() {
  local src="$1" label="${2:-$(basename "$1")}"
  if [[ -z "${GCS_BUCKET:-}" ]]; then return 0; fi
  if gsutil cp "$src" "${_GCS_PREFIX}/$(basename "$src")" &>/dev/null; then
    ok "GCS upload: $label → ${_GCS_PREFIX}/"
  else
    warn "GCS upload failed: $label (continuing)"
  fi
}

# ── Auth check ─────────────────────────────────────────────────────────────
step "Authentication check"
if ! gcloud auth print-access-token &>/dev/null; then
  error "Not authenticated. Run: gcloud auth login"
  exit 1
fi
ok "gcloud authentication verified"


# ── Download ingress YAML ──────────────────────────────────────────────────
step "Downloading ingress YAML"

# Idempotency: skip if local copy is valid YAML
if [[ "$SKIP_DOWNLOAD" == "true" ]] && [[ -f "$INGRESS_YAML" ]] && yq . "$INGRESS_YAML" &>/dev/null; then
  ok "Reusing local manifest: $INGRESS_YAML (--skip-download)"
else
  download_ingress_yaml "$INGRESS_URL" "$INGRESS_YAML"
fi

# Validate the downloaded file is valid YAML
if ! yq . "$INGRESS_YAML" &>/dev/null; then
  error "Downloaded file is not valid YAML: $INGRESS_YAML"
  exit 1
fi

# ── Auto-detect namespace, static IP and SSL cert from YAML ───────────────
_yaml_namespace=$(yq 'select(.kind == "Ingress") | .metadata.namespace // ""' "$INGRESS_YAML" | head -1)
_yaml_static_ip=$(yq 'select(.kind == "Ingress") | .metadata.annotations["kubernetes.io/ingress.global-static-ip-name"] // ""' "$INGRESS_YAML" | head -1)
_yaml_ssl_cert=$(yq 'select(.kind == "Ingress") | .metadata.annotations["ingress.gcp.kubernetes.io/pre-shared-cert"] // ""' "$INGRESS_YAML" | head -1)

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
  _prompt STATIC_IP_NAME "Static IP name (leave empty for ephemeral IP)" "${_yaml_static_ip:-}"
  _prompt_action
else
  NAMESPACE="${NAMESPACE:-$_yaml_namespace}"
  STATIC_IP_NAME="${STATIC_IP_NAME:-$_yaml_static_ip}"
fi

# ── Validate all required values ──────────────────────────────────────────
for var in TICKET_ID PROJECT_ID NAMESPACE INGRESS_URL ACTION; do
  if [[ -z "${!var:-}" ]]; then
    error "Missing required value: $var"
    exit 1
  fi
done

case "$ACTION" in
  plan|apply|destroy) ;;
  *) error "Action must be: plan, apply, or destroy"; exit 1 ;;
esac

ok "YAML valid: $(yq 'select(.kind == "Ingress") | .metadata.name' "$INGRESS_YAML" | head -1)"

# Extract companion IaC resources from multi-document YAML before Ingress extraction
step "Extracting companion resources"
extract_companions "$INGRESS_YAML" "$COMPANIONS_DIR"
ok "Companion extraction complete"

# Strip GKE controller-managed fields to prevent drift and field manager conflicts
step "Cleaning YAML"
clean_ingress_yaml "$INGRESS_YAML" "$INGRESS_YAML"
ok "Ingress YAML cleaned"

# Extract only Ingress document — yamldecode requires single-document YAML
yq 'select(.kind == "Ingress")' "$INGRESS_YAML" > "${INGRESS_YAML}.tmp" \
  && mv "${INGRESS_YAML}.tmp" "$INGRESS_YAML"
ok "Extracted Ingress document (single-document for Terraform)"

# Generate FrontendConfig if annotation present but not already extracted as companion
_fc_name=$(yq 'select(.kind == "Ingress") | .metadata.annotations["networking.gke.io/v1.FrontendConfig"] // ""' "$INGRESS_YAML" | head -1)
if [[ -n "$_fc_name" ]]; then
  _fc_companion=$(ls "$COMPANIONS_DIR"/FrontendConfig-*-"${_fc_name}".yaml 2>/dev/null | head -1 || true)
  if [[ -z "$_fc_companion" ]]; then
    _fc_companion="$COMPANIONS_DIR/FrontendConfig-${NAMESPACE}-${_fc_name}.yaml"
    cat > "$_fc_companion" << FCEOF
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
    clean_ingress_yaml "$_fc_companion" "$_fc_companion"
    ok "FrontendConfig generated: $_fc_name → companions/"
  else
    info "FrontendConfig already extracted from source YAML: $_fc_name"
  fi
else
  info "No FrontendConfig annotation — skipping"
fi

# Inject namespace into manifests if absent (kubernetes_manifest requires explicit namespace)
if [[ "$(yq 'select(.kind == "Ingress") | .metadata.namespace' "$INGRESS_YAML" | head -1)" == "null" ]]; then
  yq -i '(select(.kind == "Ingress") | .metadata.namespace) = "'"$NAMESPACE"'"' "$INGRESS_YAML"
  info "Injected namespace '$NAMESPACE' into ingress YAML"
else
  info "Namespace already present in ingress YAML: $(yq 'select(.kind == "Ingress") | .metadata.namespace' "$INGRESS_YAML" | head -1)"
fi

# Inject SSL certificate annotation if provided
if [[ -n "${SSL_CERT_NAME:-}" ]]; then
  yq -i '(select(.kind == "Ingress") | .metadata.annotations["ingress.gcp.kubernetes.io/pre-shared-cert"]) = "'"$SSL_CERT_NAME"'"' "$INGRESS_YAML"
  info "Injected SSL cert: $SSL_CERT_NAME"
fi
if [[ -n "${STATIC_IP_NAME:-}" ]]; then
  yq -i '(select(.kind == "Ingress") | .metadata.annotations["kubernetes.io/ingress.global-static-ip-name"]) = "'"$STATIC_IP_NAME"'"' "$INGRESS_YAML"
  info "Injected static IP annotation: $STATIC_IP_NAME"
else
  info "No static IP name set — GKE will assign an ephemeral IP"
fi
for _cf in "$COMPANIONS_DIR"/*.yaml; do
  [[ -f "$_cf" ]] || continue
  if [[ "$(yq '.metadata.namespace // "null"' "$_cf")" == "null" ]]; then
    yq -i ".metadata.namespace = \"$NAMESPACE\"" "$_cf"
    info "Injected namespace into companion: $(basename "$_cf")"
  fi
done

# ── Generate / overwrite environments/<project>.tfvars ────────────────────
step "Generating tfvars"

# Cluster selection: use env var, or auto-detect with prompt when multiple exist
if [[ -z "${CLUSTER_NAME:-}" ]]; then
  mapfile -t _clusters < <(gcloud container clusters list \
    --project="$PROJECT_ID" --format="value(name,location)" 2>/dev/null || true)

  if [[ ${#_clusters[@]} -eq 0 ]]; then
    error "No GKE cluster found in project $PROJECT_ID"
    exit 1
  elif [[ ${#_clusters[@]} -eq 1 ]]; then
    CLUSTER_NAME=$(awk '{print $1}' <<< "${_clusters[0]}")
    CLUSTER_LOCATION=$(awk '{print $2}' <<< "${_clusters[0]}")
    info "Cluster auto-detected: $CLUSTER_NAME ($CLUSTER_LOCATION)"
  else
    if [[ "${CI:-false}" == "true" ]]; then
      error "Multiple clusters found in $PROJECT_ID — set CLUSTER_NAME env var"
      exit 1
    fi
    step "Select cluster for $PROJECT_ID"
    for i in "${!_clusters[@]}"; do
      printf "  [%d] %s\n" "$((i+1))" "${_clusters[$i]}"
    done
    _sel=""
    while true; do
      read -rp "Cluster number [1-${#_clusters[@]}]: " _sel
      if [[ "$_sel" =~ ^[0-9]+$ ]] && (( _sel >= 1 && _sel <= ${#_clusters[@]} )); then
        break
      fi
      warn "Invalid selection, try again"
    done
    CLUSTER_NAME=$(awk '{print $1}' <<< "${_clusters[$((_sel-1))]}")
    CLUSTER_LOCATION=$(awk '{print $2}' <<< "${_clusters[$((_sel-1))]}")
    ok "Selected: $CLUSTER_NAME ($CLUSTER_LOCATION)"
  fi
else
  # CLUSTER_NAME provided — look up its location if not set
  if [[ -z "${CLUSTER_LOCATION:-}" ]]; then
    CLUSTER_LOCATION=$(gcloud container clusters list \
      --project="$PROJECT_ID" --filter="name=$CLUSTER_NAME" \
      --format="value(location)" 2>/dev/null || echo "")
  fi
  info "Cluster from env: $CLUSTER_NAME (${CLUSTER_LOCATION:-unknown})"
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
INGRESS_NAME=$(yq 'select(.kind == "Ingress") | .metadata.name' "$INGRESS_YAML" | head -1)
info "Project:      $PROJECT_ID"
info "Namespace:    $NAMESPACE"
info "Ingress:      $INGRESS_NAME"
info "Static IP:    ${STATIC_IP_NAME:-ephemeral}"
info "Ticket:       $TICKET_ID"
info "Log:          $LOG_FILE"

# ── Diff current vs new ingress (spec only — paths and services) ──────────
step "Ingress diff (current → new)"
_diff_spec() {
  local label="$1" kind="$2" name="$3" new_yaml="$4"
  local tmp_cur tmp_new
  tmp_cur=$(mktemp) tmp_new=$(mktemp)

  local raw_cur
  raw_cur=$(kubectl get "$kind" "$name" -n "$NAMESPACE" -o yaml 2>/dev/null || true)
  if [[ -z "$raw_cur" ]]; then
    info "$label: not found in cluster — will be created"
    rm -f "$tmp_cur" "$tmp_new"; return 0
  fi

  # Extract spec + user-managed annotations, strip all GKE controller-owned keys
  _extract_comparable() {
    yq '{
      "spec": .spec,
      "annotations": (.metadata.annotations // {} | del(
        .["ingress.kubernetes.io/backends"],
        .["ingress.kubernetes.io/forwarding-rule"],
        .["ingress.kubernetes.io/https-forwarding-rule"],
        .["ingress.kubernetes.io/https-target-proxy"],
        .["ingress.kubernetes.io/target-proxy"],
        .["ingress.kubernetes.io/url-map"],
        .["ingress.kubernetes.io/ssl-cert"],
        .["kubectl.kubernetes.io/last-applied-configuration"]
      ))
    }'
  }

  printf '%s' "$raw_cur" | _extract_comparable > "$tmp_cur" 2>/dev/null
  _extract_comparable < "$new_yaml"  > "$tmp_new" 2>/dev/null

  local delta
  delta=$(diff --color=always -u \
    --label "current ($name)" \
    --label "new     ($name)" \
    "$tmp_cur" "$tmp_new" 2>/dev/null || true)

  if [[ -z "$delta" ]]; then
    ok "$label: no changes (spec + annotations)"
  else
    warn "$label: changes detected"
    printf '%s\n' "$delta"
  fi
  rm -f "$tmp_cur" "$tmp_new"
}

if kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" &>/dev/null 2>&1; then
  _diff_spec "Ingress $INGRESS_NAME" "ingress" "$INGRESS_NAME" "$INGRESS_YAML"
else
  info "Ingress $INGRESS_NAME not found — fresh deployment"
fi

for _cf in "$COMPANIONS_DIR"/*.yaml; do
  [[ -f "$_cf" ]] || continue
  _cf_kind=$(yq '.kind' "$_cf")
  _cf_name_val=$(yq '.metadata.name' "$_cf")
  if kubectl get "$_cf_kind" "$_cf_name_val" -n "$NAMESPACE" &>/dev/null 2>&1; then
    _diff_spec "Companion ${_cf_kind}/${_cf_name_val}" \
      "${_cf_kind,,}" "$_cf_name_val" "$_cf"
  else
    info "Companion ${_cf_kind}/${_cf_name_val} not found — will be created"
  fi
done

# ── Backup existing ingress (apply only) ──────────────────────────────────
if [[ "$ACTION" == "apply" ]]; then
  step "Backup existing ingress"
  BACKUP_FILE="$TICKET_DIR/ingress_backup_$(date +%Y%m%d_%H%M%S).yaml"
  if kubectl get ingress -n "$NAMESPACE" "$INGRESS_NAME" &>/dev/null 2>&1; then
    kubectl get ingress -n "$NAMESPACE" "$INGRESS_NAME" -o yaml > "$BACKUP_FILE"
    ok "Backup saved: $BACKUP_FILE"
    info "Rollback: kubectl apply -f $BACKUP_FILE"
    _gcs_upload "$BACKUP_FILE" "ingress backup"
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
  if terraform import -var-file="$TFVARS" "$addr" "$import_id"; then
    ok "$label imported"
  else
    warn "Import failed for $label — apply may encounter conflicts"
    terraform state rm "$addr" 2>/dev/null || true
  fi
}

if [[ "$ACTION" != "destroy" ]]; then
  step "State import"
  cd "$TF_DIR"

  if kubectl get namespace "$NAMESPACE" &>/dev/null 2>&1; then
    _tf_import "module.ingress.kubernetes_namespace_v1.ingress" \
      "$NAMESPACE" "Namespace $NAMESPACE"
  fi

  if [[ -n "${STATIC_IP_NAME:-}" ]]; then
    if gcloud compute addresses describe "$STATIC_IP_NAME" \
         --global --project="$PROJECT_ID" &>/dev/null 2>&1; then
      _tf_import "module.ingress.google_compute_global_address.ingress[0]" \
        "projects/${PROJECT_ID}/global/addresses/${STATIC_IP_NAME}" \
        "Static IP $STATIC_IP_NAME"
    fi
  fi

  if kubectl get ingress -n "$NAMESPACE" "$INGRESS_NAME" &>/dev/null 2>&1; then
    _tf_import "module.ingress.kubernetes_manifest.ingress" \
      "apiVersion=networking.k8s.io/v1,kind=Ingress,namespace=${NAMESPACE},name=${INGRESS_NAME}" \
      "Ingress $INGRESS_NAME"
  fi

  # Import pre-existing companion resources
  for _cf in "$COMPANIONS_DIR"/*.yaml; do
    [[ -f "$_cf" ]] || continue
    _cf_kind=$(yq '.kind' "$_cf")
    _cf_ns=$(yq '.metadata.namespace // ""' "$_cf")
    _cf_name_val=$(yq '.metadata.name' "$_cf")
    _cf_api=$(yq '.apiVersion' "$_cf")
    _cf_key="${_cf_kind}/${_cf_ns}/${_cf_name_val}"
    if kubectl get "$_cf_kind" "$_cf_name_val" -n "$NAMESPACE" &>/dev/null 2>&1; then
      _tf_import \
        "module.ingress.kubernetes_manifest.companion[\"${_cf_key}\"]" \
        "apiVersion=${_cf_api},kind=${_cf_kind},namespace=${NAMESPACE},name=${_cf_name_val}" \
        "Companion ${_cf_key}"
    fi
  done

  # One-time state migration: frontendconfig[0] → companion["FrontendConfig/namespace/name"]
  if terraform state list 2>/dev/null | grep -q "kubernetes_manifest\.frontendconfig\[0\]"; then
    _fc_legacy_file=$(ls "$COMPANIONS_DIR"/FrontendConfig-*.yaml 2>/dev/null | head -1 || true)
    if [[ -z "$_fc_legacy_file" ]]; then
      error "Legacy FrontendConfig state found but no FrontendConfig companion file in companions/. Move the companion file first."
      exit 1
    fi
    _fc_legacy_ns=$(yq '.metadata.namespace // ""' "$_fc_legacy_file")
    _fc_legacy_name=$(yq '.metadata.name' "$_fc_legacy_file")
    _fc_legacy_key="FrontendConfig/${_fc_legacy_ns}/${_fc_legacy_name}"
    info "Migrating legacy FrontendConfig state → companion[\"$_fc_legacy_key\"]"
    terraform state mv \
      "module.ingress.kubernetes_manifest.frontendconfig[0]" \
      "module.ingress.kubernetes_manifest.companion[\"${_fc_legacy_key}\"]"
  fi
fi

# IP conflict pre-flight: detect forwarding rules that would block LB provisioning
if [[ -n "${STATIC_IP_NAME:-}" ]] && [[ "$ACTION" != "destroy" ]]; then
  step "IP conflict pre-flight check"
  check_ip_conflicts "$PROJECT_ID" "$STATIC_IP_NAME" "$INGRESS_NAME"
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
  # Upload applied manifests for rollback reference
  _gcs_upload "$INGRESS_YAML" "ingress.yaml"
  for _cf in "$COMPANIONS_DIR"/*.yaml; do
    [[ -f "$_cf" ]] && _gcs_upload "$_cf" "companions/$(basename "$_cf")"
  done
  _gcs_upload "$LOG_FILE" "deploy.log"
  step "Waiting for ingress stabilization"
  wait_for_ingress_ip "$NAMESPACE" "$INGRESS_NAME" 1200 \
    || warn "Ingress IP timeout — LB still provisioning. Check GKE console."
  attach_cloud_armor "$PROJECT_ID" "$NAMESPACE"
}

step "Terraform $ACTION"
case "$ACTION" in
  plan)
    terraform plan -var-file="$TFVARS" -input=false -no-color -out="$PLAN_FILE" \
      | tee -a "$LOG_FILE"
    ok "Plan complete — saved: $PLAN_FILE"
    _gcs_upload "$PLAN_FILE" "terraform.tfplan"
    
    # Exit early if dry-run-only is set
    if [[ "$DRY_RUN_ONLY" == "true" ]]; then
      step "Dry-run complete (--dry-run-only)"
      ok "No changes applied. Review plan: $PLAN_FILE"
      exit 0
    fi
    
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
    _gcs_upload "$PLAN_FILE" "terraform.tfplan"
    _do_apply
    ;;
  destroy)
    _kubectl_delete_with_finalizer_fallback() {
      local kind="$1" name="$2" ns="$3" state_addr="$4"

      if ! kubectl get "$kind" -n "$ns" "$name" &>/dev/null 2>&1; then
        info "$kind/$name not found — skipping"
        terraform state rm "$state_addr" 2>/dev/null || true
        return 0
      fi

      info "Deleting $kind/$name — waiting up to 15m for GKE LB deprovision..."
      kubectl delete "$kind" -n "$ns" "$name" --ignore-not-found 2>/dev/null || true

      if ! kubectl wait --for=delete "$kind/$name" -n "$ns" --timeout=1200s 2>/dev/null; then
        warn "GKE did not remove finalizer in 15m — forcing finalizer removal"
        kubectl patch "$kind/$name" -n "$ns" \
          -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        # Wait up to 30s more after force-patch
        kubectl wait --for=delete "$kind/$name" -n "$ns" --timeout=30s 2>/dev/null || true
      fi

      ok "$kind/$name deleted"
      terraform state rm "$state_addr" 2>/dev/null || true
    }

    step "Deleting ingress"
    _kubectl_delete_with_finalizer_fallback \
      "ingress" "$INGRESS_NAME" "$NAMESPACE" \
      "module.ingress.kubernetes_manifest.ingress"

    for _cf in "$COMPANIONS_DIR"/*.yaml; do
      [[ -f "$_cf" ]] || continue
      _cf_kind=$(yq '.kind' "$_cf")
      _cf_ns=$(yq '.metadata.namespace // ""' "$_cf")
      _cf_name_val=$(yq '.metadata.name' "$_cf")
      if echo "$_LIFECYCLE_KINDS" | grep -qw "$_cf_kind"; then
        step "Deleting companion $_cf_kind/$_cf_name_val"
        _kubectl_delete_with_finalizer_fallback \
          "$_cf_kind" "$_cf_name_val" "$NAMESPACE" \
          "module.ingress.kubernetes_manifest.companion[\"${_cf_kind}/${_cf_ns}/${_cf_name_val}\"]"
      else
        info "Skipping destroy for create-only companion: $_cf_kind/$_cf_name_val"
      fi
    done

    if [[ -n "${STATIC_IP_NAME:-}" ]]; then
      step "Destroying static IP"
      terraform destroy -var-file="$TFVARS" -input=false -auto-approve -no-color \
        -target="module.ingress.google_compute_global_address.ingress[0]" \
        | tee -a "$LOG_FILE"
    fi
    ok "Destroy complete (namespace preserved)"
    ;;
esac

ok "Done. Log: $LOG_FILE"
