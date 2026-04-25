#!/usr/bin/env bash
# Unit tests for lib/cloud_armor.sh

set -o nounset
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

assert_contains() {
    local label="$1" pattern="$2" output="$3"
    if printf '%s' "$output" | grep -q "$pattern"; then
        printf "PASS: %s\n" "$label"
        PASS=$((PASS + 1))
    else
        printf "FAIL: %s\n  expected pattern: '%s'\n  got: %s\n" "$label" "$pattern" "$output"
        FAIL=$((FAIL + 1))
    fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run_test <armor_file_content> <gcloud_script_body>
# Runs sync_cloud_armor in an isolated subshell with a stub gcloud.
run_test() {
    local armor_content="$1"
    local gcloud_body="$2"
    local prefix="$TMP/t_$$_$RANDOM"
    local stub_bin="$TMP/bin_$RANDOM"

    mkdir -p "$stub_bin"
    if [ -n "$armor_content" ]; then
        printf '%s\n' "$armor_content" > "${prefix}_new_services_armor.txt"
    else
        touch "${prefix}_new_services_armor.txt"
    fi
    printf '#!/usr/bin/env bash\n%s\n' "$gcloud_body" > "$stub_bin/gcloud"
    chmod +x "$stub_bin/gcloud"

    (
        export TMP_PREFIX="$prefix"
        export NAMESPACE="test-ns"
        export CLOUD_ARMOR_POLICY="cve-canary"
        export PATH="$stub_bin:$PATH"
        sleep() { :; }
        export -f sleep
        # shellcheck source=/dev/null
        . "$ROOT/lib/cloud_armor.sh"
        sync_cloud_armor
    ) 2>&1
}

echo "=== cloud_armor.sh unit tests ==="
echo ""

echo "--- 1: no armor file → skip ---"
out=$(
    (
        export TMP_PREFIX="$TMP/missing"
        export NAMESPACE="test-ns"
        export CLOUD_ARMOR_POLICY="cve-canary"
        sleep() { :; }
        export -f sleep
        # shellcheck source=/dev/null
        . "$ROOT/lib/cloud_armor.sh"
        sync_cloud_armor
    ) 2>&1
)
assert_contains "no armor file → skip" "No new services" "$out"

echo "--- 2: empty armor file → skip ---"
out=$(run_test "" 'exit 1')
assert_contains "empty armor file → skip" "No new services" "$out"

echo "--- 3: gcloud unavailable → warn ---"
out=$(
    (
        export TMP_PREFIX="$TMP/t3_$$"
        printf 'svc-a\n' > "${TMP_PREFIX}_new_services_armor.txt"
        export NAMESPACE="test-ns"
        export CLOUD_ARMOR_POLICY="cve-canary"
        sleep() { :; }
        export -f sleep
        # Source with normal PATH so dirname/pwd work at source time
        # shellcheck source=/dev/null
        . "$ROOT/lib/cloud_armor.sh"
        # Clear PATH after sourcing so command -v gcloud fails
        export PATH=""
        sync_cloud_armor
    ) 2>&1
)
assert_contains "gcloud unavailable → warn" "gcloud not available" "$out"

echo "--- 4: policy not found → error ---"
out=$(run_test "svc-a" '
case "$*" in
  *"security-policies describe"*) exit 1 ;;
esac
exit 0
')
assert_contains "policy not found → error" "not found" "$out"

echo "--- 5: new service → attached ---"
out=$(run_test "svc-b" '
case "$*" in
  *"security-policies describe"*) exit 0 ;;
  *"backend-services list"*)      printf "k8s-be-8080--abc123\n" ;;
  *"backend-services describe"*)  printf "\n" ;;
  *"backend-services update"*)    exit 0 ;;
esac
')
assert_contains "new service → 1 attached in summary"  "1 attached"           "$out"
assert_contains "new service → output has backend"     "k8s-be-8080--abc123"  "$out"
assert_contains "new service → output has svc name"    "svc-b"                "$out"

echo "--- 6: already attached → skip ---"
out=$(run_test "svc-c" '
case "$*" in
  *"security-policies describe"*) exit 0 ;;
  *"backend-services list"*)      printf "k8s-be-9090--def456\n" ;;
  *"backend-services describe"*)  printf "https://googleapis.com/compute/v1/projects/p/global/securityPolicies/cve-canary\n" ;;
esac
')
assert_contains "already attached → skip" "already attached" "$out"

echo "--- 7: backend not found after retries → warn ---"
out=$(run_test "svc-d" '
case "$*" in
  *"security-policies describe"*) exit 0 ;;
  *"backend-services list"*)      printf "" ;;
esac
')
assert_contains "not found → warn message"  "not found after 3 retries" "$out"
assert_contains "not found → skipped label" "skipped"                    "$out"

echo ""
printf "Results: %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
