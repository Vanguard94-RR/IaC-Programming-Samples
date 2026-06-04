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
check "deploy.sh exits 1 with invalid action in CI mode" 1 \
  "CI=true PROJECT_ID=x NAMESPACE=x STATIC_IP_NAME=x INGRESS_URL=x TICKET_ID=x ACTION=noop \
   bash ${SCRIPT_DIR}/scripts/deploy.sh"

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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
