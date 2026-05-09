#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
. "$ROOT_DIR/lib/ui.sh"
# shellcheck source=/dev/null
. "$ROOT_DIR/lib/utils.sh"

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

TMP_LOG=$(mktemp)
export LOG_FILE="$TMP_LOG"
export DRY_RUN=false

# T1: normal mode — terminal produces no output
test_normal_terminal_silent() {
    export VERBOSE=false
    local out
    out=$(run_or_dry echo "marker-normal" 2>&1)
    [ -z "$out" ]
}

# T2: normal mode — log file captures command output
test_normal_log_written() {
    export VERBOSE=false
    : > "$TMP_LOG"
    run_or_dry echo "marker-log"
    grep -q "marker-log" "$TMP_LOG"
}

# T3: verbose mode — terminal shows formatted output
test_verbose_terminal_output() {
    export VERBOSE=true
    local out
    out=$(run_or_dry echo "marker-verbose" 2>&1)
    echo "$out" | grep -q "marker-verbose"
}

# T4: verbose mode — log file also captures output
test_verbose_log_written() {
    export VERBOSE=true
    : > "$TMP_LOG"
    run_or_dry echo "marker-verbose-log" >/dev/null 2>&1
    grep -q "marker-verbose-log" "$TMP_LOG"
}

# T5: normal mode — non-zero exit from command propagates
test_normal_exit_code() {
    export VERBOSE=false
    ! run_or_dry false 2>/dev/null
}

# T6: verbose mode — non-zero exit from command propagates
test_verbose_exit_code() {
    export VERBOSE=true
    ! run_or_dry false 2>/dev/null
}

echo ""
echo "=== run_or_dry Unit Tests ==="
echo ""

run_test "T1: normal mode — terminal silent" test_normal_terminal_silent
run_test "T2: normal mode — log file captures output" test_normal_log_written
run_test "T3: verbose mode — terminal shows formatted output" test_verbose_terminal_output
run_test "T4: verbose mode — log file captures output" test_verbose_log_written
run_test "T5: normal mode — exit code propagates" test_normal_exit_code
run_test "T6: verbose mode — exit code propagates" test_verbose_exit_code

rm -f "$TMP_LOG"

echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

[ "$FAIL" -eq 0 ] || exit 1
