# UX Output Refactor — Design Spec
**Date:** 2026-04-24  
**Project:** Proyecto-Update-Ingress  
**Approach:** B — Structured output refactor

---

## Problem

The script output mixes Spanish and English strings across 6 lib files, uses excessive decorative separators (`═══`), lists unchanged services individually even when nothing changed, buries the rollback command in verbose info lines, and provides no countdown during health check waits or summary at the end of execution.

**Scope:** Interactive use only. Non-interactive/CI support is a future phase.

---

## Goals

1. All output strings in English
2. Consistent use of `step/info/success/warn/error` helpers throughout
3. Conditional sections — only render when they have content
4. Rollback command in a visually distinct box
5. Health check wait with live countdown
6. Single banner at startup
7. Final deployment summary block

---

## Out of Scope

- Logic, control flow, error handling, exit codes — untouched
- `lib/healthcheck.sh`, `lib/utils.sh`, `lib/downloader.sh`, `lib/temp.sh`
- `--verbose` flag behavior (unchanged, reserved for future CI phase)
- Smoke tests in `test/run-smoke.sh` (no logic changes to validate)

> **Note:** Any existing tests that `grep` for Spanish strings will need string updates only.

---

## Files Changed

| File | Changes |
|---|---|
| `bin/update_ingress.v2.sh` | Single banner, English final string, summary box call |
| `lib/ui.sh` | Add `print_command_box` and `print_summary_box` helpers |
| `lib/kube_select.sh` | ES→EN strings, `echo -e` → `step()` in `connect_to_cluster` |
| `lib/kube_backup.sh` | ES→EN strings, rollback command box call |
| `lib/apply_new_ingress.sh` | ES→EN strings, remove `═══` decorators |
| `lib/compare_ingress_services.sh` | ES→EN strings, conditional sections, collapsed unchanged |
| `lib/post_apply_validation.sh` | ES→EN strings, health check countdown |

---

## Detailed Changes

### 1. Single Banner (`bin/update_ingress.v2.sh`)

**Before:**
```bash
print_banner_box "GNP Cloud Infrastructure Team"
print_banner_box "Kubernetes Ingress Updater — v2"
```

**After:**
```bash
print_banner_box "Kubernetes Ingress Updater — v2"
info "GNP Cloud Infrastructure Team"
```

---

### 2. `connect_to_cluster` consistency (`lib/kube_select.sh`)

**Before:**
```bash
echo -e "\n${YELLOW}Step 3: Connect to cluster${NC}"
```

**After:**
```bash
step "Step 3: Connect to cluster"
```

All other Spanish strings in `kube_select.sh` translated to English.

---

### 3. Compare section (`lib/compare_ingress_services.sh`)

**Rules:**
- Remove all `═══` separator lines
- Use `step` for section header, `success` for completion
- Sub-sections (New / Removed / Modified paths) only render when count > 0
- Unchanged: always shown as a single collapsed line
  - ≤3 services: `● Unchanged: 2  (svc-a, svc-b)`
  - >3 services: `● Unchanged: 14 services`
- kubectl diff: if output is empty, print `● No structural changes detected` instead of empty separators

**Output shape (no changes case):**
```
➜ Backend service comparison
  ✚ New:       0
  ✖ Removed:   0
  ● Unchanged: 1  (gke-gnp-bff-tesoreria-ivr)
✔ Comparison complete
```

**Output shape (with changes):**
```
➜ Backend service comparison
  ✚ New:       2
  ✖ Removed:   1
  ● Unchanged: 14 services

  New services:
    + new-svc-a
    + new-svc-b

  Removed services:
    - old-svc-x

  Modified paths:
    old-svc: /api → /api/v2

✔ Comparison complete
```

---

### 4. Rollback command box (`lib/kube_backup.sh`)

The rollback command is moved from `info()` lines into a `print_banner_box`-style highlighted block immediately after the backup succeeds.

**Output shape:**
```
✔ Rollback-ready backup saved as /path/to/file

╔══════════════════════════════════════════════════╗
║  ROLLBACK COMMAND (save this)                    ║
║  kubectl apply -f <clean_file> -n <namespace>    ║
╚══════════════════════════════════════════════════╝
```

Implementation: new `print_command_box` helper added to `lib/ui.sh` that accepts a title and a command string. Handles dynamic width based on command length.

---

### 5. Health check countdown (`lib/post_apply_validation.sh`)

Replace the static one-time message with a live countdown that updates in place using `\r`.

**Before:**
```
Waiting for all backend health checks to return 2xx/3xx. Re-checking every 60s. Press Ctrl+C to abort.
```

**After (updates every second during the wait):**
```
Next check in: 47s  [Ctrl+C to abort]
```

Implementation: replace `sleep $HEALTHCHECK_INTERVAL` with a countdown loop:
```bash
for ((i=HEALTHCHECK_INTERVAL; i>0; i--)); do
    printf "\r  Next check in: %ds  [Ctrl+C to abort]  " "$i"
    sleep 1
done
printf "\r%*s\r" 50 ""  # clear line
```

---

### 6. Final summary block (`bin/update_ingress.v2.sh`)

Rendered after `apply_new_ingress` returns successfully. Uses a new `print_summary_box` helper in `lib/ui.sh`.

**Output shape:**
```
╔══════════════════════════════════════════════════╗
║  DEPLOYMENT SUMMARY                              ║
╠══════════════════════════════════════════════════╣
║  Ticket:    CTASK0337281                         ║
║  Project:   gnp-marketplace-qa                   ║
║  Cluster:   gke-stela                            ║
║  Ingress:   stela-ingress  [gke-stela]           ║
║  Result:    ✔ UPDATED                            ║
║  Rollback:  kubectl apply -f <file> -n <ns>      ║
╚══════════════════════════════════════════════════╝
```

Variables used: `TICKET_ID`, `PROJECT_ID`, `CLUSTER_NAME`, `NAMESPACE`, `INGRESS_NAME`, `CLEAN_FILE` — all already set as globals by the time `apply_new_ingress` completes.

---

## New helpers in `lib/ui.sh`

| Function | Purpose |
|---|---|
| `print_command_box <title> <cmd>` | Renders a highlighted box for a single command string |
| `print_summary_box <key=value...>` | Renders the final deployment summary table |

Both are TTY-safe (degrade gracefully when `NO_COLOR` is set or stdout is not a TTY).

---

## Acceptance Criteria

1. `grep -r '[áéíóúñ¿¡]' lib/ bin/` returns no matches
2. `grep -r '═══' lib/ bin/` returns no matches  
3. Running with no ingress changes shows unchanged services collapsed to one line
4. Rollback command appears in a box immediately after backup
5. Health check wait shows a live countdown
6. Script ends with the summary box
7. `bash -n` passes on all modified files (syntax check)
