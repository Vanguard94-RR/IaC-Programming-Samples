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

# Fix deprecated Ingress API versions
# Converts v1beta1 → v1 (required by modern clusters)
fix_ingress_apiversion() {
    local file="${1:-ingress.yaml}"
    
    if [ ! -f "$file" ]; then
        if declare -f error >/dev/null 2>&1; then
            error "File not found: $file"
        fi
        return 1
    fi
    
    # Check if file uses v1beta1
    if grep -q "apiVersion: networking.k8s.io/v1beta1" "$file"; then
        if declare -f info >/dev/null 2>&1; then
            info "Correcting apiVersion: networking.k8s.io/v1beta1 → v1"
        fi
        sed -i 's/apiVersion: networking\.k8s\.io\/v1beta1/apiVersion: networking.k8s.io\/v1/g' "$file"
        return 0
    elif grep -q "apiVersion: extensions/v1beta1" "$file"; then
        if declare -f info >/dev/null 2>&1; then
            info "Correcting apiVersion: extensions/v1beta1 → networking.k8s.io/v1"
        fi
        sed -i 's/apiVersion: extensions\/v1beta1/apiVersion: networking.k8s.io\/v1/g' "$file"
        return 0
    else
        if declare -f info >/dev/null 2>&1; then
            info "apiVersion already up-to-date"
        fi
        return 0
    fi
}
