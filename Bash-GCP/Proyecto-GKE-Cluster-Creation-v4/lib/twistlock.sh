#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

deploy_twistlock() {
    step "Twistlock DaemonSet Deploy"

    local daemonset_file
    daemonset_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../config/daemonset.yaml"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping Twistlock deploy"
        return 0
    fi

    if [ ! -f "$daemonset_file" ]; then
        error "DaemonSet file not found: $daemonset_file"
        warn "Twistlock deploy skipped"
        return 1
    fi

    info "DaemonSet file: $daemonset_file"

    # shellcheck disable=SC2154
    if ! run_or_dry gcloud container clusters get-credentials "${cluster_name}" \
        --region "${region}" --project "${project_id}" --quiet; then
        error "Could not get cluster credentials"
        return 1
    fi

    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot connect to cluster"
        return 1
    fi

    local twistlock_namespace
    twistlock_namespace=$(grep -E "^\s*namespace:" "$daemonset_file" | head -1 | awk '{print $2}' || echo "twistlock")

    if ! kubectl get namespace "$twistlock_namespace" &>/dev/null; then
        info "Creating namespace: $twistlock_namespace"
        run_or_dry kubectl create namespace "$twistlock_namespace" 2>/dev/null || warn "Namespace may already exist"
    else
        info "Namespace exists: $twistlock_namespace"
    fi

    local max_retries=3
    local attempt=1
    while [ "$attempt" -le "$max_retries" ]; do
        info "Apply attempt $attempt/$max_retries..."
        if run_or_dry kubectl apply -f "$daemonset_file"; then
            success "Twistlock DaemonSet applied"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 10
    done

    error "Twistlock deploy failed after $max_retries attempts"
    return 1
}
