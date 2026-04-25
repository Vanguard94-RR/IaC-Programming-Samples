#!/usr/bin/env bash
# Cloud Armor sync helpers for UpdateIngress v2

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui.sh"

sync_cloud_armor() {
    : "${CLOUD_ARMOR_POLICY:=cve-canary}"
    local armor_file="${TMP_PREFIX}_new_services_armor.txt"

    if [ ! -f "$armor_file" ] || [ ! -s "$armor_file" ]; then
        info "No new services to register in Cloud Armor"
        return 0
    fi

    if ! command -v gcloud &>/dev/null; then
        warn "gcloud not available; skipping Cloud Armor sync"
        return 0
    fi

    if ! gcloud compute security-policies describe "$CLOUD_ARMOR_POLICY" --global &>/dev/null; then
        error "Cloud Armor policy '$CLOUD_ARMOR_POLICY' not found. Aborting sync."
        return 1
    fi

    step "Cloud Armor sync (policy: $CLOUD_ARMOR_POLICY)"

    local attached=0 skipped=0 svc

    while IFS= read -r svc; do
        [ -z "$svc" ] && continue

        local backend_name="" attempt
        for attempt in 1 2 3; do
            backend_name=$(gcloud compute backend-services list --global \
                --format="value(name)" \
                --filter="description~\"$NAMESPACE/$svc\"" 2>/dev/null || true)
            [ -n "$backend_name" ] && break
            [ "$attempt" -lt 3 ] && sleep 10
        done

        if [ -z "$backend_name" ]; then
            warn "  ⚠ $svc → not found after 3 retries [skipped]"
            skipped=$((skipped + 1))
            continue
        fi

        local current_policy
        current_policy=$(gcloud compute backend-services describe "$backend_name" --global \
            --format="value(securityPolicy)" 2>/dev/null || true)
        if printf '%s' "$current_policy" | grep -q "/$CLOUD_ARMOR_POLICY$"; then
            info "  ● $svc → $backend_name [already attached]"
            continue
        fi

        if gcloud compute backend-services update "$backend_name" \
            --security-policy "$CLOUD_ARMOR_POLICY" --global &>/dev/null; then
            success "  + $svc → $backend_name [attached]"
            attached=$((attached + 1))
        else
            warn "  ✖ $svc → $backend_name [attach failed]"
            skipped=$((skipped + 1))
        fi

    done < "$armor_file"

    success "Cloud Armor sync complete ($attached attached, $skipped skipped)"
}
