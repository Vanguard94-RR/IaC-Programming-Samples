#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRY="$ROOT_DIR/bin/create_gke_cluster.sh"

# Suppress all real GCP/kubectl calls
export NO_CLUSTER=1
export DRY_RUN=true

PASS=0
FAIL=0

run_test() {
    local name="$1"
    shift
    printf "  %-50s" "$name"
    if "$@" >/dev/null 2>&1; then
        printf "PASS\n"
        PASS=$((PASS+1))
    else
        printf "FAIL\n"
        FAIL=$((FAIL+1))
    fi
}

run_test_fail() {
    local name="$1"
    shift
    printf "  %-50s" "$name"
    if ! "$@" >/dev/null 2>&1; then
        printf "PASS\n"
        PASS=$((PASS+1))
    else
        printf "FAIL (expected non-zero exit)\n"
        FAIL=$((FAIL+1))
    fi
}

echo ""
echo "=== GKE Cluster Creation Smoke Test ==="
echo ""

if [ ! -x "$ENTRY" ]; then
    echo "FATAL: Entrypoint not found or not executable: $ENTRY"
    exit 2
fi

run_test "T1: --help exits 0" "$ENTRY" --help
run_test_fail "T2: unknown subcommand exits non-zero" "$ENTRY" bad-subcommand
run_test "T3: create --dry-run with all flags" \
    "$ENTRY" create --dry-run \
    --project test-proj --cluster test-gke \
    --region us-central1 --env qa
run_test "T4: update-armor --dry-run" \
    "$ENTRY" update-armor --dry-run --project test-proj
run_test "T5: rollback-armor --dry-run" \
    "$ENTRY" rollback-armor --dry-run --project test-proj
run_test "T6: fix-shared-vpc --dry-run" \
    "$ENTRY" fix-shared-vpc --dry-run
run_test "T7: log4j --dry-run" \
    "$ENTRY" log4j --dry-run --project test-proj

echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

[ "$FAIL" -eq 0 ] || exit 1
