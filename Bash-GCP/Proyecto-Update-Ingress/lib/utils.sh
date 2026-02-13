#!/usr/bin/env bash
# Utility helpers for Proyecto-Update-Ingress

set -o errexit
set -o nounset
set -o pipefail

# UI-aware validate_number: returns 0 if input is a number between 1 and max
validate_number() {
    local input=$1
    local max=$2

    # fall back to simple echo messages if UI functions are missing
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        if declare -f error >/dev/null 2>&1; then
            error "Invalid input. Please enter a number."
        else
            printf '%s\n' "Invalid input. Please enter a number." >&2
        fi
        return 1
    fi

    if [ "$input" -lt 1 ] || [ "$input" -gt "$max" ]; then
        if declare -f error >/dev/null 2>&1; then
            error "Invalid selection. Please enter a number between 1 and $max."
        else
            printf '%s\n' "Invalid selection. Please enter a number between 1 and $max." >&2
        fi
        return 1
    fi

    return 0
}
