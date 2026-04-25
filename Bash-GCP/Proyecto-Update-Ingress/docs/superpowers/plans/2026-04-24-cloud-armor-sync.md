# Cloud Armor Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After each ingress apply, automatically attach newly added backend services to the project's Cloud Armor security policy (`cve-canary`).

**Architecture:** A new `lib/cloud_armor.sh` provides `sync_cloud_armor`, which reads the list of new services written by `compare_ingress_services.sh` and uses `gcloud compute backend-services` to discover GCP backend names and attach the policy. It is called from `post_apply_validation.sh` after the LB IP is confirmed — at which point GCP backend services are provisioned and queryable.

**Tech Stack:** Bash 5, gcloud CLI, kubectl (already present in project)

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `lib/cloud_armor.sh` | Create | `sync_cloud_armor` — discover GCP backends and attach policy |
| `test/test_cloud_armor.sh` | Create | Unit tests for `sync_cloud_armor` with stubbed gcloud |
| `lib/compare_ingress_services.sh` | Modify line 42 | Write new-services list to `${TMP_PREFIX}_new_services_armor.txt` |
| `lib/post_apply_validation.sh` | Modify | Call `sync_cloud_armor` after LB IP confirmed |
| `lib/kube_compare_apply.sh` | Modify | Source `cloud_armor.sh` |

---

## Task 1: Create `lib/cloud_armor.sh` and unit tests

**Files:**
- Create: `lib/cloud_armor.sh`
- Create: `test/test_cloud_armor.sh`

---

- [ ] **Step 1: Write `test/test_cloud_armor.sh`**

```bash
#!/usr/bin/env bash
# Unit tests for lib/cloud_armor.sh

set -o nounset
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

assert_contains() {
    local label="$1" pattern="$2" output="$3"
    if printf '%s' "$output" | grep -q "$pattern"; then
        printf "PASS: %s\n" "$label"
        PASS=$((PASS + 1))
    else
        printf "FAIL: %s\n  expected pattern: '%s'\n  got: %s\n" "$label" "$pattern" "$output"
        FAIL=$((FAIL + 1))
    fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run_test <armor_file_content> <gcloud_script_body>
# Runs sync_cloud_armor in an isolated subshell with a stub gcloud.
run_test() {
    local armor_content="$1"
    local gcloud_body="$2"
    local prefix="$TMP/t_$$_$RANDOM"
    local stub_bin="$TMP/bin_$RANDOM"

    mkdir -p "$stub_bin"
    printf '%s' "$armor_content" > "${prefix}_new_services_armor.txt"
    printf '#!/usr/bin/env bash\n%s\n' "$gcloud_body" > "$stub_bin/gcloud"
    chmod +x "$stub_bin/gcloud"

    (
        export TMP_PREFIX="$prefix"
        export NAMESPACE="test-ns"
        export CLOUD_ARMOR_POLICY="cve-canary"
        export PATH="$stub_bin:$PATH"
        sleep() { :; }
        export -f sleep
        # shellcheck source=/dev/null
        . "$ROOT/lib/cloud_armor.sh"
        sync_cloud_armor
    ) 2>&1
}

echo "=== cloud_armor.sh unit tests ==="
echo ""

echo "--- 1: no armor file → skip ---"
out=$(
    (
        export TMP_PREFIX="$TMP/missing"
        export NAMESPACE="test-ns"
        export CLOUD_ARMOR_POLICY="cve-canary"
        sleep() { :; }
        export -f sleep
        # shellcheck source=/dev/null
        . "$ROOT/lib/cloud_armor.sh"
        sync_cloud_armor
    ) 2>&1
)
assert_contains "no armor file → skip" "No new services" "$out"

echo "--- 2: empty armor file → skip ---"
out=$(run_test "" 'exit 1')
assert_contains "empty armor file → skip" "No new services" "$out"

echo "--- 3: gcloud unavailable → warn ---"
out=$(
    (
        export TMP_PREFIX="$TMP/t3_$$"
        printf 'svc-a\n' > "${TMP_PREFIX}_new_services_armor.txt"
        export NAMESPACE="test-ns"
        export CLOUD_ARMOR_POLICY="cve-canary"
        export PATH=""
        sleep() { :; }
        export -f sleep
        # shellcheck source=/dev/null
        . "$ROOT/lib/cloud_armor.sh"
        sync_cloud_armor
    ) 2>&1
)
assert_contains "gcloud unavailable → warn" "gcloud not available" "$out"

echo "--- 4: policy not found → error ---"
out=$(run_test "svc-a" '
case "$*" in
  *"security-policies describe"*) exit 1 ;;
esac
exit 0
')
assert_contains "policy not found → error" "not found" "$out"

echo "--- 5: new service → attached ---"
out=$(run_test "svc-b" '
case "$*" in
  *"security-policies describe"*) exit 0 ;;
  *"backend-services list"*)      printf "k8s-be-8080--abc123\n" ;;
  *"backend-services describe"*)  printf "\n" ;;
  *"backend-services update"*)    exit 0 ;;
esac
')
assert_contains "new service → output has attached"   "attached"          "$out"
assert_contains "new service → output has backend"    "k8s-be-8080--abc123" "$out"
assert_contains "new service → output has svc name"   "svc-b"             "$out"

echo "--- 6: already attached → skip ---"
out=$(run_test "svc-c" '
case "$*" in
  *"security-policies describe"*) exit 0 ;;
  *"backend-services list"*)      printf "k8s-be-9090--def456\n" ;;
  *"backend-services describe"*)  printf "https://googleapis.com/compute/v1/projects/p/global/securityPolicies/cve-canary\n" ;;
esac
')
assert_contains "already attached → skip" "already attached" "$out"

echo "--- 7: backend not found after retries → warn ---"
out=$(run_test "svc-d" '
case "$*" in
  *"security-policies describe"*) exit 0 ;;
  *"backend-services list"*)      printf "" ;;
esac
')
assert_contains "not found → warn message"  "not found after 3 retries" "$out"
assert_contains "not found → skipped label" "skipped"                    "$out"

echo ""
printf "Results: %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

---

- [ ] **Step 2: Run tests to confirm they fail (function not defined)**

```bash
bash test/test_cloud_armor.sh
```

Expected: `FAIL` on every case — output will show `sync_cloud_armor: command not found` or similar.

---

- [ ] **Step 3: Write `lib/cloud_armor.sh`**

```bash
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
```

---

- [ ] **Step 4: Run tests to confirm all pass**

```bash
bash test/test_cloud_armor.sh
```

Expected output:
```
=== cloud_armor.sh unit tests ===

--- 1: no armor file → skip ---
PASS: no armor file → skip
--- 2: empty armor file → skip ---
PASS: empty armor file → skip
--- 3: gcloud unavailable → warn ---
PASS: gcloud unavailable → warn
--- 4: policy not found → error ---
PASS: policy not found → error
--- 5: new service → attached ---
PASS: new service → output has attached
PASS: new service → output has backend
PASS: new service → output has svc name
--- 6: already attached → skip ---
PASS: already attached → skip
--- 7: backend not found after retries → warn ---
PASS: not found → warn message
PASS: not found → skipped label

Results: 11 passed, 0 failed
```

---

- [ ] **Step 5: Syntax check**

```bash
bash -n lib/cloud_armor.sh test/test_cloud_armor.sh
```

Expected: no output (clean).

---

- [ ] **Step 6: Commit**

```bash
git add lib/cloud_armor.sh test/test_cloud_armor.sh
git commit -m "feat: add sync_cloud_armor — attach new backends to Cloud Armor policy"
```

---

## Task 2: Write new services to armor temp file in `compare_ingress_services.sh`

**Files:**
- Modify: `lib/compare_ingress_services.sh:42`

Context: Line 42 currently pipes `comm -13` directly into `wc -l`, discarding the list.
Change it to write to a temp file first, then count from the file.

---

- [ ] **Step 1: Replace line 42 in `lib/compare_ingress_services.sh`**

Find this block (lines 41-44):
```bash
    local added removed unchanged
    added=$(comm -13 "$old_list" "$new_list" | wc -l | tr -d ' ')
    removed=$(comm -23 "$old_list" "$new_list" | wc -l | tr -d ' ')
    unchanged=$(comm -12 "$old_list" "$new_list" | wc -l | tr -d ' ')
```

Replace with:
```bash
    local added removed unchanged
    comm -13 "$old_list" "$new_list" > "${TMP_PREFIX}_new_services_armor.txt"
    added=$(wc -l < "${TMP_PREFIX}_new_services_armor.txt" | tr -d ' ')
    removed=$(comm -23 "$old_list" "$new_list" | wc -l | tr -d ' ')
    unchanged=$(comm -12 "$old_list" "$new_list" | wc -l | tr -d ' ')
```

Note: `${TMP_PREFIX}_new_services_armor.txt` is intentionally NOT added to the `rm -f` at line 72 — `sync_cloud_armor` reads it later; `cleanup_temp_files` in `lib/temp.sh` handles `${TMP_PREFIX}*` on script exit.

---

- [ ] **Step 2: Syntax check**

```bash
bash -n lib/compare_ingress_services.sh
```

Expected: no output.

---

- [ ] **Step 3: Commit**

```bash
git add lib/compare_ingress_services.sh
git commit -m "feat: write new ingress services to armor temp file for Cloud Armor sync"
```

---

## Task 3: Wire `sync_cloud_armor` into the apply flow

**Files:**
- Modify: `lib/kube_compare_apply.sh` — add source line
- Modify: `lib/post_apply_validation.sh` — call `sync_cloud_armor` after LB IP confirmed

---

- [ ] **Step 1: Add source line to `lib/kube_compare_apply.sh`**

Find the existing source block (after `post_apply_validation.sh` source):
```bash
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/post_apply_validation.sh"

## The actual functions now live in their own files and are sourced above.
```

Replace with:
```bash
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/post_apply_validation.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cloud_armor.sh"

## The actual functions now live in their own files and are sourced above.
```

---

- [ ] **Step 2: Add `sync_cloud_armor` call to `lib/post_apply_validation.sh`**

Find this block (the `else` branch after the LB IP loop, ending with `fi`):
```bash
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
    fi
```

Replace with:
```bash
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
```

---

- [ ] **Step 3: Syntax check all modified files**

```bash
bash -n lib/kube_compare_apply.sh lib/post_apply_validation.sh
```

Expected: no output.

---

- [ ] **Step 4: Run smoke test**

```bash
bash test/run-smoke.sh
```

Expected: `Smoke test completed (exit 0)`

The smoke test runs with `NO_CLUSTER=1` so it exits before the apply step — it validates that sourcing and flag parsing work without errors.

---

- [ ] **Step 5: Commit**

```bash
git add lib/kube_compare_apply.sh lib/post_apply_validation.sh
git commit -m "feat: wire sync_cloud_armor into post-apply validation step"
```

---

## Acceptance Criteria Checklist

| # | Criterion | Verified by |
|---|---|---|
| 1 | New service in diff → attached to `cve-canary` | Test 5 |
| 2 | Already-attached service → skipped without error | Test 6 |
| 3 | Policy does not exist → clear error, no update attempts | Test 4 |
| 4 | Backend not found after 3 retries → warn, run continues | Test 7 |
| 5 | No new services → step silently skipped | Tests 1, 2 |
| 6 | `CLOUD_ARMOR_POLICY` env var overrides default | Test 6 (uses default; override via env works by design of `:=`) |
| 7 | `bash -n` passes on all modified files | Steps 5, 2, 3 |
