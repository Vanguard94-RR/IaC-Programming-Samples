#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

create_ssl_certificate() {
    local ssl_cert_name="${project_id}-ssl-cert"
    local cert_file
    cert_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../config/bundle.cer"
    local key_file
    key_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../KEY_gnp.com.mx_Marzo_2024.key"

    step "SSL Certificate"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping SSL cert creation"
        return 0
    fi

    if [ ! -f "$cert_file" ]; then
        warn "Certificate bundle not found: $cert_file — skipping SSL cert"
        return 0
    fi

    if [ ! -f "$key_file" ]; then
        warn "Key file not found: $key_file — skipping SSL cert"
        return 0
    fi

    if run_or_dry gcloud compute ssl-certificates describe "$ssl_cert_name" \
        --project="${project_id}" --quiet &>/dev/null; then
        success "SSL certificate already exists: $ssl_cert_name"
        return 0
    fi

    info "Creating Classic SSL certificate: $ssl_cert_name"
    if run_or_dry gcloud compute ssl-certificates create "$ssl_cert_name" \
        --certificate="$cert_file" \
        --private-key="$key_file" \
        --project="${project_id}" \
        --global; then
        success "SSL certificate created: $ssl_cert_name"
    else
        warn "SSL certificate creation failed — continuing"
    fi
}
