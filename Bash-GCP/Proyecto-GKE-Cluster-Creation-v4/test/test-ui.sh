#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
. "$ROOT_DIR/lib/ui.sh"

# Initialize globals that will be tested
STEP_CURRENT=0
STEP_TOTAL=0

PASS=0
FAIL=0

run_test() {
    local name="$1"; shift
    printf "  %-60s" "$name"
    if "$@"; then
        printf "PASS\n"; PASS=$((PASS+1))
    else
        printf "FAIL\n"; FAIL=$((FAIL+1))
    fi
}

# T1: step_init sets STEP_TOTAL and resets STEP_CURRENT
test_step_init() {
    STEP_CURRENT=5
    step_init 10
    [ "$STEP_TOTAL" -eq 10 ] && [ "$STEP_CURRENT" -eq 0 ]
}

# T2: step() increments STEP_CURRENT
test_step_increments() {
    step_init 10
    step "Test" >/dev/null 2>&1
    [ "$STEP_CURRENT" -eq 1 ]
}

# T3: step() shows STEP N/TOTAL when STEP_TOTAL > 0
test_step_shows_counter() {
    step_init 3
    local out
    out=$(step "My Step" 2>/dev/null)
    echo "$out" | grep -q "STEP 1/3"
}

# T4: step() shows STEP N only (no slash) when STEP_TOTAL = 0
test_step_no_total() {
    step_init 0
    local out
    out=$(step "My Step" 2>/dev/null)
    echo "$out" | grep -q "STEP 1" || return 1
    echo "$out" | grep -q "STEP 1/" && return 1
    return 0
}

# T5: info() outputs middle-dot · (U+00B7) — NOT bullet • (U+2022)
test_info_format() {
    local out
    out=$(info "hello" 2>/dev/null)
    echo "$out" | grep -q "·"
}

# T6: success() outputs checkmark ✔
test_success_format() {
    local out
    out=$(success "done" 2>/dev/null)
    echo "$out" | grep -q "✔"
}

# T7: warn() outputs warning symbol ⚠
test_warn_format() {
    local out
    out=$(warn "careful" 2>/dev/null)
    echo "$out" | grep -q "⚠"
}

# T8: error() outputs to stderr, not stdout
test_error_stderr() {
    local stdout stderr
    stdout=$(error "bad" 2>/dev/null)
    stderr=$(error "bad" 2>&1 >/dev/null)
    [ -z "$stdout" ] && echo "$stderr" | grep -q "✖"
}

echo ""
echo "=== UI Unit Tests ==="
echo ""

run_test "T1: step_init sets STEP_TOTAL and resets STEP_CURRENT" test_step_init
run_test "T2: step() increments STEP_CURRENT"                    test_step_increments
run_test "T3: step() shows STEP N/TOTAL when total set"          test_step_shows_counter
run_test "T4: step() shows STEP N only when total not set"       test_step_no_total
run_test "T5: info() outputs middle dot ·"                       test_info_format
run_test "T6: success() outputs checkmark ✔"                     test_success_format
run_test "T7: warn() outputs warning symbol ⚠"                  test_warn_format
run_test "T8: error() outputs to stderr"                         test_error_stderr

echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

[ "$FAIL" -eq 0 ] || exit 1
