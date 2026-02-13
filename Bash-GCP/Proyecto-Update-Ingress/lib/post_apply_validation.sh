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

    echo -e "${YELLOW}Post-apply validation: waiting for LoadBalancer IP (timeout ${LB_TIMEOUT}s)...${NC}"
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
        echo -e "${RED}Timeout waiting for LoadBalancer IP${NC}"
    else
        echo -e "${YELLOW}Performing basic HTTP HEAD request to the LB IP...${NC}"
        if command -v curl &> /dev/null; then
            curl -I --max-time 10 "http://$ip/" || echo -e "${RED}HTTP check failed or timed out${NC}"
        else
            echo -e "${YELLOW}curl not available; skipping HTTP check.${NC}"
        fi
    fi

    if command -v curl &> /dev/null; then
        echo -e "${YELLOW}Waiting for all backend health checks to return 2xx/3xx. Re-checking every ${HEALTHCHECK_INTERVAL}s. Press Ctrl+C to abort.${NC}"
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
                warn "Some backend health checks are failing. Rechecking in ${HEALTHCHECK_INTERVAL}s..."
                sleep $HEALTHCHECK_INTERVAL
            fi
        done
    else
        echo -e "${YELLOW}curl not available; skipping per-backend health check validation.${NC}"
    fi

    echo -e "${CYAN}Recent events in namespace $NAMESPACE (last 3):${NC}"
    kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp | tail -n 3 || true
}
