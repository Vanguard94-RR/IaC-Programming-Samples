#!/usr/bin/env bash
# apply_new_ingress - extracted from kube_compare_apply

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compare_ingress_services.sh"

apply_new_ingress() {
    step "Applying new Ingress"
    
    # Detect if ingress already exists (UPDATE) or is new (CREATE)
    local operation="CREATE"
    if kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        operation="UPDATE"
        info "Operation: UPDATE (Ingress already exists)"
    else
        info "Operation: CREATE (new Ingress)"
    fi
    
    info "Validating ingress.yaml (server-side dry-run)..."
    if ! kubectl apply -f ingress.yaml -n "$NAMESPACE" --dry-run=server >/dev/null 2>&1; then
        error "ingress.yaml failed server-side validation. Aborting."
        kubectl apply -f ingress.yaml -n "$NAMESPACE" --dry-run=server -o yaml || true
        return 1
    fi
    success "Server-side dry-run validation passed"

    # Show diff of changes if it's an update
    if [ "$operation" = "UPDATE" ] && [ -f "$BACKUP_FILE" ]; then
        step "Preview of changes (kubectl diff)"
        local diff_output
        diff_output=$(kubectl diff -f ingress.yaml -n "$NAMESPACE" 2>/dev/null || true)
        if [ -n "$diff_output" ]; then
            printf "%s\n" "$diff_output"
        else
            info "No structural changes detected"
        fi
    fi

    if ! compare_ingress_services; then
        warn "Service comparison failed, but continuing with apply process"
    fi

    if [ "${DRY_RUN:-false}" = "true" ]; then
        info "Dry-run: validation passed, no changes applied."
        return 0
    fi

    warn "Apply new ingress.yaml? (${operation})"
    printf "%b" "${CYAN}Type '${WHITE}${BOLD}yes${NC}${CYAN}' or '${WHITE}${BOLD}Y${NC}${CYAN}' to continue: ${NC}"
    read_input CONFIRM ""
    CONFIRM_LOWER=$(printf "%s" "$CONFIRM" | tr '[:upper:]' '[:lower:]')
    if [ "$CONFIRM_LOWER" = "yes" ] || [ "$CONFIRM_LOWER" = "y" ]; then
        info "Applying changes to Ingress..."
        local apply_output
        apply_output=$(kubectl apply -f ingress.yaml -n "$NAMESPACE" 2>&1)
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            if echo "$apply_output" | grep -q "configured"; then
                success "Ingress updated: $apply_output"
                DEPLOY_RESULT="✔ UPDATED"
            elif echo "$apply_output" | grep -q "created"; then
                success "Ingress created: $apply_output"
                DEPLOY_RESULT="✔ CREATED"
            elif echo "$apply_output" | grep -q "unchanged"; then
                info "Ingress unchanged: $apply_output"
                DEPLOY_RESULT="● UNCHANGED"
            else
                success "Ingress applied: $apply_output"
                DEPLOY_RESULT="✔ APPLIED"
            fi
            post_apply_validation
        else
            error "Failed to apply Ingress: $apply_output"
            DEPLOY_RESULT="✖ FAILED"
            return 1
        fi
    else
        info "Cancelled. No changes applied."
        DEPLOY_RESULT="⚠ CANCELLED"
    fi
}
