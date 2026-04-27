# Cloud NAT Mandatory + Static IP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Cloud NAT mandatory for all environments (qa/uat/pro) with static IP allocation instead of auto-allocate.

**Architecture:** Single file change in `lib/vpc.sh`. Remove all prompt/skip logic from `_setup_cloud_nat()`, add `_reserve_nat_ip()` helper that reserves a static IP named `{project_id}-nat-ip`, update `_create_nat()` to use `--nat-external-ip-pool` instead of `--auto-allocate-nat-external-ips`.

**Tech Stack:** Bash 5.0+, shellcheck, gcloud CLI, `make test` smoke suite (`NO_CLUSTER=1 DRY_RUN=true`)

---

## File Map

| File | Change |
| --- | --- |
| `lib/vpc.sh` | Rewrite `_setup_cloud_nat()`, add `_reserve_nat_ip()`, update `_create_nat()` |
| `test/run-smoke.sh` | Add T8: assert `--auto-allocate-nat-external-ips` absent from `lib/vpc.sh` |

---

### Task 1: Add smoke test T8

T8 is a static assertion — it passes once `--auto-allocate-nat-external-ips` is removed in Task 4. Fails on current code (string still present).

**Files:**
- Modify: `test/run-smoke.sh`

- [ ] **Step 1: Add T8 after T7**

Open `test/run-smoke.sh`. Locate the line with T7. Add T8 immediately after:

```bash
run_test "T7: log4j --dry-run" \
    "$ENTRY" log4j --dry-run --project test-proj

run_test_fail "T8: _create_nat must not use auto-allocate mode" \
    grep -q "auto-allocate-nat-external-ips" "$ROOT_DIR/lib/vpc.sh"

echo ""
echo "Results: $PASS passed, $FAIL failed"
```

`run_test_fail` expects non-zero exit. `grep -q` exits 0 when found → T8 reports FAIL until the string is removed.

- [ ] **Step 2: Run test to verify T8 fails (expected)**

```bash
make test 2>&1 | tail -12
```

Expected: T8 `FAIL (expected non-zero exit)`. T1–T7 all `PASS`.

- [ ] **Step 3: Commit**

```bash
git add test/run-smoke.sh
git commit -m "test: add T8 assert _create_nat drops auto-allocate mode"
```

---

### Task 2: Add `_reserve_nat_ip()` helper

**Files:**
- Modify: `lib/vpc.sh` — insert new function between `_setup_cloud_nat` and `_create_nat`

- [ ] **Step 1: Insert `_reserve_nat_ip` before `_create_nat`**

In `lib/vpc.sh`, locate line 239 (`_create_nat() {`). Insert the following block immediately before it:

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

Declare `NAT_IP_NAME=""` with the other globals at the top of the file (near line 12):

```bash
# Globals set by this module
VPC_NAME=""
SUBNET_NAME=""
IS_SHARED_VPC=""
NAT_IP_NAME=""
```

- [ ] **Step 2: Run shellcheck**

```bash
make lint 2>&1
```

Expected: no new errors from `lib/vpc.sh`.

- [ ] **Step 3: Commit**

```bash
git add lib/vpc.sh
git commit -m "feat: add _reserve_nat_ip helper for static NAT IP reservation"
```

---

### Task 3: Rewrite `_setup_cloud_nat()`

**Files:**
- Modify: `lib/vpc.sh:183-237`

- [ ] **Step 1: Replace entire `_setup_cloud_nat` body**

Replace lines 183–237 (the full `_setup_cloud_nat` function) with:

```bash
_setup_cloud_nat() {
    step "Cloud NAT Configuration"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping Cloud NAT setup"
        return 0
    fi

    local router_name="${project_id}-router"
    local nat_name="${project_id}-nat"

    if gcloud compute routers describe "$router_name" \
        --region="${region}" --project="${project_id}" &>/dev/null; then
        if gcloud compute routers nats describe "$nat_name" \
            --router="$router_name" --region="${region}" --project="${project_id}" &>/dev/null; then
            success "Cloud NAT exists: $nat_name"
            return 0
        fi
        info "Router exists, creating NAT: $nat_name"
    else
        info "Creating Cloud Router: $router_name"
        if ! run_or_dry gcloud compute routers create "$router_name" \
            --network="${VPC_NAME}" \
            --region="${region}" \
            --project="${project_id}"; then
            error "Failed to create Cloud Router"
            return 1
        fi
    fi

    _reserve_nat_ip
    _create_nat "$router_name" "$nat_name"
}
```

- [ ] **Step 2: Run shellcheck**

```bash
make lint 2>&1
```

Expected: no errors.

- [ ] **Step 3: Run smoke tests**

```bash
make test 2>&1 | tail -20
```

Expected: T1–T8 all `PASS`. T8 now passes because NO_CLUSTER guard returns 0 before any prompts or gcloud calls.

- [ ] **Step 4: Commit**

```bash
git add lib/vpc.sh
git commit -m "feat: make Cloud NAT mandatory for all envs, remove skip prompt"
```

---

### Task 4: Update `_create_nat()` — static IP pool

**Files:**
- Modify: `lib/vpc.sh` — `_create_nat` function (currently at ~line 254 after insertions)

- [ ] **Step 1: Replace `--auto-allocate-nat-external-ips` with static pool**

Locate `_create_nat()`. Replace:

```bash
        --auto-allocate-nat-external-ips \
```

With:

```bash
        --nat-external-ip-pool="${NAT_IP_NAME}" \
```

Full function after change:

```bash
_create_nat() {
    local router_name="$1"
    local nat_name="$2"
    info "Creating Cloud NAT: $nat_name"
    run_or_dry gcloud compute routers nats create "$nat_name" \
        --router="$router_name" \
        --region="${region}" \
        --project="${project_id}" \
        --nat-external-ip-pool="${NAT_IP_NAME}" \
        --nat-all-subnet-ip-ranges \
        --icmp-idle-timeout=30s \
        --tcp-established-idle-timeout=1200s \
        --tcp-transitory-idle-timeout=30s \
        --udp-idle-timeout=30s
    success "Cloud NAT created: $nat_name"
}
```

- [ ] **Step 2: Run shellcheck**

```bash
make lint 2>&1
```

Expected: no errors.

- [ ] **Step 3: Run full test suite**

```bash
make test 2>&1
```

Expected output:

```
=== GKE Cluster Creation Smoke Test ===

  T1: --help exits 0                                PASS
  T2: unknown subcommand exits non-zero             PASS
  T3: create --dry-run with all flags               PASS
  T4: update-armor --dry-run                        PASS
  T5: rollback-armor --dry-run                      PASS
  T6: fix-shared-vpc --dry-run                      PASS
  T7: log4j --dry-run                               PASS
  T8: _setup_cloud_nat NO_CLUSTER returns 0         PASS

Results: 8 passed, 0 failed
```

- [ ] **Step 4: Commit**

```bash
git add lib/vpc.sh
git commit -m "feat: use static IP pool in Cloud NAT creation, drop auto-allocate"
```
