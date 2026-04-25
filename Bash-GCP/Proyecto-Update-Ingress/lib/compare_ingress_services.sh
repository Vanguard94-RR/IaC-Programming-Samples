#!/usr/bin/env bash
# compare_ingress_services - extracted from kube_compare_apply

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui.sh"

compare_ingress_services() {
    step "Backend service comparison"
    local old_yaml="$BACKUP_FILE"
    local new_yaml="ingress.yaml"
    local old_services="${TMP_PREFIX}_services_old.txt"
    local new_services="${TMP_PREFIX}_services_new.txt"

    if [ ! -f "$old_yaml" ]; then
        error "Backup file not found: $old_yaml"
        return 1
    fi
    if [ ! -f "$new_yaml" ]; then
        error "New ingress file not found: $new_yaml"
        return 1
    fi

    if ! yq eval '.spec.rules[].http.paths[].backend.service.name' "$old_yaml" | sort -u > "$old_services"; then
        error "Failed to extract services from current ingress"
        return 1
    fi
    if ! yq eval '.spec.rules[].http.paths[].backend.service.name' "$new_yaml" | sort -u > "$new_services"; then
        error "Failed to extract services from new ingress"
        return 1
    fi

    local old_list="${TMP_PREFIX}_services_old_list.txt"
    local new_list="${TMP_PREFIX}_services_new_list.txt"
    sort "$old_services" > "$old_list"
    sort "$new_services" > "$new_list"

    local added removed unchanged
    comm -13 "$old_list" "$new_list" > "${TMP_PREFIX}_new_services_armor.txt"
    added=$(wc -l < "${TMP_PREFIX}_new_services_armor.txt" | tr -d ' ')
    removed=$(comm -23 "$old_list" "$new_list" | wc -l | tr -d ' ')
    unchanged=$(comm -12 "$old_list" "$new_list" | wc -l | tr -d ' ')

    # Unchanged: inline names when ≤3, count-only when >3
    local unchanged_inline=""
    if [ "$unchanged" -gt 0 ] && [ "$unchanged" -le 3 ]; then
        unchanged_inline="  ($(comm -12 "$old_list" "$new_list" | tr '\n' ',' | sed 's/,$//') )"
    fi

    printf "  ${GREEN}✚ New:      %s${NC}\n" "$added"
    printf "  ${RED}✖ Removed:  %s${NC}\n" "$removed"
    if [ "$unchanged" -gt 3 ]; then
        printf "  ${CYAN}● Unchanged: %s services${NC}\n" "$unchanged"
    else
        printf "  ${CYAN}● Unchanged: %s%s${NC}\n" "$unchanged" "$unchanged_inline"
    fi

    if [ "$added" -gt 0 ]; then
        echo ""
        info "New services:"
        comm -13 "$old_list" "$new_list" | sed 's/^/    + /'
    fi

    if [ "$removed" -gt 0 ]; then
        echo ""
        info "Removed services:"
        comm -23 "$old_list" "$new_list" | sed 's/^/    - /'
    fi

    rm -f "$old_list" "$new_list" "$old_services" "$new_services"

    # Path comparison
    local old_paths="${TMP_PREFIX}_paths_old.txt"
    local new_paths="${TMP_PREFIX}_paths_new.txt"
    yq eval '.spec.rules[].http.paths[] | [.backend.service.name, .path] | @tsv' "$old_yaml" | sort > "$old_paths"
    yq eval '.spec.rules[].http.paths[] | [.backend.service.name, .path] | @tsv' "$new_yaml" | sort > "$new_paths"

    local added_paths removed_paths
    added_paths=$(comm -13 "$old_paths" "$new_paths" | wc -l | tr -d ' ')
    removed_paths=$(comm -23 "$old_paths" "$new_paths" | wc -l | tr -d ' ')

    if [ "$added_paths" -gt 0 ]; then
        echo ""
        info "New paths:"
        comm -13 "$old_paths" "$new_paths" | awk -F'\t' '{printf "    + %-30s → %s\n", $1, $2}'
    fi

    if [ "$removed_paths" -gt 0 ]; then
        echo ""
        info "Removed paths:"
        comm -23 "$old_paths" "$new_paths" | awk -F'\t' '{printf "    - %-30s → %s\n", $1, $2}'
    fi

    # Modified paths per-service (conditional — only header if there is content)
    local services_all="${TMP_PREFIX}_services_all.txt"
    local has_modified=false
    if awk -F'\t' '{print $1}' "$old_paths" | sort | uniq > "$services_all" 2>/dev/null; then
        while read -r svc; do
            [ -z "${svc}" ] && continue
            local old_svc_paths new_svc_paths
            old_svc_paths=$(awk -F'\t' -v s="$svc" '$1==s {print $2}' "$old_paths" | sort)
            new_svc_paths=$(awk -F'\t' -v s="$svc" '$1==s {print $2}' "$new_paths" | sort)
            if [ -n "$old_svc_paths" ] && [ -n "$new_svc_paths" ]; then
                local old_temp="${TMP_PREFIX}_old_${svc//[^a-zA-Z0-9]/_}.txt"
                local new_temp="${TMP_PREFIX}_new_${svc//[^a-zA-Z0-9]/_}.txt"
                printf "%s\n" "$old_svc_paths" > "$old_temp"
                printf "%s\n" "$new_svc_paths" > "$new_temp"
                if ! diff "$old_temp" "$new_temp" >/dev/null 2>&1; then
                    if [ "$has_modified" = false ]; then
                        echo ""
                        info "Modified paths (service/path changed):"
                        has_modified=true
                    fi
                    printf "    %s\n" "$svc"
                    diff "$old_temp" "$new_temp" 2>/dev/null | grep -E '^[<>]' \
                        | sed 's/^</      old: /;s/^>/      new: /' || true
                fi
                rm -f "$old_temp" "$new_temp" 2>/dev/null || true
            fi
        done < "$services_all"
    fi

    rm -f "$old_paths" "$new_paths" "$services_all" 2>/dev/null || true

    echo ""
    success "Comparison complete"
    return 0
}
