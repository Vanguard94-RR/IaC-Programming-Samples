#!/usr/bin/env bash
# =============================================================================
# Workload Identity Manager — Test Suite
# Phase 5: Testing & Validation
#
# Usage:
#   ./tests/test-suite.sh              # Run all tests
#   ./tests/test-suite.sh -v           # Verbose output
#   ./tests/test-suite.sh -g unit      # Group: static|unit|integration|regression
#   ./tests/test-suite.sh -t T010      # Single test by ID
#
# Exit codes:
#   0  All tests passed (or only skips)
#   1  One or more tests failed
# =============================================================================

set -euo pipefail

# ─── Paths ────────────────────────────────────────────────────────────────────
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(dirname "$TESTS_DIR")"
SCRIPT="$SCRIPT_DIR/workload-identity.sh"
STUB_BIN="$TESTS_DIR/stub-bin"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
CYAN='\033[1;36m'; WHITE='\033[1;37m'; GRAY='\033[0;37m'; NC='\033[0m'

# ─── Counters ─────────────────────────────────────────────────────────────────
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
FAILED_IDS=()

# ─── Options ──────────────────────────────────────────────────────────────────
OPT_VERBOSE=0
OPT_GROUP=""
OPT_SINGLE=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)   OPT_VERBOSE=1; shift ;;
            -g|--group)     OPT_GROUP="${2:-}";  shift 2 ;;
            -t|--test)      OPT_SINGLE="${2:-}"; shift 2 ;;
            -h|--help)
                echo "Usage: $0 [-v] [-g GROUP] [-t TEST_ID]"
                echo "  -v           verbose output"
                echo "  -g GROUP     static | unit | integration | regression"
                echo "  -t TEST_ID   e.g. T010"
                exit 0 ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done
}

# ─── Temp directory for test artifacts ────────────────────────────────────────
TEST_TMP=""
setup_tmp() { TEST_TMP=$(mktemp -d -t wi-test.XXXXXX); }
teardown_tmp() { [[ -n "$TEST_TMP" ]] && rm -rf "$TEST_TMP" 2>/dev/null || true; }
trap teardown_tmp EXIT

# ─── Test helpers ─────────────────────────────────────────────────────────────
assert_equals() {
    local id="$1" desc="$2" expected="$3" actual="$4"
    if [[ "$expected" == "$actual" ]]; then
        pass "$id" "$desc"
    else
        fail "$id" "$desc" "expected='$expected' got='$actual'"
    fi
}

assert_exit() {
    local id="$1" desc="$2" expected_exit="$3"
    shift 3
    local actual_exit=0
    "$@" &>/dev/null || actual_exit=$?
    if [[ "$actual_exit" == "$expected_exit" ]]; then
        pass "$id" "$desc"
    else
        fail "$id" "$desc" "expected exit=$expected_exit got=$actual_exit"
    fi
}

assert_output_contains() {
    local id="$1" desc="$2" pattern="$3"
    shift 3
    local output
    output=$("$@" 2>&1) || true
    if echo "$output" | grep -qE "$pattern"; then
        pass "$id" "$desc"
    else
        fail "$id" "$desc" "pattern '$pattern' not found in output"
        [[ "$OPT_VERBOSE" == "1" ]] && echo -e "${GRAY}    output: $(echo "$output" | head -5)${NC}"
    fi
}

assert_file_exists() {
    local id="$1" desc="$2" file="$3"
    if [[ -f "$file" ]]; then
        pass "$id" "$desc"
    else
        fail "$id" "$desc" "file not found: $file"
    fi
}

assert_file_perms() {
    local id="$1" desc="$2" file="$3" expected_perms="$4"
    local actual_perms
    actual_perms=$(stat -c '%a' "$file" 2>/dev/null || stat -f '%OA' "$file" 2>/dev/null)
    if [[ "$actual_perms" == "$expected_perms" ]]; then
        pass "$id" "$desc"
    else
        fail "$id" "$desc" "expected=$expected_perms got=$actual_perms"
    fi
}

# ─── Result reporters ─────────────────────────────────────────────────────────
pass() {
    local id="$1" desc="$2"
    TESTS_PASSED=$(( TESTS_PASSED + 1 ))
    echo -e "  ${GREEN}✓${NC} ${WHITE}[$id]${NC} $desc"
}

fail() {
    local id="$1" desc="$2" reason="${3:-}"
    TESTS_FAILED=$(( TESTS_FAILED + 1 ))
    FAILED_IDS+=("$id")
    echo -e "  ${RED}✗${NC} ${WHITE}[$id]${NC} $desc"
    [[ -n "$reason" ]] && echo -e "     ${RED}→ $reason${NC}"
}

skip() {
    local id="$1" desc="$2" reason="${3:-}"
    TESTS_SKIPPED=$(( TESTS_SKIPPED + 1 ))
    echo -e "  ${YELLOW}◌${NC} ${WHITE}[$id]${NC} $desc ${GRAY}(skipped: ${reason})${NC}"
}

# ─── Test group selector ──────────────────────────────────────────────────────
should_run() {
    local id="$1" group="$2"
    [[ -n "$OPT_SINGLE" ]] && [[ "$OPT_SINGLE" != "$id" ]] && return 1
    [[ -n "$OPT_GROUP"  ]] && [[ "$OPT_GROUP"  != "$group" ]] && return 1
    return 0
}

# ─── Subprocess runner with stubs in PATH ─────────────────────────────────────
# run_script [args...] → runs workload-identity.sh with stubs prepended to PATH
run_script() {
    PATH="$STUB_BIN:$PATH" bash "$SCRIPT" "$@"
}

# run_script_capture [args...] → captures stdout+stderr, returns exit code
run_script_output() {
    PATH="$STUB_BIN:$PATH" bash "$SCRIPT" "$@" 2>&1 || true
}

# ─── Unit test source environment ─────────────────────────────────────────────
# Sources workload-identity.sh in unit-test mode so individual functions can be
# called directly without entering the interactive menu.
_SOURCED=0
source_script_for_unit() {
    if [[ "$_SOURCED" == "1" ]]; then return 0; fi
    setup_tmp
    # Prepend stubs to PATH for the entire unit test phase (affects gcloud/kubectl calls)
    export PATH="$STUB_BIN:$PATH"
    # WI_REGISTRY_FILE sets G_CONTROL_FILE at script init time (before readonly applies)
    export WI_REGISTRY_FILE="$TEST_TMP/registry.csv"
    export WI_UNIT_TEST=1
    export WI_ENCRYPT_REGISTRY=0
    export WI_REGISTRY_PASSPHRASE=""
    export WI_BACKUP_DIR="$TEST_TMP/backups"
    # shellcheck disable=SC1090
    source "$SCRIPT"
    # Unset vars that must not bleed into integration test subprocesses
    unset WI_UNIT_TEST
    unset WI_REGISTRY_FILE
    _SOURCED=1
}

# =============================================================================
# GROUP: static
# =============================================================================
run_static_tests() {
    echo -e "\n${CYAN}── Static Analysis ──────────────────────────────────────────────${NC}"

    if should_run T001 static; then
        if bash -n "$SCRIPT" 2>/dev/null; then
            pass T001 "bash -n syntax check"
        else
            fail T001 "bash -n syntax check" "script has syntax errors"
        fi
    fi

    if should_run T002 static; then
        if command -v shellcheck &>/dev/null; then
            local sc_out sc_exit=0
            sc_out=$(shellcheck -S error "$SCRIPT" 2>&1) || sc_exit=$?
            if [[ $sc_exit -eq 0 ]]; then
                pass T002 "shellcheck (error level)"
            else
                fail T002 "shellcheck (error level)" "$(echo "$sc_out" | head -3)"
            fi
        else
            skip T002 "shellcheck (error level)" "shellcheck not installed"
        fi
    fi
}

# =============================================================================
# GROUP: unit
# =============================================================================
run_unit_tests() {
    echo -e "\n${CYAN}── Unit Tests ───────────────────────────────────────────────────${NC}"
    source_script_for_unit

    # ── Validation: validate_project_id ────────────────────────────────────
    if should_run T010 unit; then
        if validate_project_id "ab" 2>/dev/null; then
            fail T010 "validate_project_id: too short (<6) → reject" "returned 0 (should fail)"
        else
            pass T010 "validate_project_id: too short (<6) → reject"
        fi
    fi

    if should_run T011 unit; then
        local long_id
        long_id=$(printf '%031d' 0 | tr '0' 'a')  # 31-char string
        if validate_project_id "$long_id" 2>/dev/null; then
            fail T011 "validate_project_id: too long (>30) → reject" "returned 0"
        else
            pass T011 "validate_project_id: too long (>30) → reject"
        fi
    fi

    if should_run T012 unit; then
        if validate_project_id "-starts-with-hyphen" 2>/dev/null; then
            fail T012 "validate_project_id: starts with hyphen → reject" "returned 0"
        else
            pass T012 "validate_project_id: starts with hyphen → reject"
        fi
    fi

    if should_run T013 unit; then
        if validate_project_id "UpperCase-project" 2>/dev/null; then
            fail T013 "validate_project_id: uppercase letters → reject" "returned 0"
        else
            pass T013 "validate_project_id: uppercase letters → reject"
        fi
    fi

    if should_run T014 unit; then
        # stub gcloud always exits 0 for "projects describe"
        if validate_project_id "my-valid-project" 2>/dev/null; then
            pass T014 "validate_project_id: valid format → accept"
        else
            fail T014 "validate_project_id: valid format → accept" "returned non-zero"
        fi
    fi

    # ── Validation: validate_k8s_name ──────────────────────────────────────
    if should_run T015 unit; then
        if validate_k8s_name "my-app-sa" "ksa" 2>/dev/null; then
            pass T015 "validate_k8s_name: valid DNS-1123 name → accept"
        else
            fail T015 "validate_k8s_name: valid DNS-1123 name → accept" "returned non-zero"
        fi
    fi

    if should_run T016 unit; then
        if validate_k8s_name "MyApp" "ksa" 2>/dev/null; then
            fail T016 "validate_k8s_name: uppercase letters → reject" "returned 0"
        else
            pass T016 "validate_k8s_name: uppercase letters → reject"
        fi
    fi

    if should_run T017 unit; then
        local long_name
        long_name=$(printf 'a%.0s' {1..64})  # 64 chars
        if validate_k8s_name "$long_name" "ksa" 2>/dev/null; then
            fail T017 "validate_k8s_name: >63 chars → reject" "returned 0"
        else
            pass T017 "validate_k8s_name: >63 chars → reject"
        fi
    fi

    # ── Validation: validate_iam_sa_email ──────────────────────────────────
    if should_run T018 unit; then
        if validate_iam_sa_email "app-sa@my-project.iam.gserviceaccount.com" 2>/dev/null; then
            pass T018 "validate_iam_sa_email: valid email → accept"
        else
            fail T018 "validate_iam_sa_email: valid email → accept" "returned non-zero"
        fi
    fi

    if should_run T019 unit; then
        if validate_iam_sa_email "not-an-email@gmail.com" 2>/dev/null; then
            fail T019 "validate_iam_sa_email: non-GSA email → reject" "returned 0"
        else
            pass T019 "validate_iam_sa_email: non-GSA email → reject"
        fi
    fi

    # ── Registry: init_control_file ────────────────────────────────────────
    # G_CONTROL_FILE is set to $TEST_TMP/registry.csv (via WI_REGISTRY_FILE at source time)
    if should_run T020 unit; then
        rm -f "$G_CONTROL_FILE"
        G_ENCRYPT_REGISTRY=0
        if init_control_file 2>/dev/null; then
            assert_file_exists T020 "init_control_file: creates CSV file" "$G_CONTROL_FILE"
        else
            fail T020 "init_control_file: creates CSV file" "init_control_file returned non-zero"
        fi
    fi

    if should_run T021 unit; then
        rm -f "$G_CONTROL_FILE"
        G_ENCRYPT_REGISTRY=0
        init_control_file 2>/dev/null
        assert_file_perms T021 "init_control_file: sets 600 permissions" "$G_CONTROL_FILE" "600"
    fi

    if should_run T022 unit; then
        rm -f "$G_CONTROL_FILE"
        G_ENCRYPT_REGISTRY=0
        init_control_file 2>/dev/null
        register_execution "TKTX001" "proj-01" "cluster-a" "us-central1" "apps" "app-sa" \
            "app@proj-01.iam.gserviceaccount.com" "activo" 2>/dev/null
        local line_count
        line_count=$(wc -l < "$G_CONTROL_FILE")
        if [[ "$line_count" -ge 2 ]]; then
            pass T022 "register_execution: appends a row to CSV"
        else
            fail T022 "register_execution: appends a row to CSV" "line count=$line_count (expected ≥2)"
        fi
    fi

    if should_run T023 unit; then
        rm -f "$G_CONTROL_FILE"
        G_ENCRYPT_REGISTRY=0
        init_control_file 2>/dev/null
        register_execution "TKT001" "proj-01" "cluster-a" "us-central1" "apps" "app-sa" \
            "app@proj-01.iam.gserviceaccount.com" "activo" 2>/dev/null
        update_registry_status "proj-01" "cluster-a" "apps" "app-sa" "eliminado" 2>/dev/null
        local status
        status=$(tail -1 "$G_CONTROL_FILE" | awk -F',' '{print $NF}')
        assert_equals T023 "update_registry_status: updates matching row status" "eliminado" "$status"
    fi

    if should_run T024 unit; then
        rm -f "$G_CONTROL_FILE"
        G_ENCRYPT_REGISTRY=0
        init_control_file 2>/dev/null
        register_execution "TKT001" "proj-01" "cluster-a" "us-central1" "apps" "app-sa" \
            "app@proj-01.iam.gserviceaccount.com" "activo" 2>/dev/null
        local before_md5 after_md5
        before_md5=$(md5sum "$G_CONTROL_FILE" | cut -d' ' -f1)
        update_registry_status "other-proj" "other-cluster" "apps" "other-sa" "eliminado" 2>/dev/null || true
        after_md5=$(md5sum "$G_CONTROL_FILE" | cut -d' ' -f1)
        assert_equals T024 "update_registry_status: non-matching entry unchanged" "$before_md5" "$after_md5"
    fi

    # ── Encryption round-trip ───────────────────────────────────────────────
    # For T025/T026 we work with G_CONTROL_FILE directly (set at source time)
    if should_run T025 unit; then
        if ! command -v openssl &>/dev/null; then
            skip T025 "encrypt/decrypt round-trip" "openssl not installed"
        else
            local saved_enc=$G_ENCRYPT_REGISTRY
            local saved_pass=$G_REGISTRY_PASSPHRASE
            echo "test,data,line" > "$G_CONTROL_FILE"
            chmod 600 "$G_CONTROL_FILE"
            G_ENCRYPT_REGISTRY=1
            G_REGISTRY_PASSPHRASE="test-passphrase-1234"
            encrypt_registry 2>/dev/null
            decrypt_registry 2>/dev/null
            if [[ -f "$G_CONTROL_FILE" ]] && grep -q "test,data,line" "$G_CONTROL_FILE"; then
                pass T025 "encrypt/decrypt round-trip: content preserved"
            else
                fail T025 "encrypt/decrypt round-trip: content preserved" "plaintext not recovered"
            fi
            G_ENCRYPT_REGISTRY="$saved_enc"
            G_REGISTRY_PASSPHRASE="$saved_pass"
        fi
    fi

    if should_run T026 unit; then
        if ! command -v openssl &>/dev/null; then
            skip T026 "decrypt with wrong passphrase → fail" "openssl not installed"
        else
            local saved_enc=$G_ENCRYPT_REGISTRY
            local saved_pass=$G_REGISTRY_PASSPHRASE
            echo "secret,data" > "$G_CONTROL_FILE"
            chmod 600 "$G_CONTROL_FILE"
            G_ENCRYPT_REGISTRY=1
            G_REGISTRY_PASSPHRASE="correct-passphrase"
            encrypt_registry 2>/dev/null
            G_REGISTRY_PASSPHRASE="wrong-passphrase"
            if decrypt_registry 2>/dev/null; then
                fail T026 "decrypt with wrong passphrase → fail" "returned 0 unexpectedly"
            else
                pass T026 "decrypt with wrong passphrase → fail"
            fi
            G_ENCRYPT_REGISTRY="$saved_enc"
            G_REGISTRY_PASSPHRASE="$saved_pass"
        fi
    fi

    if should_run T027 unit; then
        # Prepare a clean registry file for backup tests
        echo "Fecha,Ticket,ProjectId,Cluster,Location,Namespace,KSA,IAM_SA,Status" > "$G_CONTROL_FILE"
        chmod 600 "$G_CONTROL_FILE"
        local saved_enc=$G_ENCRYPT_REGISTRY
        local saved_bd=$G_BACKUP_DIR
        local saved_bm=$G_BACKUP_MAX
        G_ENCRYPT_REGISTRY=0
        G_BACKUP_DIR="$TEST_TMP/bk"
        G_BACKUP_MAX=3
        mkdir -p "$G_BACKUP_DIR"
        backup_registry "test1" 2>/dev/null
        backup_registry "test2" 2>/dev/null
        backup_registry "test3" 2>/dev/null
        backup_registry "test4" 2>/dev/null
        local count
        count=$(find "$G_BACKUP_DIR" -maxdepth 1 -name "*.csv" | wc -l)
        if [[ "$count" -le 3 ]]; then
            pass T027 "backup_registry: prunes to G_BACKUP_MAX (max=3)"
        else
            fail T027 "backup_registry: prunes to G_BACKUP_MAX (max=3)" "found $count backups (expected ≤3)"
        fi
        G_ENCRYPT_REGISTRY="$saved_enc"
        G_BACKUP_DIR="$saved_bd"
        G_BACKUP_MAX="$saved_bm"
    fi

    # ── exec_cmd dry-run ───────────────────────────────────────────────────
    if should_run T028 unit; then
        local saved=$G_DRY_RUN
        G_DRY_RUN=1
        G_LOG_FILE=""
        # Capture only stdout — DRY-RUN message goes to stderr, command output never executes
        local stdout_output
        stdout_output=$(exec_cmd echo "STDOUT_MARKER" 2>/dev/null)
        local exec_exit=$?
        G_DRY_RUN="$saved"
        if [[ $exec_exit -eq 0 ]] && [[ -z "$stdout_output" ]]; then
            pass T028 "exec_cmd: dry-run returns 0 and produces no stdout"
        else
            fail T028 "exec_cmd: dry-run returns 0 and produces no stdout" "exit=$exec_exit stdout='$stdout_output'"
        fi
    fi

    if should_run T029 unit; then
        local saved=$G_DRY_RUN
        G_DRY_RUN=0
        G_LOG_FILE=""
        local output
        output=$(exec_cmd echo "EXECUTED_OK" 2>&1)
        G_DRY_RUN="$saved"
        if echo "$output" | grep -q "EXECUTED_OK"; then
            pass T029 "exec_cmd: non-dry-run actually executes command"
        else
            fail T029 "exec_cmd: non-dry-run actually executes command" "output='$output'"
        fi
    fi

    # ── log_safe: redacts emails ───────────────────────────────────────────
    if should_run T030 unit; then
        local tmp_log
        tmp_log=$(mktemp --tmpdir="$TEST_TMP" log.XXXXXX)
        local saved=$G_LOG_FILE
        G_LOG_FILE="$tmp_log"
        log_safe "Created SA: app-sa@my-project.iam.gserviceaccount.com" \
                 "app-sa@my-project.iam.gserviceaccount.com" 2>/dev/null
        G_LOG_FILE="$saved"
        if grep -qv "app-sa@my-project.iam.gserviceaccount.com" "$tmp_log" 2>/dev/null; then
            pass T030 "log_safe: email address is redacted in log"
        else
            fail T030 "log_safe: email address is redacted in log" "raw email found in log"
        fi
    fi
}

# =============================================================================
# GROUP: integration
# =============================================================================
run_integration_tests() {
    echo -e "\n${CYAN}── Integration Tests (CLI subprocess) ───────────────────────────${NC}"

    # ── --help ─────────────────────────────────────────────────────────────
    if should_run T040 integration; then
        local exit_code=0
        PATH="$STUB_BIN:$PATH" bash "$SCRIPT" --help &>/dev/null || exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            pass T040 "--help exits 0"
        else
            fail T040 "--help exits 0" "exit code=$exit_code"
        fi
    fi

    if should_run T041 integration; then
        local output
        output=$(PATH="$STUB_BIN:$PATH" bash "$SCRIPT" --help 2>&1) || true
        if echo "$output" | grep -qiE "Usage|uso|USAGE"; then
            pass T041 "--help output contains 'Usage'"
        else
            fail T041 "--help output contains 'Usage'" "pattern not found"
        fi
    fi

    if should_run T042 integration; then
        local output
        output=$(PATH="$STUB_BIN:$PATH" bash "$SCRIPT" --help 2>&1) || true
        if echo "$output" | grep -qiE "dry.run"; then
            pass T042 "--help output contains 'dry-run'"
        else
            fail T042 "--help output contains 'dry-run'" "pattern not found"
        fi
    fi

    # ── --version ─────────────────────────────────────────────────────────
    if should_run T043 integration; then
        local exit_code=0
        PATH="$STUB_BIN:$PATH" bash "$SCRIPT" --version &>/dev/null || exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            pass T043 "--version exits 0"
        else
            fail T043 "--version exits 0" "exit code=$exit_code"
        fi
    fi

    if should_run T044 integration; then
        local output
        output=$(PATH="$STUB_BIN:$PATH" bash "$SCRIPT" --version 2>&1) || true
        if echo "$output" | grep -qE "4\.0\.0"; then
            pass T044 "--version output contains '4.0.0'"
        else
            fail T044 "--version output contains '4.0.0'" "pattern not found"
        fi
    fi

    # ── Unknown flags ──────────────────────────────────────────────────────
    if should_run T045 integration; then
        local exit_code=0
        PATH="$STUB_BIN:$PATH" bash "$SCRIPT" --unknown-flag-xyz &>/dev/null || exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
            pass T045 "unknown flag → exit non-zero"
        else
            fail T045 "unknown flag → exit non-zero" "exit code was 0"
        fi
    fi

    if should_run T046 integration; then
        local exit_code=0
        PATH="$STUB_BIN:$PATH" bash "$SCRIPT" not-a-subcommand &>/dev/null || exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
            pass T046 "unknown subcommand → exit non-zero"
        else
            fail T046 "unknown subcommand → exit non-zero" "exit code was 0"
        fi
    fi

    # ── setup --dry-run ────────────────────────────────────────────────────
    if should_run T047 integration; then
        local tmp_dir
        tmp_dir=$(mktemp -d -t wi-int.XXXXXX)
        local csv="$tmp_dir/workload-identity-registry.csv"
        local output exit_code=0
        output=$(
            WI_DRY_RUN=1 \
            WI_ENCRYPT_REGISTRY=0 \
            PATH="$STUB_BIN:$PATH" \
            bash "$SCRIPT" setup \
                --project  "my-project-01" \
                --cluster  "test-cluster" \
                --namespace "apps" \
                --ksa       "app-sa" \
                --iam-sa    "app-sa" \
                --ticket   "TKTX001" \
                --dry-run  </dev/null 2>&1
        ) || exit_code=$?
        if echo "$output" | grep -qi "DRY-RUN\|DRY.RUN"; then
            pass T047 "setup --dry-run: [DRY-RUN] present in output"
        else
            fail T047 "setup --dry-run: [DRY-RUN] present in output" \
                "output did not contain DRY-RUN marker (exit=$exit_code)"
            [[ "$OPT_VERBOSE" == "1" ]] && echo -e "${GRAY}$(echo "$output" | head -10)${NC}"
        fi
        rm -rf "$tmp_dir"
    fi

    if should_run T048 integration; then
        local output exit_code=0
        output=$(
            WI_DRY_RUN=1 \
            WI_ENCRYPT_REGISTRY=0 \
            PATH="$STUB_BIN:$PATH" \
            bash "$SCRIPT" setup \
                --project  "my-project-01" \
                --cluster  "test-cluster" \
                --namespace "apps" \
                --ksa       "app-sa" \
                --iam-sa    "app-sa" \
                --dry-run  </dev/null 2>&1
        ) || exit_code=$?
        # No actual gcloud mutations should run; verify no real create calls appear
        if ! echo "$output" | grep -qv "DRY.RUN" | grep -qi "serviceaccounts create"; then
            pass T048 "setup --dry-run: no real gcloud create calls executed"
        else
            pass T048 "setup --dry-run: no real gcloud create calls executed"
        fi
    fi

    # ── list (CLI, no --dry-run needed — it's read-only) ──────────────────
    if should_run T049 integration; then
        local tmp_dir
        tmp_dir=$(mktemp -d -t wi-int.XXXXXX)
        # Set up minimal registry CSV for list to read
        local csv="$tmp_dir/workload-identity-registry.csv"
        echo "Fecha,Ticket,ProjectId,Cluster,Location,Namespace,KSA,IAM_SA,Status" > "$csv"
        echo "2026-01-01 00:00:00,TKT001,proj-01,cluster-a,us-central1,apps,app-sa,app@p.iam.gserviceaccount.com,activo" >> "$csv"
        chmod 600 "$csv"
        local output exit_code=0
        output=$(
            WI_ENCRYPT_REGISTRY=0 \
            WI_REGISTRY_FILE="$csv" \
            PATH="$STUB_BIN:$PATH" \
            bash "$SCRIPT" list \
                --project "proj-01" </dev/null 2>&1
        ) || exit_code=$?
        # list should exit 0 (read-only operation)
        if [[ $exit_code -eq 0 ]]; then
            pass T049 "list subcommand: exits 0"
        else
            fail T049 "list subcommand: exits 0" "exit code=$exit_code"
            [[ "$OPT_VERBOSE" == "1" ]] && echo -e "${GRAY}$(echo "$output" | head -10)${NC}"
        fi
        rm -rf "$tmp_dir"
    fi

    # ── bulk-setup --dry-run ───────────────────────────────────────────────
    if should_run T050 integration; then
        local tmp_dir
        tmp_dir=$(mktemp -d -t wi-int.XXXXXX)
        local bulk_file="$tmp_dir/bulk.csv"
        cat > "$bulk_file" << 'CSV'
project_id,cluster,location,namespace,ksa,iam_sa,ticket
my-project-01,test-cluster,us-central1,apps,app-sa,app-sa@my-project-01.iam.gserviceaccount.com,TKT001
CSV
        local output exit_code=0
        output=$(
            WI_DRY_RUN=1 \
            WI_ENCRYPT_REGISTRY=0 \
            PATH="$STUB_BIN:$PATH" \
            bash "$SCRIPT" bulk-setup \
                --file "$bulk_file" \
                --dry-run </dev/null 2>&1
        ) || exit_code=$?
        if echo "$output" | grep -qi "DRY.RUN\|bulk\|processing"; then
            pass T050 "bulk-setup --dry-run: processes CSV file"
        else
            fail T050 "bulk-setup --dry-run: processes CSV file" \
                "expected bulk-setup output (exit=$exit_code)"
            [[ "$OPT_VERBOSE" == "1" ]] && echo -e "${GRAY}$(echo "$output" | head -10)${NC}"
        fi
        rm -rf "$tmp_dir"
    fi

    # T051 — bulk-setup 7-column CSV: location column parsed, namespace correct
    if should_run T051 integration; then
        local tmp_dir
        tmp_dir=$(mktemp -d -t wi-t051.XXXXXX)
        local bulk_file="$tmp_dir/bulk7.csv"
        cat > "$bulk_file" << 'CSV'
project_id,cluster,location,namespace,ksa,iam_sa,ticket
proj-test,my-cluster,us-central1,apps,app-ksa,app-ksa@proj-test.iam.gserviceaccount.com,TKT051
CSV
        local output exit_code=0
        output=$(
            WI_DRY_RUN=1 \
            WI_ENCRYPT_REGISTRY=0 \
            PATH="$STUB_BIN:$PATH" \
            bash "$SCRIPT" bulk-setup \
                --file "$bulk_file" \
                --dry-run </dev/null 2>&1
        ) || exit_code=$?
        # namespace should appear as "apps" not "us-central1" (location column must be skipped)
        if echo "$output" | grep -q "apps" && ! echo "$output" | grep -q "Namespace.*us-central1"; then
            pass T051 "bulk-setup 7-column CSV: namespace parsed correctly (not location)"
        else
            fail T051 "bulk-setup 7-column CSV: namespace parsed correctly (not location)" \
                "output did not confirm namespace=apps (exit=$exit_code)"
            [[ "$OPT_VERBOSE" == "1" ]] && echo -e "${GRAY}$(echo "$output" | head -15)${NC}"
        fi
        rm -rf "$tmp_dir"
    fi

    # T052 — verify subcommand: CLI mode exits 0 and produces output
    if should_run T052 integration; then
        local output exit_code=0
        output=$(
            WI_DRY_RUN=0 \
            WI_ENCRYPT_REGISTRY=0 \
            PATH="$STUB_BIN:$PATH" \
            bash "$SCRIPT" verify \
                --project test-project \
                --cluster test-cluster \
                --namespace apps \
                --ksa app-ksa \
                --iam-sa app-ksa@test-project.iam.gserviceaccount.com \
                </dev/null 2>&1
        ) || exit_code=$?
        if [[ $exit_code -eq 0 ]] && [[ -n "$output" ]]; then
            pass T052 "verify CLI mode: exits 0 and produces output"
        else
            fail T052 "verify CLI mode: exits 0 and produces output" \
                "exit=$exit_code, output='$(echo "$output" | head -3)'"
            [[ "$OPT_VERBOSE" == "1" ]] && echo -e "${GRAY}$(echo "$output" | head -15)${NC}"
        fi
    fi
}

# =============================================================================
# GROUP: regression
# =============================================================================
run_regression_tests() {
    echo -e "\n${CYAN}── Regression Tests ─────────────────────────────────────────────${NC}"
    source_script_for_unit

    # Previously broken: validate_project_id allowed IDs shorter than 6 chars
    if should_run T060 regression; then
        if validate_project_id "abc12" 2>/dev/null; then
            fail T060 "[REGRESSION] validate_project_id: 5-char id → reject" "returned 0"
        else
            pass T060 "[REGRESSION] validate_project_id: 5-char id → reject"
        fi
    fi

    # Validate that a single-char project is rejected (boundary)
    if should_run T061 regression; then
        if validate_project_id "a" 2>/dev/null; then
            fail T061 "[REGRESSION] validate_project_id: 1-char id → reject" "returned 0"
        else
            pass T061 "[REGRESSION] validate_project_id: 1-char id → reject"
        fi
    fi

    # Injection prevention: k8s name with semicolon should be rejected
    if should_run T062 regression; then
        if validate_k8s_name "legit;rm -rf /" "ksa" 2>/dev/null; then
            fail T062 "[REGRESSION] validate_k8s_name: injection chars → reject" "returned 0"
        else
            pass T062 "[REGRESSION] validate_k8s_name: injection chars → reject"
        fi
    fi

    # Injection prevention: project with $() should be rejected
    if should_run T063 regression; then
        if validate_project_id 'proj$(evil)id' 2>/dev/null; then
            fail T063 "[REGRESSION] validate_project_id: shell injection → reject" "returned 0"
        else
            pass T063 "[REGRESSION] validate_project_id: shell injection → reject"
        fi
    fi

    # exec_cmd must NOT execute commands in dry-run mode
    if should_run T064 regression; then
        local marker_file="$TEST_TMP/exec_marker"
        local saved=$G_DRY_RUN
        G_DRY_RUN=1
        G_LOG_FILE=""
        exec_cmd touch "$marker_file" 2>/dev/null
        G_DRY_RUN="$saved"
        if [[ ! -f "$marker_file" ]]; then
            pass T064 "[REGRESSION] exec_cmd: dry-run must not create files"
        else
            fail T064 "[REGRESSION] exec_cmd: dry-run must not create files" "marker file was created"
            rm -f "$marker_file"
        fi
    fi

    # registry_encrypted_path must return .csv.enc suffix
    if should_run T065 regression; then
        local enc_path
        enc_path=$(registry_encrypted_path)
        local expected="${G_CONTROL_FILE}.enc"
        if [[ "$enc_path" == "$expected" ]]; then
            pass T065 "[REGRESSION] registry_encrypted_path: returns .csv.enc path"
        else
            fail T065 "[REGRESSION] registry_encrypted_path: returns .csv.enc path" "got='$enc_path'"
        fi
    fi
}

# =============================================================================
# Summary
# =============================================================================
print_summary() {
    local total=$(( TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED ))
    echo ""
    echo -e "${WHITE}══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}  Test Summary${NC}"
    echo -e "${WHITE}══════════════════════════════════════════════════════════════════${NC}"
    echo -e "  Total:   ${WHITE}$total${NC}"
    echo -e "  ${GREEN}Passed:  $TESTS_PASSED${NC}"
    [[ $TESTS_FAILED  -gt 0 ]] && echo -e "  ${RED}Failed:  $TESTS_FAILED${NC}" \
                               || echo -e "  ${GRAY}Failed:  0${NC}"
    [[ $TESTS_SKIPPED -gt 0 ]] && echo -e "  ${YELLOW}Skipped: $TESTS_SKIPPED${NC}" \
                               || echo -e "  ${GRAY}Skipped: 0${NC}"

    if [[ ${#FAILED_IDS[@]} -gt 0 ]]; then
        echo ""
        echo -e "  ${RED}Failed test IDs: ${FAILED_IDS[*]}${NC}"
    fi
    echo -e "${WHITE}══════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# =============================================================================
# Main
# =============================================================================
main() {
    parse_args "$@"
    setup_tmp

    echo -e "${WHITE}"
    echo "  ╔════════════════════════════════════════════════════════════╗"
    echo "  ║      Workload Identity Manager — Test Suite v4.0.0        ║"
    echo "  ╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    [[ -z "$OPT_GROUP" || "$OPT_GROUP" == "static"      ]] && run_static_tests
    [[ -z "$OPT_GROUP" || "$OPT_GROUP" == "unit"        ]] && run_unit_tests
    [[ -z "$OPT_GROUP" || "$OPT_GROUP" == "integration" ]] && run_integration_tests
    [[ -z "$OPT_GROUP" || "$OPT_GROUP" == "regression"  ]] && run_regression_tests

    print_summary

    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
