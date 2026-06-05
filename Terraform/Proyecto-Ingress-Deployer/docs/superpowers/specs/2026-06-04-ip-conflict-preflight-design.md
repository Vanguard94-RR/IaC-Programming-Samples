# IP Conflict Pre-flight Check — Ingress Deployer

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Detect GCP forwarding rules that conflict with the ingress static IP before `terraform plan/apply`, preventing the `Error 400: IP address is in-use` LB sync failure.

**Architecture:** New `lib/network_checks.sh` sourced by `deploy.sh`. Single function `check_ip_conflicts` classifies conflicting rules by origin (manual vs GKE orphan vs another ingress) and handles each appropriately. Runs before `terraform validate` when `STATIC_IP_NAME` is set.

**Tech Stack:** Bash, gcloud CLI

---

## Trigger

Incident on `gnp-tipoevaluacion-qa`: `rh-evaluaciones-ingress` failed with `Error syncing to GCP: Invalid value for field 'resource.IPAddress': '34.54.146.145'. Specified IP address is in-use and would result in a conflict.`

Root cause: two forwarding rules occupied the IP before the GKE LB controller could complete its LB stack:
1. Manual `https` forwarding rule (port 443) — created outside GKE
2. Orphan `k8s2-fr-*` GKE rule (port 80) — from a previously incomplete LB creation

---

## Function: `check_ip_conflicts`

### Signature

```bash
check_ip_conflicts <project_id> <static_ip_name> <ingress_name>
```

### Classification Logic

For each forwarding rule found using the static IP:

| Rule name pattern | Classification | Action |
|---|---|---|
| No `k8s2-` prefix | Manual rule | Prompt to delete → exit 1 if declined |
| `k8s2-*` contains `<ingress_name>` | GKE orphan (this ingress, incomplete stack) | Prompt to delete → exit 1 if declined |
| `k8s2-*` does NOT contain `<ingress_name>` | Another ingress's GKE rule | Error + exit 1 (no delete offered) |

### CI Mode

When `CI=true`: no prompts. All conflicts → `error` log + `exit 1` with manual resolution instruction.

### Implementation

```bash
#!/usr/bin/env bash
# Requires: lib/ui.sh sourced first (ok, warn, error, info functions)

check_ip_conflicts() {
  local project_id="$1" static_ip_name="$2" ingress_name="$3"

  local ip
  ip=$(gcloud compute addresses describe "$static_ip_name" \
    --global --project="$project_id" --format="value(address)" 2>/dev/null || true)
  [[ -z "$ip" ]] && return 0

  local rules
  rules=$(gcloud compute forwarding-rules list \
    --project="$project_id" \
    --filter="IPAddress=$ip" \
    --format="value(name)" 2>/dev/null || true)
  [[ -z "$rules" ]] && return 0

  local has_conflict=false

  while IFS= read -r rule; do
    [[ -z "$rule" ]] && continue

    if [[ ! "$rule" =~ ^k8s2- ]]; then
      # Manual (non-GKE) forwarding rule
      warn "Manual forwarding rule '$rule' uses $ip — will conflict with GKE LB"
      if [[ "${CI:-false}" == "true" ]]; then
        error "CI mode: delete manually → gcloud compute forwarding-rules delete $rule --global --project=$project_id"
        has_conflict=true
      else
        read -rp "Delete manual rule '$rule'? [y/N]: " _confirm
        if [[ "${_confirm,,}" == "y" ]]; then
          gcloud compute forwarding-rules delete "$rule" --global --project="$project_id" -q
          ok "Deleted manual rule: $rule"
        else
          error "Conflict not resolved: $rule still uses $ip"
          has_conflict=true
        fi
      fi

    elif echo "$rule" | grep -q "$ingress_name"; then
      # GKE orphan rule from this ingress (incomplete LB stack)
      warn "GKE orphan forwarding rule '$rule' — incomplete LB stack from previous deploy"
      if [[ "${CI:-false}" == "true" ]]; then
        error "CI mode: delete manually → gcloud compute forwarding-rules delete $rule --global --project=$project_id"
        has_conflict=true
      else
        read -rp "Delete orphan GKE rule '$rule'? [y/N]: " _confirm
        if [[ "${_confirm,,}" == "y" ]]; then
          gcloud compute forwarding-rules delete "$rule" --global --project="$project_id" -q
          ok "Deleted orphan GKE rule: $rule"
        else
          error "Conflict not resolved: $rule still uses $ip"
          has_conflict=true
        fi
      fi

    else
      # Another ingress's GKE rule — do not auto-delete
      error "IP $ip is used by another GKE ingress: $rule — resolve manually before deploying"
      has_conflict=true
    fi

  done <<< "$rules"

  if [[ "$has_conflict" == "true" ]]; then
    error "IP conflict check failed — resolve conflicts before proceeding"
    exit 1
  fi

  ok "IP conflict check passed: $ip is available"
}
```

---

## Integration in `deploy.sh`

### 1. Source the new lib (line ~14, after cloud_armor.sh)

```bash
# shellcheck source=../lib/network_checks.sh
. "$SCRIPT_DIR/lib/network_checks.sh"
```

### 2. Call before terraform validate (~line 497)

```bash
# IP conflict pre-flight: detect forwarding rules that would block LB provisioning
if [[ -n "${STATIC_IP_NAME:-}" ]] && [[ "$ACTION" != "destroy" ]]; then
  step "IP conflict pre-flight check"
  check_ip_conflicts "$PROJECT_ID" "$STATIC_IP_NAME" "$INGRESS_NAME"
fi
```

`INGRESS_NAME` is already set at this point (line 331 in current deploy.sh).

---

## `docs/ARCHITECTURE.md` Update

Add to Section 5 (Operational Gotchas):

```markdown
### Forwarding rules in conflict → LB sync Error 400

**Symptom:** `Error syncing to GCP: error running load balancer syncing routine: ... googleapi: Error 400: Invalid value for field 'resource.IPAddress': '...'. Specified IP address is in-use and would result in a conflict.`

**Root cause:** One or more GCP forwarding rules already occupy the static IP (or a specific port on it) before the GKE LB controller can create its managed stack. Common sources:
- Manual forwarding rules created outside GKE (e.g. for quick SSL termination)
- Orphan `k8s2-fr-*` GKE rules from a previous incomplete LB creation

**Fix (automated):** `deploy.sh` detects conflicting rules during pre-flight and offers to delete them. Manual resolution:
```bash
gcloud compute forwarding-rules list \
  --project=<project> --filter="IPAddress=<ip>"
gcloud compute forwarding-rules delete <rule-name> --global --project=<project>
```

**Note:** If the conflicting rule belongs to a different GKE ingress, the deployer will not auto-delete it — coordinate with the team owning that ingress.
```

---

## Smoke Tests

Add to `test/run-smoke.sh`:

1. `network_checks.sh` sources cleanly
2. `check_ip_conflicts` called without `STATIC_IP_NAME` equivalent → no-op when IP not found

```bash
check "network_checks.sh sources cleanly" 0 \
  "bash -c 'source ${SCRIPT_DIR}/lib/ui.sh && source ${SCRIPT_DIR}/lib/network_checks.sh'"

_test_check_ip_no_conflict() {
  source "$SCRIPT_DIR/lib/ui.sh"
  source "$SCRIPT_DIR/lib/network_checks.sh"
  # Non-existent IP name → gcloud returns empty → function returns 0
  check_ip_conflicts "nonexistent-project" "nonexistent-ip" "test-ingress"
}
check "check_ip_conflicts returns 0 when IP not found" 0 \
  "_test_check_ip_no_conflict"
```

---

## What Does NOT Change

- Ephemeral IP mode (`STATIC_IP_NAME` empty) — check skipped entirely
- `ACTION=destroy` — check skipped (no LB creation)
- Terraform module, variables, outputs — unchanged
- Cloud Armor logic — unchanged
