# Cloud Armor Sync — Design Spec
**Date:** 2026-04-24
**Project:** Proyecto-Update-Ingress

---

## Problem

When a new backend service is added to an Ingress, it must be registered as a target on the project's Cloud Armor security policy (`cve-canary`). Today this is done manually. The script has zero Cloud Armor awareness.

**Scope:** Interactive use only. One pre-existing global policy per GCP project.

---

## Goals

1. After each ingress apply, attach newly added backend services to the Cloud Armor policy
2. Skip services already attached (idempotent)
3. Warn and skip services not yet found in GCP after retries — do not fail the run
4. Policy name configurable via `CLOUD_ARMOR_POLICY` env var (default: `cve-canary`)

---

## Out of Scope

- Creating or modifying Cloud Armor policies or rules
- Removing services from the policy when deleted from the Ingress
- BackendConfig CRD management
- Regional (non-global) backend services
- Multi-policy support

---

## Approach

**gcloud direct via description filter.**

GKE backend services have a `description` field set by the Ingress controller:
```json
{"kubernetes.io/service-name":"<namespace>/<service>","kubernetes.io/service-port":"<port>"}
```

This lets us resolve the GCP backend service name from a Kubernetes service name without touching K8s Service resources or BackendConfig CRDs.

Attachment mechanism:
```bash
gcloud compute backend-services update <gcp-backend-name> \
  --security-policy <CLOUD_ARMOR_POLICY> \
  --global
```

---

## Data Flow

```
compare_ingress_services.sh
  already computes new services via comm -13
  + writes them to ${TMP_PREFIX}_new_services_armor.txt

post_apply_validation.sh
  already waits for LB IP (LB IP = GCP backend services provisioned)
  + calls sync_cloud_armor after IP is confirmed

lib/cloud_armor.sh   ← new file
  reads new services list from temp file
  for each service:
    discovers GCP backend name via gcloud describe filter
    attaches policy via gcloud update
```

Timing is correct by design: `post_apply_validation` already blocks on LB IP assignment. By the time the IP is confirmed, GCP backend services are provisioned and queryable.

---

## Files Changed

| File | Change |
|---|---|
| `lib/cloud_armor.sh` | New — `sync_cloud_armor` function |
| `lib/compare_ingress_services.sh` | Write new services to `${TMP_PREFIX}_new_services_armor.txt` |
| `lib/post_apply_validation.sh` | Call `sync_cloud_armor` after LB IP confirmed |
| `lib/kube_compare_apply.sh` | Source `cloud_armor.sh` |

---

## Detailed Design

### `lib/cloud_armor.sh` — `sync_cloud_armor`

```
sync_cloud_armor()
  guard: new services file missing or empty → info "No new services to register" → return 0
  guard: gcloud not available → warn and return 0
  guard: gcloud compute security-policies describe $CLOUD_ARMOR_POLICY --global
         fails → error "Policy not found" → return 1

  step "Cloud Armor sync (policy: $CLOUD_ARMOR_POLICY)"

  for each service in ${TMP_PREFIX}_new_services_armor.txt:
    discover GCP backend name:
      gcloud compute backend-services list --global \
        --format="value(name)" \
        --filter="description~\"$NAMESPACE/$svc\""
    if empty → retry up to 3× with 10s sleep
    if still empty → warn "[skipped] $svc not found after 3 retries"
                     increment skipped counter → continue

    check if already attached:
      gcloud compute backend-services describe $backend_name --global \
        --format="value(securityPolicy)"
      if matches $CLOUD_ARMOR_POLICY → info "[already attached] $svc" → continue

    attach:
      gcloud compute backend-services update $backend_name \
        --security-policy $CLOUD_ARMOR_POLICY --global
      success / error per service
      increment attached counter

  success "Cloud Armor sync complete (N attached, M skipped)"
```

### Output shape

```
➜ Cloud Armor sync (policy: cve-canary)
  ● new-svc-a → k8s-be-8080--abc123  [already attached]
  + new-svc-b → k8s-be-9090--def456  [attached]
  ⚠ new-svc-c → not found after 3 retries [skipped]
✔ Cloud Armor sync complete (1 attached, 1 skipped)
```

### `lib/compare_ingress_services.sh` change

After the existing `comm -13` that computes new services, write to temp file:

```bash
comm -13 "$old_list" "$new_list" > "${TMP_PREFIX}_new_services_armor.txt"
```

The file is left for `sync_cloud_armor` to consume. Temp cleanup (`cleanup_temp_files`) already handles `${TMP_PREFIX}_*` files.

### `lib/post_apply_validation.sh` change

After the LB IP is confirmed and before the health check loop, add:

```bash
sync_cloud_armor
```

### `lib/kube_compare_apply.sh` change

Add source line alongside existing sources:

```bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cloud_armor.sh"
```

---

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `CLOUD_ARMOR_POLICY` | `cve-canary` | Name of the Cloud Armor security policy to attach to |

---

## Acceptance Criteria

1. New service in diff → attached to `cve-canary` after apply
2. Already-attached service → skipped without error
3. Policy does not exist → clear error before any update attempts
4. GCP backend not found after 3 retries → warns and skips, run continues
5. No new services → Cloud Armor step silently skipped
6. `CLOUD_ARMOR_POLICY` env var overrides default policy name
7. `bash -n` passes on all modified files
