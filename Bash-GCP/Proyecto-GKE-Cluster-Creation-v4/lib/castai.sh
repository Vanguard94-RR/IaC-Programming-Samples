#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

deploy_castai() {
    step "CastAI Deploy"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping CastAI deploy"
        return 0
    fi

    local castai_env
    castai_env="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../config/castai.env"

    if [ ! -f "$castai_env" ]; then
        error "CastAI config not found: $castai_env"
        return 1
    fi

    # shellcheck source=/dev/null
    . "$castai_env"

    local var
    for var in CASTAI_API_TOKEN CASTAI_TRACKING_ID CREDENTIALS_SCRIPT_API_TOKEN; do
        if [ -z "${!var:-}" ]; then
            error "$var not set in $castai_env"
            return 1
        fi
    done

    local api_url="${CASTAI_API_URL:-https://api.cast.ai}"
    local tracking_id="${CASTAI_TRACKING_ID}"

    if [ "${DRY_RUN:-false}" = "true" ]; then
        local token_short="${CASTAI_API_TOKEN:0:20}..."
        local cred_short="${CREDENTIALS_SCRIPT_API_TOKEN:0:20}..."
        info "[DRY-RUN] Would execute:"
        info "  CASTAI_API_TOKEN=${token_short} \\"
        info "  CASTAI_API_URL=${api_url} \\"
        info "  CASTAI_TRACKING_ID=${tracking_id} \\"
        info "  CREDENTIALS_SCRIPT_API_TOKEN=${cred_short} \\"
        info "  INSTALL_AUTOSCALER=true INSTALL_POD_MUTATOR=true \\"
        info "  INSTALL_UMBRELLA=true INSTALL_WORKLOAD_AUTOSCALER=true \\"
        info "  PROVIDER=gke SEND_ONBOARDING_LOGS_FEATURE_FLAG=true \\"
        info "  /bin/bash -c \"\$(curl -fsSL -H 'X-Tracking-ID: ${tracking_id}' '${api_url}/v1/scripts/connect-and-enable-castai.sh')\""
        return 0
    fi

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

    if ! command -v helm &>/dev/null; then
        info "helm not found — installing"
        if ! curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; then
            error "helm installation failed"
            return 1
        fi
        success "helm installed: $(helm version --short)"
    fi

    info "Downloading CastAI install script"
    local castai_script
    if ! castai_script=$(curl -fsSL \
        -H "X-Tracking-ID: ${tracking_id}" \
        "${api_url}/v1/scripts/connect-and-enable-castai.sh"); then
        error "Failed to download CastAI install script"
        return 1
    fi

    info "Installing CastAI on cluster: ${cluster_name}"
    if CASTAI_API_TOKEN="${CASTAI_API_TOKEN}" \
        CASTAI_API_URL="${api_url}" \
        CASTAI_TRACKING_ID="${tracking_id}" \
        CREDENTIALS_SCRIPT_API_TOKEN="${CREDENTIALS_SCRIPT_API_TOKEN}" \
        INSTALL_AUTOSCALER=true \
        INSTALL_POD_MUTATOR=true \
        INSTALL_UMBRELLA=true \
        INSTALL_WORKLOAD_AUTOSCALER=true \
        PROVIDER=gke \
        SEND_ONBOARDING_LOGS_FEATURE_FLAG=true \
        /bin/bash -c "${castai_script}"; then
        success "CastAI installed on cluster: ${cluster_name}"
    else
        error "CastAI deploy failed"
        return 1
    fi
}
