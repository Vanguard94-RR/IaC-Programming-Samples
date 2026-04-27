# Cloud NAT: Mandatory + Static IP

**Date:** 2026-04-27  
**File:** `lib/vpc.sh`  
**Status:** Approved

## Requirements

1. Cloud NAT created for all environments (qa, uat, pro) — mandatory, no prompt
2. Static IP allocation — no auto-allocate mode
3. Naming convention: `{project_id}-nat-ip` (IP), `{project_id}-nat` (NAT), `{project_id}-router` (router)

## Current Behavior

`_setup_cloud_nat()` in `lib/vpc.sh:183`:
- PRO: prompts with default=1 (create)
- QA/UAT: prompts with default=2 (skip)
- Router exists + no NAT: prompts user
- `_create_nat()` uses `--auto-allocate-nat-external-ips`

## New Design

### `_setup_cloud_nat()` — rewritten

Prompt/skip logic removed. Always executes.

```
1. NO_CLUSTER guard → return
2. router_name = {project_id}-router
3. nat_name   = {project_id}-nat
4. If NAT already exists → success + return  (idempotent)
5. If router missing → create router
6. _reserve_nat_ip()  → sets NAT_IP_NAME
7. _create_nat(router_name, nat_name)
```

### New helper `_reserve_nat_ip()`

Insert before `_create_nat()` in file.

```bash
_reserve_nat_ip() {
    local ip_name="${project_id}-nat-ip"
    if gcloud compute addresses describe "$ip_name" \
        --region="${region}" --project="${project_id}" &>/dev/null; then
        success "Static IP exists: $ip_name"
    else
        info "Reserving static IP: $ip_name"
        run_or_dry gcloud compute addresses create "$ip_name" \
            --region="${region}" \
            --project="${project_id}"
    fi
    NAT_IP_NAME="$ip_name"
}
```

Idempotent — reuses existing reserved IP if found.

### `_create_nat()` — one line change

Replace:
```bash
--auto-allocate-nat-external-ips \
```
With:
```bash
--nat-external-ip-pool="${NAT_IP_NAME}" \
```

All timeout flags unchanged.

## Idempotency Matrix

| State | Action |
|---|---|
| NAT exists | skip (success msg) |
| Router exists, no NAT | reserve IP → create NAT |
| Nothing exists | create router → reserve IP → create NAT |
| IP exists, NAT missing | reuse IP → create NAT |

## Smoke Test

`NO_CLUSTER=1 DRY_RUN=true` — `_setup_cloud_nat` returns early on `NO_CLUSTER=1` before calling `_reserve_nat_ip`, so existing smoke test path unaffected.
