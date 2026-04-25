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

# run_test_full <new_content> <existing_content> <gcloud_script_body>
run_test_full() {
    local new_content="$1"
    local existing_content="$2"
    local gcloud_body="$3"
    local prefix="$TMP/t_$$_$RANDOM"
    local stub_bin="$TMP/bin_$RANDOM"

    mkdir -p "$stub_bin"

    if [ -n "$new_content" ]; then
        printf '%s\n' "$new_content" > "${prefix}_new_services_armor.txt"
    else
        touch "${prefix}_new_services_armor.txt"
    fi

    if [ -n "$existing_content" ]; then
        printf '%s\n' "$existing_content" > "${prefix}_existing_services_armor.txt"
    else
        touch "${prefix}_existing_services_armor.txt"
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

# run_test <new_content> <gcloud_script_body>  (no existing services file)
run_test() {
    run_test_full "$1" "" "$2"
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
assert_contains "no armor file → skip" "no services to check" "$out"

echo "--- 2: empty armor file → skip ---"
out=$(run_test "" 'exit 1')
assert_contains "empty armor file → skip" "no services to check" "$out"

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

echo "--- 8: existing service → policy attached → all OK ---"
out=$(run_test_full "" "svc-x" '
case "$*" in
  *"security-policies describe"*) exit 0 ;;
  *"backend-services list"*)      printf "k8s-be-8080--ghi789\n" ;;
  *"backend-services describe"*)  printf "https://googleapis.com/compute/v1/projects/p/global/securityPolicies/cve-canary\n" ;;
esac
')
assert_contains "existing attached → ✔ line"      "svc-x"      "$out"
assert_contains "existing attached → all OK msg"  "all 1"      "$out"

echo "--- 9: existing service → policy NOT attached → warning ---"
out=$(run_test_full "" "svc-y" '
case "$*" in
  *"security-policies describe"*) exit 0 ;;
  *"backend-services list"*)      printf "k8s-be-9090--jkl012\n" ;;
  *"backend-services describe"*)  printf "\n" ;;
esac
')
assert_contains "existing not attached → NOT attached line"  "NOT attached"   "$out"
assert_contains "existing not attached → summary warning"    "without policy" "$out"

echo ""
printf "Results: %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
