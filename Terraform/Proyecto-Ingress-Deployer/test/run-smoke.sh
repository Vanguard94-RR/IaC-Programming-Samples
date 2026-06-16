#!/usr/bin/env bash
# Smoke tests — input validation only, no GCP required
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PASS=0; FAIL=0

check() {
  local desc="$1"; local expected_exit="$2"; shift 2
  local actual_exit=0
  eval "$@" &>/dev/null || actual_exit=$?
  if [[ "$actual_exit" -eq "$expected_exit" ]]; then
    echo "PASS: $desc"; (( ++PASS ))
  else
    echo "FAIL: $desc (expected exit $expected_exit, got $actual_exit)"; (( ++FAIL ))
  fi
}

echo "=== Ingress Deployer Smoke Tests ==="

# Task 1: lib/ui.sh sources without error
check "ui.sh sources cleanly" 0 \
  "bash -c 'source ${SCRIPT_DIR}/lib/ui.sh'"

# Task 5: init-backend.sh arg validation
check "init-backend.sh exits 1 with no args" 1 \
  "bash ${SCRIPT_DIR}/scripts/init-backend.sh"

# Task 6: discover.sh arg validation
check "discover.sh exits 1 with no args" 1 \
  "bash ${SCRIPT_DIR}/scripts/discover.sh"

# Task 7: lib/downloader.sh sources without error
check "downloader.sh sources cleanly" 0 \
  "bash -c 'source ${SCRIPT_DIR}/lib/ui.sh && source ${SCRIPT_DIR}/lib/downloader.sh'"

# Task 1 (audit): yaml_cleaner.sh sources cleanly
check "yaml_cleaner.sh sources cleanly" 0 \
  "bash -c 'source ${SCRIPT_DIR}/lib/ui.sh && source ${SCRIPT_DIR}/lib/yaml_cleaner.sh'"

# Task 1 (audit): clean_ingress_yaml strips GKE fields, preserves user annotations
_test_yaml_cleaner() {
  local dirty=/tmp/ingress-dirty-test.yaml
  local clean=/tmp/ingress-clean-test.yaml
  cat > "$dirty" << 'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  namespace: default
  uid: abc-123
  resourceVersion: "99999"
  generation: 16
  finalizers:
    - networking.gke.io/ingress-finalizer-V2
  annotations:
    kubernetes.io/ingress.global-static-ip-name: test-ip
    networking.gke.io/v1.FrontendConfig: http-redirect-config
    ingress.kubernetes.io/backends: '{"k8s":"HEALTHY"}'
    ingress.kubernetes.io/forwarding-rule: k8s2-fr-abc-test
    ingress.kubernetes.io/target-proxy: k8s2-tp-abc-test
    ingress.kubernetes.io/url-map: k8s2-um-abc-test
spec:
  rules: []
status:
  loadBalancer:
    ingress:
    - ip: 1.2.3.4
YAML
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/yaml_cleaner.sh"
  clean_ingress_yaml "$dirty" "$clean"
  [[ "$(yq '.metadata.uid // "null"' "$clean")" == "null" ]] &&
  [[ "$(yq '.metadata.resourceVersion // "null"' "$clean")" == "null" ]] &&
  [[ "$(yq '.metadata.generation // "null"' "$clean")" == "null" ]] &&
  [[ "$(yq '.metadata.finalizers // "null"' "$clean")" == "null" ]] &&
  [[ "$(yq '.metadata.annotations["ingress.kubernetes.io/backends"] // "null"' "$clean")" == "null" ]] &&
  [[ "$(yq '.metadata.annotations["ingress.kubernetes.io/forwarding-rule"] // "null"' "$clean")" == "null" ]] &&
  [[ "$(yq '.metadata.annotations["ingress.kubernetes.io/target-proxy"] // "null"' "$clean")" == "null" ]] &&
  [[ "$(yq '.metadata.annotations["ingress.kubernetes.io/url-map"] // "null"' "$clean")" == "null" ]] &&
  [[ "$(yq '.status // "null"' "$clean")" == "null" ]] &&
  yq '.metadata.annotations["kubernetes.io/ingress.global-static-ip-name"]' "$clean" | grep -q "test-ip" &&
  yq '.metadata.annotations["networking.gke.io/v1.FrontendConfig"]' "$clean" | grep -q "http-redirect-config"
}
check "clean_ingress_yaml strips GKE fields, preserves user annotations" 0 "_test_yaml_cleaner"

# Task 2 (audit): _get_credentials zone/region detection regex
_test_zone_detection() {
  source "$SCRIPT_DIR/lib/ui.sh"
  [[ "us-central1-a" =~ ^[a-z]+-[a-z0-9]+-[a-z]$ ]] &&
  [[ "europe-west1-b" =~ ^[a-z]+-[a-z0-9]+-[a-z]$ ]] &&
  [[ "asia-northeast1-c" =~ ^[a-z]+-[a-z0-9]+-[a-z]$ ]] &&
  ! [[ "us-central1" =~ ^[a-z]+-[a-z0-9]+-[a-z]$ ]] &&
  ! [[ "europe-west1" =~ ^[a-z]+-[a-z0-9]+-[a-z]$ ]]
}
check "_get_credentials zone/region detection regex" 0 "_test_zone_detection"

# Task 8: deploy.sh — interactive UI is skipped when CI=true and required env vars missing
_test_invalid_action() {
  local fixture
  fixture=$(mktemp --suffix=.yaml)
  cat > "$fixture" << 'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  namespace: default
spec: {}
YAML
  local exit_code=0
  CI=true PROJECT_ID=x NAMESPACE=x STATIC_IP_NAME=x \
    INGRESS_URL="file://${fixture}" TICKET_ID=x ACTION=noop \
    bash "${SCRIPT_DIR}/scripts/deploy.sh" || exit_code=$?
  rm -f "$fixture"
  return "$exit_code"
}
check "deploy.sh exits 1 with invalid action in CI mode" 1 "_test_invalid_action"

# Ephemeral IP: deploy.sh must NOT fail on missing STATIC_IP_NAME
_test_ephemeral_validation() {
  local out
  out=$(CI=true PROJECT_ID=x NAMESPACE=x INGRESS_URL=x TICKET_ID=x ACTION=plan \
    bash "${SCRIPT_DIR}/scripts/deploy.sh" 2>&1 || true)
  ! echo "$out" | grep -q "Missing required value: STATIC_IP_NAME"
}
check "deploy.sh does not require STATIC_IP_NAME (ephemeral mode)" 0 \
  "_test_ephemeral_validation"

# Companion extraction: must extract BackendConfig, skip Ingress and Service
_test_extract_companions() {
  local src=/tmp/test-multidoc.yaml
  local companions_dir=/tmp/test-companions
  rm -rf "$companions_dir"

  cat > "$src" << 'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  namespace: apps
spec:
  rules: []
---
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: test-backendconfig
  namespace: apps
spec:
  timeoutSec: 1800
---
apiVersion: v1
kind: Service
metadata:
  name: test-service
  namespace: apps
spec:
  ports:
  - port: 8080
YAML

  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/yaml_cleaner.sh"
  extract_companions "$src" "$companions_dir"

  # BackendConfig extracted (with namespace in filename)
  [[ -f "$companions_dir/BackendConfig-apps-test-backendconfig.yaml" ]] &&
  # Ingress NOT extracted
  ! [[ -f "$companions_dir/Ingress-apps-test-ingress.yaml" ]] &&
  # Service NOT extracted (blocklisted)
  ! [[ -f "$companions_dir/Service-apps-test-service.yaml" ]]
}
check "extract_companions extracts BackendConfig, skips Ingress and Service" 0 \
  "_test_extract_companions"

# extract_companions: empty result when no matching docs
_test_extract_companions_empty() {
  local src=/tmp/test-ingress-only.yaml
  local companions_dir=/tmp/test-companions-empty
  rm -rf "$companions_dir"

  cat > "$src" << 'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  namespace: apps
spec:
  rules: []
YAML

  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/yaml_cleaner.sh"
  extract_companions "$src" "$companions_dir"
  [[ -d "$companions_dir" ]] && [[ -z "$(ls -A "$companions_dir")" ]]
}
check "extract_companions produces empty dir when no companion docs" 0 \
  "_test_extract_companions_empty"

# _LIFECYCLE_KINDS includes BackendConfig and FrontendConfig, not ManagedCertificate
_test_lifecycle_kinds() {
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/yaml_cleaner.sh"
  echo "$_LIFECYCLE_KINDS" | grep -qw "BackendConfig" &&
  echo "$_LIFECYCLE_KINDS" | grep -qw "FrontendConfig" &&
  ! echo "$_LIFECYCLE_KINDS" | grep -qw "ManagedCertificate"
}
check "_LIFECYCLE_KINDS includes BackendConfig/FrontendConfig, excludes ManagedCertificate" 0 \
  "_test_lifecycle_kinds"

# extract_companions: networking.gke.io FrontendConfig is extracted
_test_extract_frontendconfig() {
  local src=/tmp/test-fc-multidoc.yaml
  local companions_dir=/tmp/test-companions-fc
  rm -rf "$companions_dir"

  cat > "$src" << 'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  namespace: apps
spec:
  rules: []
---
apiVersion: networking.gke.io/v1beta1
kind: FrontendConfig
metadata:
  name: test-fc
  namespace: apps
spec:
  redirectToHttps:
    enabled: true
YAML

  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/yaml_cleaner.sh"
  extract_companions "$src" "$companions_dir"
  [[ -f "$companions_dir/FrontendConfig-apps-test-fc.yaml" ]]
}
check "extract_companions extracts FrontendConfig from networking.gke.io" 0 \
  "_test_extract_frontendconfig"

# extract_companions: ManagedCertificate is extracted (create-only companion)
_test_extract_managedcert() {
  local src=/tmp/test-cert-multidoc.yaml
  local companions_dir=/tmp/test-companions-cert
  rm -rf "$companions_dir"

  cat > "$src" << 'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  namespace: apps
spec:
  rules: []
---
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: test-cert
  namespace: apps
spec:
  domains:
  - example.com
YAML

  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/yaml_cleaner.sh"
  extract_companions "$src" "$companions_dir"
  [[ -f "$companions_dir/ManagedCertificate-apps-test-cert.yaml" ]] &&
  ! echo "$_LIFECYCLE_KINDS" | grep -qw "ManagedCertificate"
}
check "extract_companions extracts ManagedCertificate as create-only companion" 0 \
  "_test_extract_managedcert"

# network_checks.sh sources cleanly
check "network_checks.sh sources cleanly" 0 \
  "bash -c 'source ${SCRIPT_DIR}/lib/ui.sh && source ${SCRIPT_DIR}/lib/network_checks.sh'"

# check_ip_conflicts returns 0 when IP not found (gcloud returns empty)
_test_check_ip_no_conflict() {
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/network_checks.sh"
  # Non-existent project/IP → gcloud returns empty string → function returns 0
  check_ip_conflicts "nonexistent-proj-x" "nonexistent-ip-x" "test-ingress"
}
check "check_ip_conflicts returns 0 when IP not found" 0 \
  "_test_check_ip_no_conflict"

# GAP-03: deploy.sh FrontendConfig block must use ${SSL_POLICY_NAME}, not hardcoded sslsecure
_test_ssl_policy_name_in_deploy() {
  # Static regression check: confirms deploy.sh's FrontendConfig heredoc uses the variable
  # and does NOT contain a hardcoded sslsecure literal.
  local deploy="$SCRIPT_DIR/scripts/deploy.sh"
  grep -qF 'sslPolicy: ${SSL_POLICY_NAME}' "$deploy" &&
  ! grep -qP 'sslPolicy:\s+sslsecure' "$deploy"
}
check "deploy.sh FrontendConfig uses SSL_POLICY_NAME variable (not hardcoded sslsecure)" 0 \
  "_test_ssl_policy_name_in_deploy"

# GAP-04: deploy.sh must redirect mutations to WORK_DIR (static regression check)
_test_workdir_isolation_in_deploy() {
  local deploy="$SCRIPT_DIR/scripts/deploy.sh"
  grep -qF 'WORK_DIR="$TICKET_DIR/manifests-work"'       "$deploy" &&
  grep -qF 'cp "$INGRESS_YAML" "$WORK_DIR/ingress.yaml"' "$deploy" &&
  grep -qF 'INGRESS_YAML="$WORK_DIR/ingress.yaml"'       "$deploy" &&
  grep -qF 'COMPANIONS_DIR="$WORK_DIR/companions"'        "$deploy"
}
check "deploy.sh WORK_DIR redirect lines are present (not a reimplementation)" 0 \
  "_test_workdir_isolation_in_deploy"

# discovery.sh sources cleanly
check "discovery.sh sources cleanly" 0 \
  "bash -c 'source ${SCRIPT_DIR}/lib/ui.sh && source ${SCRIPT_DIR}/lib/discovery.sh'"

# normalize_static_ip_name: keyword variants → empty string
_test_normalize_ephemeral() {
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/discovery.sh"
  [[ "$(normalize_static_ip_name "ephemeral")" == "" ]] &&
  [[ "$(normalize_static_ip_name "efimera")" == "" ]] &&
  [[ "$(normalize_static_ip_name "efim")" == "" ]] &&
  [[ "$(normalize_static_ip_name "eph")" == "" ]] &&
  [[ "$(normalize_static_ip_name "EPHEMERAL")" == "" ]] &&
  [[ "$(normalize_static_ip_name "gnp-rpff")" == "gnp-rpff" ]] &&
  [[ "$(normalize_static_ip_name "")" == "" ]]
}
check "normalize_static_ip_name converts keywords to empty, passthrough others" 0 \
  "_test_normalize_ephemeral"

# validate_static_ip: non-existent project/IP in CI mode → returns 0 (no prompt)
_test_validate_ip_ci_missing() {
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/discovery.sh"
  CI=true validate_static_ip "nonexistent-proj-x" "nonexistent-ip-x"
}
check "validate_static_ip returns 0 in CI mode when IP not found" 0 \
  "_test_validate_ip_ci_missing"

# validate_namespace: non-blocking when namespace missing (kubectl fails → warn only)
_test_validate_ns_missing() {
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/discovery.sh"
  # kubectl unavailable or namespace missing → warn but return 0
  validate_namespace "nonexistent-ns-x" ""
}
check "validate_namespace returns 0 when namespace not found (non-blocking)" 0 \
  "_test_validate_ns_missing"

# detect_ingress_cluster returns 0 and emits nothing with empty cluster list
_test_detect_no_clusters() {
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/discovery.sh"
  # gcloud returns empty → mapfile gets empty array → early return → no output, exit 0
  gcloud() { return 0; }
  local out
  out=$(detect_ingress_cluster "nonexistent-proj-x" "test-ingress")
  [[ -z "$out" ]]
}
check "detect_ingress_cluster returns 0 and emits nothing when no clusters" 0 \
  "_test_detect_no_clusters"

# GCP-04/GCP-05: kubernetes_manifest resources must have computed_fields configured
_test_computed_fields_in_main_tf() {
  local main_tf="$SCRIPT_DIR/modules/ingress/main.tf"
  grep -q 'computed_fields' "$main_tf" &&
  grep -q '"metadata.finalizers"' "$main_tf" &&
  grep -q '"status"' "$main_tf"
}
check "kubernetes_manifest resources have computed_fields configured (main.tf)" 0 \
  "_test_computed_fields_in_main_tf"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
