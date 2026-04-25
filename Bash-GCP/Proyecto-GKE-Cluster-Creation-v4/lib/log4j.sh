#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

LOG4J_POLICY="cve-canary"

cmd_log4j() {
    step "log4j WAF Rules"

    prompt_or_arg project_id "${ARG_PROJECT:-}" "GCP Project ID" ""
    [ -z "${project_id:-}" ] && { error "project_id required"; return 1; }

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping log4j operations"
        return 0
    fi

    info "[1] Apply log4j rules"
    info "[2] Backup current log4j rules"
    local choice
    read_input choice "${CYAN}Select operation [1-2]: ${NC}"

    case "${choice:-1}" in
        1) _apply_log4j_rules ;;
        2) _backup_log4j_rules ;;
        *) error "Invalid option"; return 1 ;;
    esac
}

_apply_log4j_rules() {
    info "Applying log4j WAF rules to policy: $LOG4J_POLICY in project: $project_id"

    if ! gcloud compute security-policies describe "$LOG4J_POLICY" \
        --project="$project_id" &>/dev/null; then
        error "Security policy '$LOG4J_POLICY' not found in project '$project_id'"
        info "Run 'update-armor' subcommand first to create the policy"
        return 1
    fi

    local backup_file="${LOG_FILE%.log}-log4j-backup-${project_id}.json"
    info "Creating backup: $backup_file"
    gcloud compute security-policies export "$LOG4J_POLICY" \
        --project="$project_id" \
        --format=json > "$backup_file" 2>/dev/null || warn "Could not backup — continuing"

    local priority=1000
    local expression="evaluatePreconfiguredExpr('cve-canary-stable')"
    local action="deny(403)"
    local description="log4j CVE RCE block"

    if gcloud compute security-policies rules describe "$priority" \
        --security-policy="$LOG4J_POLICY" --project="$project_id" &>/dev/null; then
        info "Rule $priority exists — updating..."
        run_or_dry gcloud compute security-policies rules update "$priority" \
            --security-policy="$LOG4J_POLICY" \
            --expression="$expression" \
            --action="$action" \
            --description="$description" \
            --project="$project_id"
    else
        info "Creating rule $priority..."
        run_or_dry gcloud compute security-policies rules create "$priority" \
            --security-policy="$LOG4J_POLICY" \
            --expression="$expression" \
            --action="$action" \
            --description="$description" \
            --project="$project_id"
    fi

    success "log4j rule applied (priority $priority)"
}

_backup_log4j_rules() {
    local backup_file="${LOG_FILE%.log}-log4j-backup-${project_id}.json"
    info "Backing up Cloud Armor policy to: $backup_file"

    if run_or_dry gcloud compute security-policies export "$LOG4J_POLICY" \
        --project="$project_id" \
        --format=json > "$backup_file"; then
        success "Backup complete: $backup_file"
    else
        error "Backup failed"
        return 1
    fi
}
