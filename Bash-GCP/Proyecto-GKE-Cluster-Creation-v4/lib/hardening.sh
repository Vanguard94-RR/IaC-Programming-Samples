#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

POLICY_NAME="cve-canary"
SSL_POLICY_NAME="sslsecure"
WAF_ALLOWED_IPS="35.238.84.248,34.121.197.40"

cmd_update_armor() {
    step "Cloud Armor Rules Update"
    _preflight_checks

    prompt_or_arg project_id "${ARG_PROJECT:-}" "GCP Project ID" ""
    [ -z "${project_id:-}" ] && { error "project_id required"; return 1; }

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping Cloud Armor update"
        return 0
    fi

    local backup_file="${LOG_FILE%.log}-armor-backup-${project_id}.json"
    info "Backup will be written to: $backup_file"

    if gcloud compute security-policies describe "$POLICY_NAME" \
        --project="$project_id" &>/dev/null; then
        info "Backing up existing policy..."
        gcloud compute security-policies export "$POLICY_NAME" \
            --project="$project_id" \
            --format=json > "$backup_file" 2>/dev/null \
            || warn "Could not export policy — backup skipped"
        success "Backup: $backup_file"
    else
        info "Policy '$POLICY_NAME' does not exist — creating fresh"
        run_or_dry gcloud compute security-policies create "$POLICY_NAME" \
            --description="GNP CVE Canary WAF policy" \
            --project="$project_id"
    fi

    _apply_armor_rules "$project_id"
    success "Cloud Armor rules updated"
}

cmd_rollback_armor() {
    step "Cloud Armor Rollback"
    _preflight_checks

    prompt_or_arg project_id "${ARG_PROJECT:-}" "GCP Project ID" ""
    [ -z "${project_id:-}" ] && { error "project_id required"; return 1; }

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping Cloud Armor rollback"
        return 0
    fi

    local backup_file=""
    local latest_backup
    latest_backup=$(find "${LOG_FILE%/*}" -maxdepth 1 -name "*-armor-backup-${project_id}.json" -printf '%T+\t%p\n' 2>/dev/null | sort -r | head -1 | cut -f2 || true)

    if [ -n "$latest_backup" ]; then
        info "Latest backup found: $latest_backup"
        local confirm
        read_input confirm "${CYAN}Use this backup? (Y/N): ${NC}"
        [[ "$confirm" =~ ^[Yy]$ ]] && backup_file="$latest_backup"
    fi

    if [ -z "$backup_file" ]; then
        read_input backup_file "${CYAN}Enter path to backup JSON file: ${NC}"
    fi

    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
        return 1
    fi

    info "Restoring from: $backup_file"
    if run_or_dry gcloud compute security-policies import "$POLICY_NAME" \
        --source="$backup_file" \
        --project="$project_id" \
        --quiet; then
        success "Cloud Armor rules restored from backup"
    else
        error "Rollback failed"
        return 1
    fi
}

apply_cluster_hardening() {
    step "Cluster Security Hardening"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping hardening"
        return 0
    fi

    local missing=()
    command -v jq &>/dev/null || missing+=("jq")
    command -v kubectl &>/dev/null || missing+=("kubectl")
    if [ "${#missing[@]}" -gt 0 ]; then
        error "Missing dependencies: ${missing[*]}"
        return 1
    fi

    # shellcheck disable=SC2154
    if ! run_or_dry gcloud container clusters get-credentials "${cluster_name}" \
        --region "${region}" --project "${project_id}" --quiet; then
        error "Could not get cluster credentials"
        return 1
    fi

    if gcloud compute security-policies describe "$POLICY_NAME" \
        --project="${project_id}" &>/dev/null; then
        info "Security policy '$POLICY_NAME' already exists"
    else
        info "Creating security policy: $POLICY_NAME"
        run_or_dry gcloud compute security-policies create "$POLICY_NAME" \
            --description="GNP CVE Canary WAF policy" \
            --project="${project_id}"
    fi

    _apply_armor_rules "${project_id}"

    if gcloud compute ssl-policies describe "$SSL_POLICY_NAME" \
        --project="${project_id}" &>/dev/null; then
        info "SSL policy '$SSL_POLICY_NAME' already exists"
    else
        info "Creating SSL policy (TLS 1.2+ MODERN)..."
        run_or_dry gcloud compute ssl-policies create "$SSL_POLICY_NAME" \
            --profile=MODERN \
            --min-tls-version=1.2 \
            --project="${project_id}" \
            || warn "SSL policy creation failed — continuing"
        success "SSL policy created"
    fi

    for api in certificatemanager.googleapis.com containersecurity.googleapis.com; do
        run_or_dry gcloud services enable "$api" --project="${project_id}" 2>/dev/null \
            || warn "$api already enabled"
    done

    local cert_map="${project_id}-cert-map"
    if ! gcloud certificate-manager maps describe "$cert_map" \
        --project="${project_id}" --quiet &>/dev/null; then
        run_or_dry gcloud certificate-manager maps create "$cert_map" \
            --project="${project_id}" --quiet \
            || warn "Certificate Map creation failed — continuing"
    fi
    success "Hardening complete"
}

_apply_armor_rules() {
    local proj="$1"

    _upsert_rule "$proj" 100 \
        "evaluatePreconfiguredExpr('cve-canary')" \
        "deny-403" \
        "CVE-Canary WAF"

    _upsert_rule "$proj" 200 \
        "evaluatePreconfiguredExpr('xss-stable') || evaluatePreconfiguredExpr('sqli-stable')" \
        "deny-403" \
        "WAF XSS-SQLi"

    local allow_expr
    allow_expr="inIpRange(origin.ip, '${WAF_ALLOWED_IPS//,/\') || inIpRange(origin.ip, \'}')"
    _upsert_rule "$proj" 300 \
        "$allow_expr" \
        "allow" \
        "Allow known IPs"

    _upsert_rule "$proj" 400 \
        "true" \
        "throttle" \
        "Rate limit"

    _upsert_rule "$proj" 2147483647 \
        "true" \
        "deny-403" \
        "Default deny"

    run_or_dry gcloud compute security-policies update "$POLICY_NAME" \
        --json-parsing=STANDARD \
        --project="$proj" 2>/dev/null || warn "JSON parsing already set"

    local backends
    backends=$(gcloud compute backend-services list \
        --project="$proj" --format="value(name)" 2>/dev/null || true)

    local count=0 updated=0
    while IFS= read -r svc; do
        if [ -z "$svc" ]; then continue; fi
        count=$((count + 1))
        if run_or_dry gcloud compute backend-services update "$svc" \
            --security-policy="$POLICY_NAME" \
            --global --project="$proj" 2>/dev/null; then
            success "  Applied to: $svc"
            updated=$((updated + 1))
        else
            warn "  Failed: $svc"
        fi
    done <<< "$backends"
    if [ "$count" -gt 0 ]; then info "Backend services: $updated/$count updated"; fi
}

_upsert_rule() {
    local proj="$1" priority="$2" expression="$3" action="$4" description="$5"

    local throttle_flags=""
    if [ "$action" = "throttle" ]; then
        throttle_flags="--rate-limit-threshold-count=100 --rate-limit-threshold-interval-sec=60 --conform-action=allow --exceed-action=deny-403 --enforce-on-key=IP"
    fi

    # Default rule (2147483647) requires --src-ip-ranges=* not --expression
    local match_flag="--expression=${expression}"
    [ "$priority" = "2147483647" ] && match_flag="--src-ip-ranges=*"

    if gcloud compute security-policies rules describe "$priority" \
        --security-policy="$POLICY_NAME" --project="$proj" &>/dev/null; then
        local existing_action
        existing_action=$(gcloud compute security-policies rules describe "$priority" \
            --security-policy="$POLICY_NAME" --project="$proj" \
            --format="value(action)" 2>/dev/null || true)
        if [ "$existing_action" = "$action" ]; then
            info "  Rule $priority: already correct ($description)"
            return 0
        fi
        info "  Rule $priority: updating ($description)..."
        # shellcheck disable=SC2086
        run_or_dry gcloud compute security-policies rules update "$priority" \
            --security-policy="$POLICY_NAME" \
            "$match_flag" \
            --action="$action" \
            --description="$description" \
            --project="$proj" \
            $throttle_flags
    else
        info "  Rule $priority: creating ($description)..."
        # shellcheck disable=SC2086
        run_or_dry gcloud compute security-policies rules create "$priority" \
            --security-policy="$POLICY_NAME" \
            "$match_flag" \
            --action="$action" \
            --description="$description" \
            --project="$proj" \
            $throttle_flags
    fi
    success "  Rule $priority: done"
}

# --- cmd_log4j ---
# Subcommand: log4j — apply or backup log4j WAF rules
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
    info "Applying log4j WAF rules to policy: $POLICY_NAME in project: $project_id"

    if ! gcloud compute security-policies describe "$POLICY_NAME" \
        --project="$project_id" &>/dev/null; then
        error "Security policy '$POLICY_NAME' not found in project '$project_id'"
        info "Run 'update-armor' subcommand first to create the policy"
        return 1
    fi

    local backup_file="${LOG_FILE%.log}-log4j-backup-${project_id}.json"
    info "Creating backup: $backup_file"
    gcloud compute security-policies export "$POLICY_NAME" \
        --project="$project_id" \
        --format=json > "$backup_file" 2>/dev/null || warn "Could not backup — continuing"

    local priority=1000
    local expression="evaluatePreconfiguredExpr('cve-canary')"
    local action="deny-403"
    local description="log4j CVE RCE block"

    if gcloud compute security-policies rules describe "$priority" \
        --security-policy="$POLICY_NAME" --project="$project_id" &>/dev/null; then
        info "Rule $priority exists — updating..."
        run_or_dry gcloud compute security-policies rules update "$priority" \
            --security-policy="$POLICY_NAME" \
            --expression="$expression" \
            --action="$action" \
            --description="$description" \
            --project="$project_id"
    else
        info "Creating rule $priority..."
        run_or_dry gcloud compute security-policies rules create "$priority" \
            --security-policy="$POLICY_NAME" \
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

    if run_or_dry gcloud compute security-policies export "$POLICY_NAME" \
        --project="$project_id" \
        --format=json > "$backup_file"; then
        success "Backup complete: $backup_file"
    else
        error "Backup failed"
        return 1
    fi
}
