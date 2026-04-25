#!/usr/bin/env bash
# post_apply_validation - extracted from kube_compare_apply

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/healthcheck.sh"

post_apply_validation() {
    # Defaults (seconds) if not provided by environment
    : ${LB_TIMEOUT:=300}
    : ${HEALTHCHECK_TIMEOUT:=300}
    : ${HEALTHCHECK_INTERVAL:=60}

    step "Post-apply validation: waiting for LoadBalancer IP (timeout ${LB_TIMEOUT}s)..."
    local interval=5
    local elapsed=0
    local ip=""
    progress_bar_start $LB_TIMEOUT
    while [ $elapsed -lt $LB_TIMEOUT ]; do
        ip=$(kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
        if [ -n "$ip" ]; then
            progress_bar_stop
            success "LoadBalancer IP assigned: $ip"
            break
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        progress_bar_update $elapsed $LB_TIMEOUT
    done
    progress_bar_stop
    if [ -z "$ip" ]; then
        error "Timeout waiting for LoadBalancer IP"
    else
        info "Performing basic HTTP HEAD request to the LB IP..."
        if command -v curl &> /dev/null; then
            local http_code
            http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$ip/" 2>/dev/null || true)
            if [ -n "$http_code" ]; then
                info "HTTP status: ${http_code}"
            else
                warn "HTTP check failed or timed out"
            fi
        else
            warn "curl not available; skipping HTTP check."
        fi
        sync_cloud_armor
    fi

    if command -v curl &> /dev/null; then
        info "Waiting for backend health checks (timeout: ${HEALTHCHECK_TIMEOUT}s, interval: ${HEALTHCHECK_INTERVAL}s)"
        local start_time
        start_time=$(date +%s)
        while true; do
            if validate_health_checks "$INGRESS_NAME" "$NAMESPACE" "$ip"; then
                success "All backend health checks are OK"
                break
            else
                if [ "$HEALTHCHECK_TIMEOUT" -gt 0 ]; then
                    local now
                    now=$(date +%s)
                    local elapsed=$((now - start_time))
                    if [ $elapsed -ge $HEALTHCHECK_TIMEOUT ]; then
                        error "Health-check global timeout reached (${HEALTHCHECK_TIMEOUT}s). Exiting with failures."
                        return 1
                    fi
                fi
                warn "Some checks failing."
                local j
                for ((j=HEALTHCHECK_INTERVAL; j>0; j--)); do
                    printf "\r  ${CYAN}Next check in: %ds  [Ctrl+C to abort]${NC}  " "$j"
                    sleep 1
                done
                printf "\r%-60s\r" ""
            fi
        done
    else
        warn "curl not available; skipping per-backend health check validation."
    fi

    info "Recent events in namespace $NAMESPACE (last 3):"
    kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp | tail -n 3 || true
}
