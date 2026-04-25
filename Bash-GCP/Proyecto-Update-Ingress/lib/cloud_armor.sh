#!/usr/bin/env bash
# Cloud Armor sync helpers for UpdateIngress v2

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui.sh"

sync_cloud_armor() {
    : "${CLOUD_ARMOR_POLICY:=cve-canary}"
    local new_file="${TMP_PREFIX}_new_services_armor.txt"
    local existing_file="${TMP_PREFIX}_existing_services_armor.txt"
    local has_new=false has_existing=false

    [ -f "$new_file" ]      && [ -s "$new_file" ]      && has_new=true
    [ -f "$existing_file" ] && [ -s "$existing_file" ] && has_existing=true

    if [ "$has_new" = false ] && [ "$has_existing" = false ]; then
        info "Cloud Armor (policy: ${CLOUD_ARMOR_POLICY}): no services to check"
        return 0
    fi

    if ! command -v gcloud &>/dev/null; then
        warn "Cloud Armor (policy: ${CLOUD_ARMOR_POLICY}): gcloud not available, skipping"
        return 0
    fi

    if ! gcloud compute security-policies describe "$CLOUD_ARMOR_POLICY" --global &>/dev/null; then
        error "Cloud Armor policy '$CLOUD_ARMOR_POLICY' not found. Aborting."
        return 1
    fi

    # ── Register new services ──────────────────────────────────────────────────
    if [ "$has_new" = true ]; then
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

        done < "$new_file"

        success "Cloud Armor sync complete ($attached attached, $skipped skipped)"
    else
        info "Cloud Armor (policy: ${CLOUD_ARMOR_POLICY}): no new services to register"
    fi

    # ── Validate existing services ─────────────────────────────────────────────
    if [ "$has_existing" = true ]; then
        step "Cloud Armor status — existing services (policy: $CLOUD_ARMOR_POLICY)"
        local ok=0 missing=0 esvc

        while IFS= read -r esvc; do
            [ -z "$esvc" ] && continue

            local be_name=""
            be_name=$(gcloud compute backend-services list --global \
                --format="value(name)" \
                --filter="description~\"$NAMESPACE/$esvc\"" 2>/dev/null || true)

            if [ -z "$be_name" ]; then
                warn "  ? $esvc → GCP backend not found"
                missing=$((missing + 1))
                continue
            fi

            local cur_pol
            cur_pol=$(gcloud compute backend-services describe "$be_name" --global \
                --format="value(securityPolicy)" 2>/dev/null || true)

            if printf '%s' "$cur_pol" | grep -q "/$CLOUD_ARMOR_POLICY$"; then
                info "  ✔ $esvc → $be_name"
                ok=$((ok + 1))
            else
                warn "  ✖ $esvc → $be_name [policy NOT attached]"
                missing=$((missing + 1))
            fi
        done < "$existing_file"

        if [ "$missing" -gt 0 ]; then
            warn "Cloud Armor status: $ok attached, $missing without policy"
        else
            success "Cloud Armor status: all $ok existing service(s) ✔"
        fi
    fi
}
