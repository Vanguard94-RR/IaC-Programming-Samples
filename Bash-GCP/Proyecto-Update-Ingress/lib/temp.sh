#!/usr/bin/env bash
# Temp helpers: TMP_PREFIX and cleanup for update_ingress scripts

set -o errexit
set -o nounset
set -o pipefail

TMP_PREFIX="/tmp/update_ingress_$$"

cleanup_temp_files() {
    rm -f "${TMP_PREFIX}"* 2>/dev/null || true
    # If called with a signal name, exit non-zero to indicate interruption
    if [ "$#" -gt 0 ]; then
        # shellcheck disable=SC2059
        printf "\nCleanup after signal: %s\n" "$1" >&2
        exit 130
    fi
}

# Ensure temp files are removed on normal exit
trap cleanup_temp_files EXIT

# On INT/TERM we want to cleanup and then exit immediately with non-zero
_handle_signal() {
    cleanup_temp_files "$1"
}
trap '_handle_signal INT' INT
trap '_handle_signal TERM' TERM
