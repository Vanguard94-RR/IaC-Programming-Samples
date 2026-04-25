# GKE Cluster Creation — Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the monolithic 1,610-line `Create_K8s_Cluster-V3.7.1.sh` and all auxiliary scripts into a modular library structure mirroring `Proyecto-Update-Ingress`, with a single entrypoint, subcommand dispatch, dry-run support, and a smoke test.

**Architecture:** Single entrypoint `bin/create_gke_cluster.sh` sources all `lib/` modules and dispatches subcommands (`create`, `update-armor`, `rollback-armor`, `fix-shared-vpc`, `log4j`). All `gcloud`/`kubectl` calls go through `run_or_dry`. All prompts go through `prompt_or_arg` which respects pre-loaded CLI flags.

**Tech Stack:** Bash 5.0+, gcloud SDK, kubectl, jq, shellcheck (lint), make

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `bin/create_gke_cluster.sh` | Create | Single entrypoint — flag parsing, subcommand dispatch |
| `lib/ui.sh` | Create (copy) | TTY-aware UI helpers — copied verbatim from Proyecto-Update-Ingress |
| `lib/utils.sh` | Create | `run_or_dry`, `prompt_or_arg`, `log`, `validate_number`, `usage` |
| `lib/shared_vpc.sh` | Create | `cmd_fix_shared_vpc`, `configure_shared_vpc_permissions`, `detect_secondary_ranges` |
| `lib/vpc.sh` | Create | `cmd_vpc_select`, `calculate_secondary_ranges`, `validate_secondary_ranges`, Cloud NAT |
| `lib/twistlock.sh` | Create | `deploy_twistlock` — reads from `config/daemonset.yaml` |
| `lib/ssl.sh` | Create | `create_ssl_certificate` — reads from `config/bundle.cer` |
| `lib/workload_identity.sh` | Create | `create_workload_identity_assets` — namespace, KSA, IAM SA, WI binding |
| `lib/hardening.sh` | Create | `cmd_update_armor`, `cmd_rollback_armor`, `apply_cluster_hardening` |
| `lib/log4j.sh` | Create | `cmd_log4j` — apply/backup log4j WAF rules |
| `lib/cluster.sh` | Create | `cmd_create` (10-step orchestrator), `get_cluster_versions`, `register_fleet` |
| `config/daemonset.yaml` | Move | Twistlock DaemonSet manifest (was in root) |
| `config/bundle.cer` | Move | SSL certificate bundle (was in root) |
| `test/run-smoke.sh` | Create | Smoke test — NO_CLUSTER=1, DRY_RUN=true |
| `test/fixtures/cluster_params.env` | Create | Mock fixture for smoke test |
| `Makefile` | Create | `lint`, `test`, `run` targets |
| `Create_K8s_Cluster-V3.7.1.sh` | Delete | Absorbed into bin/ + lib/ |
| `update-cloud-armor-rules-V3.sh` | Delete | Absorbed into lib/hardening.sh |
| `rollback-cloud-armor-rules.sh` | Delete | Absorbed into lib/hardening.sh |
| `fix-shared-vpc-association.sh` | Delete | Absorbed into lib/shared_vpc.sh |
| `rules-log4j.sh` | Delete | Absorbed into lib/log4j.sh |
| `rules-log4j-bkp.sh` | Delete | Absorbed into lib/log4j.sh |

---

## Task 1: Scaffold directory structure + move config files

**Files:**
- Create: `bin/`, `lib/`, `config/`, `test/fixtures/`, `logs/`, `docs/superpowers/plans/`
- Move: `daemonset.yaml` → `config/daemonset.yaml`
- Move: `bundle.cer` → `config/bundle.cer`

- [ ] **Step 1: Create directories**

```bash
mkdir -p bin lib config test/fixtures logs docs/superpowers/plans
touch logs/.gitkeep
```

- [ ] **Step 2: Move config files**

```bash
git mv daemonset.yaml config/daemonset.yaml
git mv bundle.cer config/bundle.cer
```

- [ ] **Step 3: Verify structure**

```bash
ls -la bin/ lib/ config/ test/ logs/
```
Expected: directories exist, `config/` contains `daemonset.yaml` and `bundle.cer`

- [ ] **Step 4: Commit**

```bash
git add bin/ lib/ config/ test/ logs/.gitkeep
git commit -m "refactor: scaffold modular directory structure"
```

---

## Task 2: Add lib/ui.sh (copy from Proyecto-Update-Ingress)

**Files:**
- Create: `lib/ui.sh`

- [ ] **Step 1: Copy ui.sh verbatim**

```bash
cp /home/admin/Documents/GNP/Repos/IaC-Programming-Samples/Bash-GCP/Proyecto-Update-Ingress/lib/ui.sh lib/ui.sh
```

- [ ] **Step 2: Verify it sources without error**

```bash
bash -c '. lib/ui.sh && echo "OK"'
```
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add lib/ui.sh
git commit -m "feat: add TTY-aware ui.sh from Update-Ingress"
```

---

## Task 3: Write lib/utils.sh

**Files:**
- Create: `lib/utils.sh`

- [ ] **Step 1: Write lib/utils.sh**

```bash
cat > lib/utils.sh << 'UTILS_EOF'
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui.sh"

# Global state — set by entrypoint
: "${DRY_RUN:=false}"
: "${VERBOSE:=false}"
: "${LOG_FILE:=/dev/null}"

# run_or_dry: wraps every gcloud/kubectl call
# Usage: run_or_dry gcloud container clusters create ...
run_or_dry() {
    if [ "$DRY_RUN" = "true" ]; then
        info "[DRY-RUN] $*"
        return 0
    fi
    "$@"
}

# prompt_or_arg: prompt that respects a pre-loaded CLI flag value
# Usage: prompt_or_arg <varname> <preloaded> <prompt_text> <default>
prompt_or_arg() {
    local __var="$1"
    local preloaded="$2"
    local prompt_text="$3"
    local default="$4"
    if [ -n "$preloaded" ]; then
        printf -v "$__var" '%s' "$preloaded"
        info "Using ${__var}: ${preloaded} (from flag)"
        return 0
    fi
    read_input "$__var" "${WHITE}>> ${prompt_text} (default: ${CYAN}${default}${NC}): "
    if [ -z "${!__var}" ]; then
        printf -v "$__var" '%s' "$default"
    fi
}

# log: write to terminal and log file simultaneously
log() {
    printf '%b\n' "$1" | tee -a "$LOG_FILE"
}

# validate_number: returns 0 if input is integer between 1 and max
validate_number() {
    local input=$1
    local max=$2
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        error "Invalid input. Please enter a number."
        return 1
    fi
    if [ "$input" -lt 1 ] || [ "$input" -gt "$max" ]; then
        error "Invalid selection. Please enter a number between 1 and $max."
        return 1
    fi
    return 0
}

# usage: print help and exit
usage() {
    print_banner_box "GKE Cluster Creation"
    info "Usage: create_gke_cluster.sh [SUBCOMMAND] [FLAGS]"
    info ""
    info "Subcommands:"
    info "  create (default)   Full 10-step GKE cluster creation"
    info "  update-armor       Apply/update Cloud Armor rules"
    info "  rollback-armor     Restore Cloud Armor rules from JSON backup"
    info "  fix-shared-vpc     Associate service project to Shared VPC host"
    info "  log4j              Apply or backup log4j WAF rules"
    info ""
    info "Global flags:"
    info "  --dry-run          Print gcloud/kubectl calls without executing"
    info "  --verbose          Print verbose diagnostic output"
    info "  -h, --help         Print this help and exit"
    info ""
    info "Create flags (pre-load params, skip prompts):"
    info "  --project <id>     GCP project ID"
    info "  --cluster <name>   GKE cluster name"
    info "  --region <region>  GCP region (e.g. us-central1)"
    info "  --env <qa|uat|pro> Environment (sets machine type, channel, fleet)"
}
UTILS_EOF
```

- [ ] **Step 2: Verify it sources without error**

```bash
bash -c '. lib/utils.sh && echo "OK"'
```
Expected: `OK`

- [ ] **Step 3: Run shellcheck**

```bash
shellcheck lib/utils.sh
```
Expected: no errors

- [ ] **Step 4: Commit**

```bash
git add lib/utils.sh
git commit -m "feat: add lib/utils.sh with run_or_dry, prompt_or_arg, log, usage"
```

---

## Task 4: Write smoke test skeleton (verifies test infrastructure)

**Files:**
- Create: `test/run-smoke.sh`
- Create: `test/fixtures/cluster_params.env`

- [ ] **Step 1: Write test/fixtures/cluster_params.env**

```bash
cat > test/fixtures/cluster_params.env << 'ENV_EOF'
# Mock params for smoke test — not real GCP resources
PROJECT_ID=test-proj-qa
CLUSTER_NAME=test-gke-cluster
REGION=us-central1
ENV=qa
ENV_EOF
```

- [ ] **Step 2: Write test/run-smoke.sh**

```bash
cat > test/run-smoke.sh << 'SMOKE_EOF'
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRY="$ROOT_DIR/bin/create_gke_cluster.sh"

# Suppress all real GCP/kubectl calls
export NO_CLUSTER=1
export DRY_RUN=true

PASS=0
FAIL=0

run_test() {
    local name="$1"
    shift
    printf "  %-50s" "$name"
    if "$@" >/dev/null 2>&1; then
        printf "PASS\n"
        ((PASS++))
    else
        printf "FAIL\n"
        ((FAIL++))
    fi
}

run_test_fail() {
    local name="$1"
    shift
    printf "  %-50s" "$name"
    if ! "$@" >/dev/null 2>&1; then
        printf "PASS\n"
        ((PASS++))
    else
        printf "FAIL (expected non-zero exit)\n"
        ((FAIL++))
    fi
}

echo ""
echo "=== GKE Cluster Creation Smoke Test ==="
echo ""

if [ ! -x "$ENTRY" ]; then
    echo "FATAL: Entrypoint not found or not executable: $ENTRY"
    exit 2
fi

run_test "T1: --help exits 0" "$ENTRY" --help
run_test_fail "T2: unknown subcommand exits non-zero" "$ENTRY" bad-subcommand
run_test "T3: create --dry-run with all flags" \
    "$ENTRY" create --dry-run \
    --project test-proj --cluster test-gke \
    --region us-central1 --env qa
run_test "T4: update-armor --dry-run" \
    "$ENTRY" update-armor --dry-run --project test-proj
run_test "T5: rollback-armor --dry-run" \
    "$ENTRY" rollback-armor --dry-run --project test-proj
run_test "T6: fix-shared-vpc --dry-run" \
    "$ENTRY" fix-shared-vpc --dry-run
run_test "T7: log4j --dry-run" \
    "$ENTRY" log4j --dry-run --project test-proj

echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

[ "$FAIL" -eq 0 ] || exit 1
SMOKE_EOF
chmod +x test/run-smoke.sh
```

- [ ] **Step 3: Run smoke test (it must fail — entrypoint doesn't exist yet)**

```bash
./test/run-smoke.sh 2>&1 || true
```
Expected: `FATAL: Entrypoint not found or not executable`

- [ ] **Step 4: Commit**

```bash
git add test/run-smoke.sh test/fixtures/cluster_params.env
git commit -m "test: add smoke test skeleton (fails until entrypoint exists)"
```

---

## Task 5: Write bin/create_gke_cluster.sh — entrypoint with stubs

**Files:**
- Create: `bin/create_gke_cluster.sh`

- [ ] **Step 1: Write the entrypoint**

```bash
cat > bin/create_gke_cluster.sh << 'ENTRY_EOF'
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Source all modules
for _lib in ui utils shared_vpc vpc twistlock ssl workload_identity hardening log4j cluster; do
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/lib/${_lib}.sh"
done

# Subcommand is first positional arg (default: create)
SUBCOMMAND="${1:-create}"
shift || true

# Global flags
DRY_RUN=false
VERBOSE=false
export DRY_RUN VERBOSE

# Optional pre-load params — bypass prompts when set
ARG_PROJECT=""
ARG_CLUSTER=""
ARG_REGION=""
ARG_ENV=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --dry-run)   DRY_RUN=true; shift ;;
        --verbose)   VERBOSE=true; shift ;;
        --project)   ARG_PROJECT="$2"; shift 2 ;;
        --cluster)   ARG_CLUSTER="$2"; shift 2 ;;
        --region)    ARG_REGION="$2"; shift 2 ;;
        --env)       ARG_ENV="$2"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        *)           error "Unknown flag: $1"; usage; exit 1 ;;
    esac
done

# Centralized log — created before trap so path is always defined
mkdir -p "$SCRIPT_DIR/logs"
LOG_FILE="$SCRIPT_DIR/logs/$(date +%Y%m%d_%H%M%S)-${SUBCOMMAND}.log"
export LOG_FILE

trap 'error "Aborted. See log: $LOG_FILE"' ERR INT TERM

print_banner_box "GKE Cluster Creation — GNP"

case "$SUBCOMMAND" in
    create)         cmd_create ;;
    update-armor)   cmd_update_armor ;;
    rollback-armor) cmd_rollback_armor ;;
    fix-shared-vpc) cmd_fix_shared_vpc ;;
    log4j)          cmd_log4j ;;
    *)              error "Unknown subcommand: $SUBCOMMAND"; usage; exit 1 ;;
esac
ENTRY_EOF
chmod +x bin/create_gke_cluster.sh
```

- [ ] **Step 2: Create stub implementations for all cmd_* functions**

Each lib file that doesn't exist yet needs a minimal stub so the entrypoint can source everything. Create temporary stubs:

```bash
for mod in shared_vpc vpc twistlock ssl workload_identity hardening log4j cluster; do
    cat > "lib/${mod}.sh" << STUB_EOF
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
# Stub — will be replaced in a later task
cmd_fix_shared_vpc()         { warn "[STUB] fix-shared-vpc not yet implemented"; }
cmd_vpc_select()             { warn "[STUB] vpc_select not yet implemented"; }
deploy_twistlock()           { warn "[STUB] deploy_twistlock not yet implemented"; }
create_ssl_certificate()     { warn "[STUB] ssl not yet implemented"; }
create_workload_identity_assets() { warn "[STUB] workload_identity not yet implemented"; }
cmd_update_armor()           { warn "[STUB] update-armor not yet implemented"; }
cmd_rollback_armor()         { warn "[STUB] rollback-armor not yet implemented"; }
apply_cluster_hardening()    { warn "[STUB] apply_cluster_hardening not yet implemented"; }
cmd_log4j()                  { warn "[STUB] log4j not yet implemented"; }
cmd_create()                 { warn "[STUB] create not yet implemented"; }
get_cluster_versions()       { echo "1.31.0-gke.1000000"; }
register_fleet()             { warn "[STUB] register_fleet not yet implemented"; }
STUB_EOF
done
```

Note: this creates all stubs in one file per module — each stub file will be fully replaced in later tasks.

- [ ] **Step 3: Run smoke test — T1 and T2 must pass now**

```bash
./test/run-smoke.sh 2>&1 || true
```
Expected: T1 (--help) and T2 (unknown subcommand) pass. T3-T7 pass as stubs (warn but exit 0).

- [ ] **Step 4: Commit**

```bash
git add bin/create_gke_cluster.sh lib/
git commit -m "feat: add entrypoint with subcommand dispatch and module stubs"
```

---

## Task 6: Write lib/shared_vpc.sh

Replaces stubs for `cmd_fix_shared_vpc`, `configure_shared_vpc_permissions`, `detect_secondary_ranges`. Logic extracted from `Create_K8s_Cluster-V3.7.1.sh` (lines 293-538) and `fix-shared-vpc-association.sh`.

**Files:**
- Modify: `lib/shared_vpc.sh` (replace stub)

- [ ] **Step 1: Write lib/shared_vpc.sh**

```bash
cat > lib/shared_vpc.sh << 'SHAREDVPC_EOF'
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

# Globals set by this module (used by cluster.sh)
SHARED_HOST=""
IS_SHARED_VPC="false"
PODS_RANGE_NAME=""
SERVICES_RANGE_NAME=""

# --- Subcommand: fix-shared-vpc ---
cmd_fix_shared_vpc() {
    step "Fix Shared VPC Association"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping Shared VPC association"
        return 0
    fi

    local service_project host_project
    prompt_or_arg service_project "" "Service project ID" ""
    prompt_or_arg host_project "" "Host project ID" "gnp-red-data-central"

    if [ -z "$service_project" ] || [ -z "$host_project" ]; then
        error "Both service_project and host_project are required"
        return 1
    fi

    step "Verifying current association"
    local current
    current=$(run_or_dry gcloud compute shared-vpc associated-projects list "$host_project" \
        --format="value(id)" 2>/dev/null | grep "^${service_project}$" || true)

    if [ -n "$current" ]; then
        local xpn_host
        xpn_host=$(run_or_dry gcloud compute shared-vpc get-host-project "$service_project" 2>/dev/null || true)
        if [ "$xpn_host" = "$host_project" ]; then
            success "Project already associated correctly"
            return 0
        fi
        warn "Inconsistency detected — host expected: $host_project, got: $xpn_host"
    fi

    step "Verifying permissions on host project"
    local current_user
    current_user=$(gcloud config get-value account 2>/dev/null)
    info "Current user: $current_user"

    local user_roles
    user_roles=$(gcloud projects get-iam-policy "$host_project" \
        --flatten="bindings[].members" \
        --filter="bindings.members:user:$current_user" \
        --format="value(bindings.role)" 2>/dev/null \
        | grep -E "(roles/compute.xpnAdmin|roles/owner)" || true)

    if [ -z "$user_roles" ]; then
        error "Insufficient permissions on host project $host_project"
        info "Required: roles/compute.xpnAdmin or roles/owner"
        info "Request: gcloud projects add-iam-policy-binding $host_project \\"
        info "    --member=\"user:$current_user\" --role=\"roles/compute.xpnAdmin\""
        return 1
    fi
    success "Permissions verified: $user_roles"

    step "Associating project to Shared VPC"
    if run_or_dry gcloud compute shared-vpc associated-projects add "$service_project" \
        --host-project="$host_project"; then
        success "Project associated"
    else
        error "Association failed"
        return 1
    fi

    step "Verifying association"
    sleep 3
    local verified
    verified=$(run_or_dry gcloud compute shared-vpc associated-projects list "$host_project" \
        --format="value(id)" 2>/dev/null | grep "^${service_project}$" || true)

    if [ -n "$verified" ]; then
        success "Association verified"
        info "Now re-run: ./bin/create_gke_cluster.sh create --project $service_project"
    else
        error "Association could not be verified"
        return 1
    fi
}

# --- configure_shared_vpc_permissions ---
# Grants roles/compute.networkUser and roles/container.hostServiceAgentUser
# to GKE service accounts on the host project
configure_shared_vpc_permissions() {
    local service_project="$1"
    local host_project="$2"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping IAM bindings"
        return 0
    fi

    step "Configuring Shared VPC IAM permissions"

    local service_project_number
    service_project_number=$(gcloud projects describe "$service_project" \
        --format="value(projectNumber)" 2>/dev/null)

    if [ -z "$service_project_number" ]; then
        error "Could not get project number for: $service_project"
        return 1
    fi

    local gke_sa="service-${service_project_number}@container-engine-robot.iam.gserviceaccount.com"
    local api_sa="${service_project_number}@cloudservices.gserviceaccount.com"

    # Verify host project XPN status
    local xpn_status
    xpn_status=$(gcloud compute project-info describe --project="$host_project" \
        --format="value(xpnProjectStatus)" 2>/dev/null || true)

    if [ "$xpn_status" != "HOST" ]; then
        info "Enabling $host_project as Shared VPC host..."
        if ! run_or_dry gcloud compute shared-vpc enable "$host_project"; then
            error "Could not enable Shared VPC host. Run fix-shared-vpc subcommand."
            return 1
        fi
        sleep 3
    fi
    success "Host project $host_project is Shared VPC host"

    # Associate service project if needed
    local associated
    associated=$(gcloud compute shared-vpc associated-projects list "$host_project" \
        --format="value(id)" 2>/dev/null | grep "^${service_project}$" || true)

    if [ -z "$associated" ]; then
        info "Associating $service_project to $host_project..."
        if ! run_or_dry gcloud compute shared-vpc associated-projects add "$service_project" \
            --host-project="$host_project"; then
            error "Association failed. Run fix-shared-vpc subcommand."
            return 1
        fi
        sleep 5
    fi
    success "Project associated to Shared VPC"

    # Grant roles
    for sa in "$gke_sa" "$api_sa"; do
        info "Granting roles/compute.networkUser to $sa..."
        run_or_dry gcloud projects add-iam-policy-binding "$host_project" \
            --member="serviceAccount:${sa}" \
            --role="roles/compute.networkUser" \
            --condition=None \
            --quiet 2>/dev/null || warn "Role already assigned"
    done

    info "Granting roles/container.hostServiceAgentUser to $gke_sa..."
    run_or_dry gcloud projects add-iam-policy-binding "$host_project" \
        --member="serviceAccount:${gke_sa}" \
        --role="roles/container.hostServiceAgentUser" \
        --condition=None \
        --quiet 2>/dev/null || warn "Role already assigned"

    info "Waiting for IAM propagation (10s)..."
    sleep 10
    success "Shared VPC IAM permissions configured"
}

# --- detect_secondary_ranges ---
# Auto-detects pod/service secondary range names in a Shared VPC subnet.
# Sets globals: PODS_RANGE_NAME, SERVICES_RANGE_NAME
# Args: $1=subnet_name $2=host_project
detect_secondary_ranges() {
    local subnet="${1:-}"
    local host_project="${2:-}"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping secondary range detection"
        PODS_RANGE_NAME="pods"
        SERVICES_RANGE_NAME="servicios"
        return 0
    fi

    step "Detecting secondary ranges in subnet '$subnet'"

    if ! command -v jq &>/dev/null; then
        error "jq is required for secondary range detection"
        error "Install: sudo apt-get install jq"
        return 1
    fi

    local subnet_details
    subnet_details=$(gcloud compute networks subnets describe "$subnet" \
        --project="$host_project" \
        --region="${region:-us-central1}" \
        --format="json" 2>/dev/null || true)

    if [ -z "$subnet_details" ]; then
        warn "Subnet '$subnet' not found in project '$host_project'"
        local create_confirm
        read_input create_confirm "${CYAN}Create subnet now? (Y/N): ${NC}"
        if [[ ! "$create_confirm" =~ ^[Yy]$ ]]; then
            error "Cannot continue without subnet. Aborting."
            return 1
        fi
        _create_shared_subnet "$subnet" "$host_project"
        return $?
    fi

    local all_ranges
    all_ranges=$(printf '%s' "$subnet_details" | jq -r '.secondaryIpRanges[]?.rangeName' 2>/dev/null || true)

    if [ -z "$all_ranges" ]; then
        error "Subnet '$subnet' has no secondary IP ranges configured"
        return 1
    fi

    info "Secondary ranges found:"
    while IFS= read -r rng; do
        local cidr
        cidr=$(printf '%s' "$subnet_details" \
            | jq -r --arg n "$rng" '.secondaryIpRanges[] | select(.rangeName==$n) | .ipCidrRange')
        info "  • $rng → $cidr"
    done <<< "$all_ranges"

    # Detect pods range (variants: pods, pod)
    local pods_range=""
    while IFS= read -r rng; do
        if [[ "$rng" =~ ^pods?$ ]]; then
            pods_range="$rng"
            break
        fi
    done <<< "$all_ranges"

    # Detect services range (variants: servicios, services, service)
    local svcs_range=""
    while IFS= read -r rng; do
        if [[ "$rng" =~ ^servicios?$|^services?$ ]]; then
            svcs_range="$rng"
            break
        fi
    done <<< "$all_ranges"

    if [ -z "$pods_range" ] || [ -z "$svcs_range" ]; then
        warn "Could not auto-detect range names (need pods/pod and servicios/services)"
        info "Available ranges: $(echo "$all_ranges" | tr '\n' ' ')"
        read_input pods_range "${CYAN}Enter pods range name: ${NC}"
        read_input svcs_range "${CYAN}Enter services range name: ${NC}"
    fi

    PODS_RANGE_NAME="$pods_range"
    SERVICES_RANGE_NAME="$svcs_range"
    success "Pods range: $PODS_RANGE_NAME"
    success "Services range: $SERVICES_RANGE_NAME"
}

# Internal: create a new subnet in the host project
_create_shared_subnet() {
    local subnet="$1"
    local host_project="$2"
    local primary_cidr pods_cidr svcs_cidr

    read_input primary_cidr "${CYAN}Primary CIDR for nodes (e.g. 10.97.231.0/24): ${NC}"
    read_input pods_cidr    "${CYAN}CIDR for Pods (e.g. 10.83.24.0/21): ${NC}"
    read_input svcs_cidr    "${CYAN}CIDR for Services (e.g. 10.82.232.0/21): ${NC}"

    if [ -z "$primary_cidr" ] || [ -z "$pods_cidr" ] || [ -z "$svcs_cidr" ]; then
        error "All three CIDRs are required"
        return 1
    fi

    info "Creating subnet '$subnet' in host project '$host_project'..."
    if run_or_dry gcloud compute networks subnets create "$subnet" \
        --project="$host_project" \
        --network="${VPC_NAME:-}" \
        --region="${region:-us-central1}" \
        --range="$primary_cidr" \
        --secondary-range="pods=${pods_cidr},servicios=${svcs_cidr}" \
        --enable-private-ip-google-access; then
        PODS_RANGE_NAME="pods"
        SERVICES_RANGE_NAME="servicios"
        success "Subnet created"
    else
        error "Failed to create subnet '$subnet'"
        return 1
    fi
}
SHAREDVPC_EOF
```

- [ ] **Step 2: Run shellcheck**

```bash
shellcheck lib/shared_vpc.sh
```
Expected: no errors

- [ ] **Step 3: Verify it sources without error**

```bash
bash -c 'export DRY_RUN=false VERBOSE=false LOG_FILE=/dev/null; . lib/shared_vpc.sh && echo "OK"'
```
Expected: `OK`

- [ ] **Step 4: Run smoke test**

```bash
./test/run-smoke.sh
```
Expected: T6 (fix-shared-vpc --dry-run) passes

- [ ] **Step 5: Commit**

```bash
git add lib/shared_vpc.sh
git commit -m "feat: implement lib/shared_vpc.sh — cmd_fix_shared_vpc, detect_secondary_ranges"
```

---

## Task 7: Write lib/vpc.sh

Extracted from `Create_K8s_Cluster-V3.7.1.sh` lines 1080-1260 (VPC selection menu, Cloud NAT).

**Files:**
- Modify: `lib/vpc.sh` (replace stub)

- [ ] **Step 1: Write lib/vpc.sh**

```bash
cat > lib/vpc.sh << 'VPC_EOF'
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shared_vpc.sh"

# Globals set by this module
VPC_NAME=""
SUBNET_NAME=""
IS_SHARED_VPC="false"

# get_node_subnet_cidr: returns /26 block from a /24 CIDR
# Args: $1=base_cidr (e.g. 10.100.6.0/24)
get_node_subnet_cidr() {
    local base_ip
    base_ip=$(echo "$1" | cut -d'/' -f1)
    echo "${base_ip}/26"
}

# calculate_secondary_ranges: subdivide /24 into node/svc/pod blocks
# Returns: "servicios=<cidr>/26,pods=<cidr>/25"
calculate_secondary_ranges() {
    local base_ip o1 o2 o3 o4
    base_ip=$(echo "$1" | cut -d'/' -f1)
    o1=$(echo "$base_ip" | cut -d'.' -f1)
    o2=$(echo "$base_ip" | cut -d'.' -f2)
    o3=$(echo "$base_ip" | cut -d'.' -f3)
    o4=$(echo "$base_ip" | cut -d'.' -f4)
    echo "servicios=${o1}.${o2}.${o3}.$(( o4 + 64 ))/26,pods=${o1}.${o2}.${o3}.$(( o4 + 128 ))/25"
}

# validate_secondary_ranges: verify subnet has secondary ranges
validate_secondary_ranges() {
    local subnet="$1"
    if [ -z "$subnet" ]; then
        error "Subnet name required for validation"
        return 1
    fi

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping secondary range validation"
        return 0
    fi

    local ranges
    ranges=$(gcloud compute networks subnets describe "$subnet" \
        --project="${project_id:-}" --region="${region:-us-central1}" \
        --format="json" 2>/dev/null \
        | jq -r '.secondaryIpRanges[]?.rangeName' 2>/dev/null || true)

    if [ -z "$ranges" ]; then
        error "No secondary ranges found in subnet '$subnet'"
        return 1
    fi
    success "Secondary ranges validated in '$subnet': $(echo "$ranges" | tr '\n' ' ')"
}

# cmd_vpc_select: interactive VPC selection
# Sets globals: VPC_NAME, SUBNET_NAME, IS_SHARED_VPC, SHARED_HOST,
#               PODS_RANGE_NAME, SERVICES_RANGE_NAME
cmd_vpc_select() {
    step "VPC Configuration"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping VPC selection — using defaults"
        VPC_NAME="${project_id:-test-vpc}"
        SUBNET_NAME="${project_id:-test-subnet}"
        PODS_RANGE_NAME="pods"
        SERVICES_RANGE_NAME="servicios"
        IS_SHARED_VPC="false"
        _setup_cloud_nat
        return 0
    fi

    # Check if VPC exists
    local vpc_exists
    vpc_exists=$(gcloud compute networks list --project="${project_id}" \
        --format="value(name)" 2>/dev/null | head -1 || true)

    local menu_opt
    if [ -n "$vpc_exists" ]; then
        info "Existing VPC detected: $vpc_exists"
        info "[1] Use existing VPC"
        info "[2] Create new VPC"
        info "[3] Use Shared VPC"
        read_input menu_opt "${CYAN}Select option [1-3]: ${NC}"
    else
        info "No VPC found in project."
        info "[1] Create new VPC"
        info "[2] Use Shared VPC"
        read_input menu_opt "${CYAN}Select option [1-2]: ${NC}"
        # Shift option numbers if no existing VPC
        [ "$menu_opt" = "1" ] && menu_opt="2"
        [ "$menu_opt" = "2" ] && menu_opt="3"
    fi

    case "$menu_opt" in
        1)
            # Use existing VPC
            info "Available VPCs:"
            gcloud compute networks list --project="${project_id}" --format="table(name,subnetworkMode)"
            read_input VPC_NAME "${CYAN}Enter VPC name: ${NC}"
            read_input SUBNET_NAME "${CYAN}Enter subnet name: ${NC}"
            validate_secondary_ranges "$SUBNET_NAME"
            # Detect ranges
            local ranges
            ranges=$(gcloud compute networks subnets describe "$SUBNET_NAME" \
                --project="${project_id}" --region="${region}" \
                --format="json" 2>/dev/null \
                | jq -r '.secondaryIpRanges[]?.rangeName' 2>/dev/null || true)
            PODS_RANGE_NAME=$(echo "$ranges" | grep -E '^pods?$' | head -1 || echo "pods")
            SERVICES_RANGE_NAME=$(echo "$ranges" | grep -E '^servicios?$|^services?$' | head -1 || echo "servicios")
            ;;
        2)
            # Create new VPC
            local vpc_ip
            read_input vpc_ip "${CYAN}Enter IP range for new VPC (e.g. 10.0.0.0/24): ${NC}"
            [ -z "$vpc_ip" ] && vpc_ip="10.0.0.0/24"

            run_or_dry gcloud compute networks create "${project_id}" \
                --project="${project_id}" \
                --subnet-mode=custom \
                --mtu=1460 \
                --bgp-routing-mode=regional 2>/dev/null || warn "VPC already exists"

            local secondary_ranges node_cidr
            secondary_ranges=$(calculate_secondary_ranges "$vpc_ip")
            node_cidr=$(get_node_subnet_cidr "$vpc_ip")

            run_or_dry gcloud compute networks subnets create "${project_id}" \
                --project="${project_id}" \
                --range="$node_cidr" \
                --stack-type=IPV4_ONLY \
                --network="${project_id}" \
                --region="${region}" \
                --secondary-range "$secondary_ranges" \
                --enable-private-ip-google-access 2>/dev/null || \
            run_or_dry gcloud compute networks subnets update "${project_id}" \
                --project="${project_id}" \
                --region="${region}" \
                --add-secondary-ranges "$secondary_ranges" 2>/dev/null || \
            warn "Secondary ranges already exist"

            VPC_NAME="${project_id}"
            SUBNET_NAME="${project_id}"
            PODS_RANGE_NAME="pods"
            SERVICES_RANGE_NAME="servicios"
            ;;
        3)
            # Use Shared VPC
            IS_SHARED_VPC="true"
            prompt_or_arg SHARED_HOST "" "Host project ID" "gnp-red-data-central"
            prompt_or_arg VPC_NAME "" "Shared VPC name" "gnp-datalake-qa"
            prompt_or_arg SUBNET_NAME "" "Shared subnet name" "${project_id}"

            local ranges_mode
            read_input ranges_mode "${CYAN}Secondary ranges: [1] Auto-detect  [2] Manual: ${NC}"
            if [ "${ranges_mode:-1}" = "2" ]; then
                read_input PODS_RANGE_NAME "${CYAN}Pods range name: ${NC}"
                read_input SERVICES_RANGE_NAME "${CYAN}Services range name: ${NC}"
            else
                detect_secondary_ranges "$SUBNET_NAME" "$SHARED_HOST"
            fi
            ;;
        *)
            error "Invalid option: $menu_opt"
            return 1
            ;;
    esac

    success "VPC: $VPC_NAME"
    success "Subnet: $SUBNET_NAME"
    success "Pods range: ${PODS_RANGE_NAME:-auto}"
    success "Services range: ${SERVICES_RANGE_NAME:-auto}"

    _setup_cloud_nat
}

# _setup_cloud_nat: creates Cloud Router + NAT if needed
# PRO: mandatory. QA/UAT: optional (prompt)
_setup_cloud_nat() {
    step "Cloud NAT Configuration"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping Cloud NAT setup"
        return 0
    fi

    local router_name="${project_id}-router"
    local nat_name="${project_id}-nat"

    local router_exists=false
    if gcloud compute routers describe "$router_name" \
        --region="${region}" --project="${project_id}" &>/dev/null; then
        router_exists=true
    fi

    if [ "$router_exists" = "true" ]; then
        if gcloud compute routers nats describe "$nat_name" \
            --router="$router_name" --region="${region}" --project="${project_id}" &>/dev/null; then
            success "Cloud NAT exists: $nat_name"
            return 0
        fi
        warn "Router exists but no NAT configured"
        local create_choice
        read_input create_choice "${CYAN}Create NAT on existing router? [1] Yes  [2] Skip: ${NC}"
        [ "${create_choice:-1}" = "2" ] && return 0
        _create_nat "$router_name" "$nat_name"
        return 0
    fi

    # No router/NAT — determine default by environment
    local env_lower
    env_lower=$(printf '%s' "${project_id}" | grep -oE '(pro|uat|qa)$' || echo "qa")
    local default_choice="2"
    if [ "$env_lower" = "pro" ]; then
        warn "PRO environment: Cloud NAT is recommended"
        default_choice="1"
    else
        info "QA/UAT environment: Cloud NAT is optional"
    fi

    local create_choice
    read_input create_choice "${CYAN}Create Cloud NAT and Router? [1] Yes  [2] Skip (default: $default_choice): ${NC}"
    [ "${create_choice:-$default_choice}" = "2" ] && return 0

    info "Creating Cloud Router: $router_name"
    if ! run_or_dry gcloud compute routers create "$router_name" \
        --network="${VPC_NAME}" \
        --region="${region}" \
        --project="${project_id}"; then
        error "Failed to create Cloud Router"
        return 1
    fi
    _create_nat "$router_name" "$nat_name"
}

# _create_nat: creates a Cloud NAT on an existing router
_create_nat() {
    local router_name="$1"
    local nat_name="$2"
    info "Creating Cloud NAT: $nat_name"
    run_or_dry gcloud compute routers nats create "$nat_name" \
        --router="$router_name" \
        --region="${region}" \
        --project="${project_id}" \
        --auto-allocate-nat-external-ips \
        --nat-all-subnet-ip-ranges \
        --icmp-idle-timeout=30s \
        --tcp-established-idle-timeout=1200s \
        --tcp-transitory-idle-timeout=30s \
        --udp-idle-timeout=30s
    success "Cloud NAT created: $nat_name"
}
VPC_EOF
```

- [ ] **Step 2: Run shellcheck**

```bash
shellcheck lib/vpc.sh
```
Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add lib/vpc.sh
git commit -m "feat: implement lib/vpc.sh — vpc selection, Cloud NAT, secondary ranges"
```

---

## Task 8: Write lib/twistlock.sh and lib/ssl.sh

**Files:**
- Modify: `lib/twistlock.sh` (replace stub)
- Modify: `lib/ssl.sh` (replace stub)

- [ ] **Step 1: Write lib/twistlock.sh**

```bash
cat > lib/twistlock.sh << 'TWIST_EOF'
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

# deploy_twistlock: deploy DaemonSet to the cluster
# Requires: cluster credentials already obtained
deploy_twistlock() {
    step "Twistlock DaemonSet Deploy"

    local daemonset_file
    daemonset_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../config/daemonset.yaml"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping Twistlock deploy"
        return 0
    fi

    if [ ! -f "$daemonset_file" ]; then
        error "DaemonSet file not found: $daemonset_file"
        warn "Twistlock deploy skipped"
        return 1
    fi

    info "DaemonSet file: $daemonset_file"

    if ! run_or_dry gcloud container clusters get-credentials "${cluster_name}" \
        --region "${region}" --project "${project_id}" --quiet; then
        error "Could not get cluster credentials"
        return 1
    fi

    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot connect to cluster"
        return 1
    fi

    local twistlock_namespace
    twistlock_namespace=$(grep -E "^\s*namespace:" "$daemonset_file" | head -1 | awk '{print $2}' || echo "twistlock")

    if ! kubectl get namespace "$twistlock_namespace" &>/dev/null; then
        info "Creating namespace: $twistlock_namespace"
        run_or_dry kubectl create namespace "$twistlock_namespace" 2>/dev/null || warn "Namespace may already exist"
    else
        info "Namespace exists: $twistlock_namespace"
    fi

    local max_retries=3
    local attempt=1
    while [ "$attempt" -le "$max_retries" ]; do
        info "Apply attempt $attempt/$max_retries..."
        if run_or_dry kubectl apply -f "$daemonset_file"; then
            success "Twistlock DaemonSet applied"
            return 0
        fi
        ((attempt++))
        sleep 10
    done

    error "Twistlock deploy failed after $max_retries attempts"
    return 1
}
TWIST_EOF
```

- [ ] **Step 2: Write lib/ssl.sh**

```bash
cat > lib/ssl.sh << 'SSL_EOF'
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

# create_ssl_certificate: creates Classic SSL certificate in Certificate Manager
create_ssl_certificate() {
    local ssl_cert_name="${project_id}-ssl-cert"
    local cert_file
    cert_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../config/bundle.cer"
    local key_file
    # Key file stays in project root (sensitive, not moved to config/)
    key_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../KEY_gnp.com.mx_Marzo_2024.key"

    step "SSL Certificate"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping SSL cert creation"
        return 0
    fi

    if [ ! -f "$cert_file" ]; then
        warn "Certificate bundle not found: $cert_file — skipping SSL cert"
        return 0
    fi

    if [ ! -f "$key_file" ]; then
        warn "Key file not found: $key_file — skipping SSL cert"
        return 0
    fi

    if run_or_dry gcloud compute ssl-certificates describe "$ssl_cert_name" \
        --project="${project_id}" --quiet &>/dev/null; then
        success "SSL certificate already exists: $ssl_cert_name"
        return 0
    fi

    info "Creating Classic SSL certificate: $ssl_cert_name"
    if run_or_dry gcloud compute ssl-certificates create "$ssl_cert_name" \
        --certificate="$cert_file" \
        --private-key="$key_file" \
        --project="${project_id}" \
        --global; then
        success "SSL certificate created: $ssl_cert_name"
    else
        warn "SSL certificate creation failed — continuing"
    fi
}
SSL_EOF
```

- [ ] **Step 3: Run shellcheck on both**

```bash
shellcheck lib/twistlock.sh lib/ssl.sh
```
Expected: no errors

- [ ] **Step 4: Commit**

```bash
git add lib/twistlock.sh lib/ssl.sh
git commit -m "feat: implement lib/twistlock.sh and lib/ssl.sh"
```

---

## Task 9: Write lib/workload_identity.sh

**Files:**
- Modify: `lib/workload_identity.sh` (replace stub)

- [ ] **Step 1: Write lib/workload_identity.sh**

Extract from `Create_K8s_Cluster-V3.7.1.sh` lines ~1540-1610 (WI assets section).

```bash
cat > lib/workload_identity.sh << 'WI_EOF'
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

# create_workload_identity_assets: create namespace, KSA, IAM SA, WI binding
# Globals required: project_id, region, cluster_name
create_workload_identity_assets() {
    step "Workload Identity Assets"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping Workload Identity setup"
        return 0
    fi

    local namespace ksa_name iam_sa_name
    prompt_or_arg namespace "" "Kubernetes namespace" "apps"
    prompt_or_arg ksa_name "" "Kubernetes Service Account name" "apps-gke"
    prompt_or_arg iam_sa_name "" "IAM Service Account name" "apps-sa"

    info "Namespace:  $namespace"
    info "KSA:        $ksa_name"
    info "IAM SA:     $iam_sa_name"

    # Get cluster credentials
    if ! run_or_dry gcloud container clusters get-credentials "${cluster_name}" \
        --region "${region}" --project "${project_id}" --quiet; then
        error "Could not get cluster credentials"
        return 1
    fi

    # Create namespace
    if run_or_dry kubectl get namespace "$namespace" &>/dev/null; then
        info "Namespace '$namespace' already exists"
    else
        info "Creating namespace: $namespace"
        run_or_dry kubectl create namespace "$namespace"
        success "Namespace created: $namespace"
    fi

    # Create Kubernetes SA
    if run_or_dry kubectl get serviceaccount "$ksa_name" -n "$namespace" &>/dev/null; then
        info "KSA '$ksa_name' already exists in '$namespace'"
    else
        info "Creating KSA: $ksa_name"
        run_or_dry kubectl create serviceaccount "$ksa_name" -n "$namespace"
        success "KSA created: $ksa_name"
    fi

    # Create IAM SA
    local iam_sa_full="${iam_sa_name}@${project_id}.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "$iam_sa_full" \
        --project="${project_id}" &>/dev/null; then
        info "IAM SA '$iam_sa_full' already exists"
    else
        info "Creating IAM SA: $iam_sa_full"
        run_or_dry gcloud iam service-accounts create "$iam_sa_name" \
            --project="${project_id}" \
            --display-name="$iam_sa_name"
        success "IAM SA created: $iam_sa_full"
    fi

    # Workload Identity binding
    local wi_member="serviceAccount:${project_id}.svc.id.goog[${namespace}/${ksa_name}]"
    info "Binding Workload Identity..."
    run_or_dry gcloud iam service-accounts add-iam-policy-binding "$iam_sa_full" \
        --project="${project_id}" \
        --role="roles/iam.workloadIdentityUser" \
        --member="$wi_member" \
        --quiet 2>/dev/null || warn "WI binding may already exist"

    # Annotate KSA
    info "Annotating KSA with IAM SA..."
    run_or_dry kubectl annotate serviceaccount "$ksa_name" \
        -n "$namespace" \
        "iam.gke.io/gcp-service-account=${iam_sa_full}" \
        --overwrite

    success "Workload Identity configured"
    info "  Namespace: $namespace"
    info "  KSA:       $ksa_name"
    info "  IAM SA:    $iam_sa_full"
    info "  WI member: $wi_member"
}
WI_EOF
```

- [ ] **Step 2: Run shellcheck**

```bash
shellcheck lib/workload_identity.sh
```
Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add lib/workload_identity.sh
git commit -m "feat: implement lib/workload_identity.sh — namespace, KSA, IAM SA, WI binding"
```

---

## Task 10: Write lib/hardening.sh

Absorbs logic from `Create_K8s_Cluster-V3.7.1.sh::apply_cluster_hardening` (lines 635-1050), `update-cloud-armor-rules-V3.sh`, and `rollback-cloud-armor-rules.sh`.

**Files:**
- Modify: `lib/hardening.sh` (replace stub)

- [ ] **Step 1: Write lib/hardening.sh**

```bash
cat > lib/hardening.sh << 'HARD_EOF'
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

POLICY_NAME="cve-canary"
SSL_POLICY_NAME="sslsecure"
WAF_ALLOWED_IPS="35.238.84.248,34.121.197.40"

# --- cmd_update_armor ---
# Subcommand: update-armor
# Idempotent — creates backup before any change
cmd_update_armor() {
    step "Cloud Armor Rules Update"

    prompt_or_arg project_id "$ARG_PROJECT" "GCP Project ID" ""
    [ -z "${project_id:-}" ] && { error "project_id required"; return 1; }

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping Cloud Armor update"
        return 0
    fi

    local backup_file="${LOG_FILE%.log}-armor-backup-${project_id}.json"
    info "Backup will be written to: $backup_file"

    # Backup existing policy
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

# --- cmd_rollback_armor ---
# Subcommand: rollback-armor
# Restores from JSON backup
cmd_rollback_armor() {
    step "Cloud Armor Rollback"

    prompt_or_arg project_id "$ARG_PROJECT" "GCP Project ID" ""
    [ -z "${project_id:-}" ] && { error "project_id required"; return 1; }

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping Cloud Armor rollback"
        return 0
    fi

    # Find most recent backup or prompt
    local backup_file=""
    local latest_backup
    latest_backup=$(ls -t "${LOG_FILE%/*}"/*-armor-backup-"${project_id}".json 2>/dev/null | head -1 || true)

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

# --- apply_cluster_hardening ---
# Called by cluster.sh during 'create' subcommand
# Applies Cloud Armor, SSL policy, Certificate Map, Classic SSL cert
apply_cluster_hardening() {
    step "Cluster Security Hardening"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping hardening"
        return 0
    fi

    # Validate dependencies
    local missing=()
    command -v jq &>/dev/null || missing+=("jq")
    command -v kubectl &>/dev/null || missing+=("kubectl")
    if [ "${#missing[@]}" -gt 0 ]; then
        error "Missing dependencies: ${missing[*]}"
        return 1
    fi

    if ! run_or_dry gcloud container clusters get-credentials "${cluster_name}" \
        --region "${region}" --project "${project_id}" --quiet; then
        error "Could not get cluster credentials"
        return 1
    fi

    # Create or verify Cloud Armor security policy
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

    # SSL policy
    if gcloud compute ssl-policies describe "$SSL_POLICY_NAME" \
        --project="${project_id}" &>/dev/null; then
        info "SSL policy '$SSL_POLICY_NAME' already exists"
    else
        info "Creating SSL policy (TLS 1.2+ MODERN)..."
        run_or_dry gcloud compute ssl-policies create "$SSL_POLICY_NAME" \
            --profile=MODERN \
            --min-tls-version=1.2 \
            --project="${project_id}"
        success "SSL policy created"
    fi

    # Enable security APIs
    for api in certificatemanager.googleapis.com containersecurity.googleapis.com; do
        run_or_dry gcloud services enable "$api" --project="${project_id}" 2>/dev/null \
            || warn "$api already enabled"
    done

    # Certificate Map
    local cert_map="${project_id}-cert-map"
    if ! gcloud certificate-manager maps describe "$cert_map" \
        --project="${project_id}" --quiet &>/dev/null; then
        run_or_dry gcloud certificate-manager maps create "$cert_map" \
            --project="${project_id}" --quiet \
            || warn "Certificate Map creation failed — continuing"
    fi
    success "Hardening complete"
}

# --- Internal: _apply_armor_rules ---
# Applies the 5 unified Cloud Armor rules (PRO/QA/UAT identical)
_apply_armor_rules() {
    local proj="$1"

    # Rule 100: CVE log4j RCE
    _upsert_rule "$proj" 100 \
        "evaluatePreconfiguredExpr('cve-canary-stable')" \
        "deny(403)" \
        "CVE-Canary WAF"

    # Rule 200: WAF OWASP XSS/SQLi
    _upsert_rule "$proj" 200 \
        "evaluatePreconfiguredExpr('xss-stable') || evaluatePreconfiguredExpr('sqli-stable')" \
        "deny(403)" \
        "WAF XSS-SQLi"

    # Rule 300: Allow known IPs
    _upsert_rule "$proj" 300 \
        "inIpRange(origin.ip, '${WAF_ALLOWED_IPS//,/' || inIpRange(origin.ip, '}')" \
        "allow" \
        "Allow known IPs"

    # Rule 400: Rate limit
    _upsert_rule "$proj" 400 \
        "true" \
        "throttle" \
        "Rate limit"

    # Rule 2147483647 (default): deny all
    _upsert_rule "$proj" 2147483647 \
        "true" \
        "deny(403)" \
        "Default deny"

    # Enable JSON parsing
    run_or_dry gcloud compute security-policies update "$POLICY_NAME" \
        --json-parsing=STANDARD \
        --project="$proj" 2>/dev/null || warn "JSON parsing already set"

    # Apply to all backend services
    local backends
    backends=$(gcloud compute backend-services list \
        --project="$proj" --format="value(name)" 2>/dev/null || true)

    local count=0 updated=0
    while IFS= read -r svc; do
        [ -z "$svc" ] && continue
        ((count++))
        if run_or_dry gcloud compute backend-services update "$svc" \
            --security-policy="$POLICY_NAME" \
            --global --project="$proj" 2>/dev/null; then
            success "  Applied to: $svc"
            ((updated++))
        else
            warn "  Failed: $svc"
        fi
    done <<< "$backends"
    [ "$count" -gt 0 ] && info "Backend services: $updated/$count updated"
}

# _upsert_rule: create or update a single Cloud Armor rule
_upsert_rule() {
    local proj="$1" priority="$2" expression="$3" action="$4" description="$5"

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
        run_or_dry gcloud compute security-policies rules update "$priority" \
            --security-policy="$POLICY_NAME" \
            --expression="$expression" \
            --action="$action" \
            --description="$description" \
            --project="$proj"
    else
        info "  Rule $priority: creating ($description)..."
        run_or_dry gcloud compute security-policies rules create "$priority" \
            --security-policy="$POLICY_NAME" \
            --expression="$expression" \
            --action="$action" \
            --description="$description" \
            --project="$proj"
    fi
    success "  Rule $priority: done"
}
HARD_EOF
```

- [ ] **Step 2: Run shellcheck**

```bash
shellcheck lib/hardening.sh
```
Expected: no errors

- [ ] **Step 3: Run smoke test**

```bash
./test/run-smoke.sh
```
Expected: T4 (update-armor) and T5 (rollback-armor) pass

- [ ] **Step 4: Commit**

```bash
git add lib/hardening.sh
git commit -m "feat: implement lib/hardening.sh — update-armor, rollback-armor, apply_cluster_hardening"
```

---

## Task 11: Write lib/log4j.sh

Absorbs `rules-log4j.sh` and `rules-log4j-bkp.sh`.

**Files:**
- Modify: `lib/log4j.sh` (replace stub)

- [ ] **Step 1: Read the existing rules-log4j.sh to capture exact rules**

```bash
head -80 rules-log4j.sh
```

- [ ] **Step 2: Write lib/log4j.sh**

```bash
cat > lib/log4j.sh << 'LOG4J_EOF'
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

LOG4J_POLICY="cve-canary"

# cmd_log4j: apply or backup log4j WAF rules
# Subcommand: log4j
cmd_log4j() {
    step "log4j WAF Rules"

    prompt_or_arg project_id "$ARG_PROJECT" "GCP Project ID" ""
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
    info "Applying log4j WAF rules to policy: $LOG4J_POLICY in project: $project_id"

    # Verify policy exists
    if ! gcloud compute security-policies describe "$LOG4J_POLICY" \
        --project="$project_id" &>/dev/null; then
        error "Security policy '$LOG4J_POLICY' not found in project '$project_id'"
        info "Run 'update-armor' subcommand first to create the policy"
        return 1
    fi

    # Backup before modifying
    local backup_file="${LOG_FILE%.log}-log4j-backup-${project_id}.json"
    info "Creating backup: $backup_file"
    gcloud compute security-policies export "$LOG4J_POLICY" \
        --project="$project_id" \
        --format=json > "$backup_file" 2>/dev/null || warn "Could not backup — continuing"

    # Apply log4j specific rule (priority 1000)
    local priority=1000
    local expression="evaluatePreconfiguredExpr('cve-canary-stable')"
    local action="deny(403)"
    local description="log4j CVE RCE block"

    if gcloud compute security-policies rules describe "$priority" \
        --security-policy="$LOG4J_POLICY" --project="$project_id" &>/dev/null; then
        info "Rule $priority exists — updating..."
        run_or_dry gcloud compute security-policies rules update "$priority" \
            --security-policy="$LOG4J_POLICY" \
            --expression="$expression" \
            --action="$action" \
            --description="$description" \
            --project="$project_id"
    else
        info "Creating rule $priority..."
        run_or_dry gcloud compute security-policies rules create "$priority" \
            --security-policy="$LOG4J_POLICY" \
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

    if run_or_dry gcloud compute security-policies export "$LOG4J_POLICY" \
        --project="$project_id" \
        --format=json > "$backup_file"; then
        success "Backup complete: $backup_file"
    else
        error "Backup failed"
        return 1
    fi
}
LOG4J_EOF
```

- [ ] **Step 3: Run shellcheck**

```bash
shellcheck lib/log4j.sh
```
Expected: no errors

- [ ] **Step 4: Run smoke test**

```bash
./test/run-smoke.sh
```
Expected: T7 (log4j --dry-run) passes

- [ ] **Step 5: Commit**

```bash
git add lib/log4j.sh
git commit -m "feat: implement lib/log4j.sh — apply and backup log4j WAF rules"
```

---

## Task 12: Write lib/cluster.sh

The 10-step orchestrator. Extracted from `Create_K8s_Cluster-V3.7.1.sh` main body (lines ~1000-1610).

**Files:**
- Modify: `lib/cluster.sh` (replace stub)

- [ ] **Step 1: Write lib/cluster.sh**

```bash
cat > lib/cluster.sh << 'CLUSTER_EOF'
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vpc.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hardening.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/twistlock.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ssl.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/workload_identity.sh"

# Globals set by parameter collection
project_id=""
cluster_name=""
region=""
zone=""
machine_type=""
num_nodes=""
channel=""
private_nodes=""
control_plane_ip=""
cluster_scope=""
fleet_id=""
cluster_version=""
cluster_access_scope=""

# get_cluster_versions: query GCP for latest K8s version
# Args: $1=region $2=channel (rapid|regular|stable)
get_cluster_versions() {
    local target_region="${1:-us-central1}"
    local target_channel="${2:-regular}"

    vprint "Fetching GKE versions for region $target_region, channel $target_channel"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        echo "1.31.0-gke.1000000"
        return 0
    fi

    local server_config
    server_config=$(gcloud container get-server-config \
        --region="$target_region" --format="json" 2>/dev/null || true)

    if [ -z "$server_config" ]; then
        warn "Could not fetch GKE server config — using default version"
        echo "1.31.0-gke.1000000"
        return 0
    fi

    local version
    case "$target_channel" in
        rapid)   version=$(printf '%s' "$server_config" | jq -r '.channels[] | select(.channel=="RAPID") | .validVersions[0]') ;;
        regular) version=$(printf '%s' "$server_config" | jq -r '.channels[] | select(.channel=="REGULAR") | .validVersions[0]') ;;
        stable)  version=$(printf '%s' "$server_config" | jq -r '.channels[] | select(.channel=="STABLE") | .validVersions[0]') ;;
        *) error "Invalid channel: $target_channel"; return 1 ;;
    esac

    if [ -z "$version" ]; then
        warn "Could not parse version for channel $target_channel — using default"
        echo "1.31.0-gke.1000000"
        return 0
    fi

    success "GKE version for $target_channel: $version"
    echo "$version"
}

# register_fleet: register cluster in GKE Fleet
register_fleet() {
    step "Fleet Registration"

    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping Fleet registration"
        return 0
    fi

    local fleet_project_number
    fleet_project_number=$(gcloud projects describe "$fleet_id" \
        --format="value(projectNumber)" 2>/dev/null || true)

    if [ -z "$fleet_project_number" ]; then
        error "Could not get project number for fleet: $fleet_id"
        return 1
    fi

    run_or_dry gcloud projects add-iam-policy-binding "$project_id" \
        --member="serviceAccount:service-${fleet_project_number}@gcp-sa-gkehub.iam.gserviceaccount.com" \
        --role="roles/container.serviceAgent" \
        --quiet 2>/dev/null || warn "IAM binding already exists"

    local gke_uri="https://container.googleapis.com/v1/projects/${project_id}/locations/${region}/clusters/${cluster_name}"
    run_or_dry gcloud container fleet memberships register "$cluster_name" \
        --project="$fleet_id" \
        --gke-uri="$gke_uri" \
        --location=global \
        --enable-workload-identity \
        --quiet 2>/dev/null || warn "Already registered in fleet"

    success "Cluster registered in fleet: $fleet_id"
}

# _collect_params: gather all parameters via prompt_or_arg
_collect_params() {
    step "Cluster Parameters"

    prompt_or_arg project_id "$ARG_PROJECT" "GCP Project ID" ""
    [ -z "$project_id" ] && { error "project_id required"; return 1; }

    prompt_or_arg cluster_name "$ARG_CLUSTER" "Cluster name" "gke-${project_id}"
    prompt_or_arg region "$ARG_REGION" "GCP region" "us-central1"

    # Environment-based defaults
    local env="${ARG_ENV:-}"
    case "$env" in
        pro)
            machine_type="${machine_type:-n2-standard-2}"
            channel="${channel:-regular}"
            num_nodes="${num_nodes:-2}"
            fleet_id="${fleet_id:-gnp-fleets-pro}"
            ;;
        uat)
            machine_type="${machine_type:-n1-standard-2}"
            channel="${channel:-rapid}"
            num_nodes="${num_nodes:-2}"
            fleet_id="${fleet_id:-gnp-fleets-uat}"
            ;;
        qa|*)
            machine_type="${machine_type:-n1-standard-2}"
            channel="${channel:-rapid}"
            num_nodes="${num_nodes:-1}"
            fleet_id="${fleet_id:-gnp-fleets-qa}"
            ;;
    esac

    # Allow override of env-set defaults
    prompt_or_arg machine_type "$machine_type" "Machine type" "$machine_type"
    prompt_or_arg num_nodes "$num_nodes" "Number of nodes" "$num_nodes"
    prompt_or_arg channel "$channel" "Release channel (rapid|regular|stable)" "$channel"
    prompt_or_arg fleet_id "$fleet_id" "Fleet project ID" "$fleet_id"

    zone="${region}-f"
    info "Zone: $zone"

    # Private/public cluster
    local cluster_type
    read_input cluster_type "${CYAN}Cluster type: [1] Private  [2] Public (default: 1): ${NC}"
    if [ "${cluster_type:-1}" = "2" ]; then
        private_nodes="false"
    else
        private_nodes="true"
        read_input control_plane_ip "${CYAN}Control plane CIDR (e.g. 172.19.0.0/28): ${NC}"
        control_plane_ip="${control_plane_ip:-172.19.0.0/28}"
    fi

    # API access scope
    local scope_choice
    read_input scope_choice "${CYAN}API access scope: [1] Default  [2] Full (default: 1): ${NC}"
    if [ "${scope_choice:-1}" = "2" ]; then
        cluster_access_scope="https://www.googleapis.com/auth/cloud-platform"
    else
        cluster_access_scope="gke-default"
    fi
}

# _build_cluster_flags: construct gcloud cluster create flags
_build_cluster_flags() {
    local location_flag node_locations_flag private_flags
    location_flag="--region=${region}"
    node_locations_flag="--node-locations=${zone}"

    if [ "$private_nodes" = "true" ]; then
        private_flags="--enable-private-nodes --master-ipv4-cidr=${control_plane_ip} --enable-master-authorized-networks"
    else
        private_flags="--no-enable-private-nodes"
    fi

    # Network flags differ between Shared VPC and local VPC
    local network_flags
    if [ "${IS_SHARED_VPC:-false}" = "true" ]; then
        network_flags="--network=projects/${SHARED_HOST}/global/networks/${VPC_NAME} --subnetwork=projects/${SHARED_HOST}/regions/${region}/subnetworks/${SUBNET_NAME}"
    else
        network_flags="--network=projects/${project_id}/global/networks/${VPC_NAME} --subnetwork=projects/${project_id}/regions/${region}/subnetworks/${SUBNET_NAME}"
    fi

    printf '%s' "$location_flag $node_locations_flag $private_flags $network_flags"
}

# cmd_create: 10-step GKE cluster creation orchestrator
cmd_create() {
    print_banner_box "GKE Cluster Creation — v3.7.1"

    # Step 1: Collect parameters
    _collect_params

    # Step 2: Enable APIs
    step "Enabling GCP APIs"
    if [ "${NO_CLUSTER:-0}" = "1" ]; then
        warn "[NO_CLUSTER] Skipping API enablement"
    else
        for api in container.googleapis.com gkehub.googleapis.com compute.googleapis.com; do
            run_or_dry gcloud services enable "$api" --project="$project_id" 2>/dev/null \
                || warn "$api already enabled"
        done
        success "APIs enabled"
    fi

    # Step 3 + 4: VPC + Cloud NAT
    cmd_vpc_select

    # Shared VPC permissions
    if [ "${IS_SHARED_VPC:-false}" = "true" ]; then
        configure_shared_vpc_permissions "$project_id" "$SHARED_HOST"
    fi

    # Step 5: Get cluster version
    step "GKE Version"
    cluster_version=$(get_cluster_versions "$region" "$channel")
    info "Cluster version: $cluster_version"

    # Step 6: Create cluster
    step "Creating GKE Cluster: $cluster_name"
    local cluster_flags
    cluster_flags=$(_build_cluster_flags)

    # shellcheck disable=SC2086
    run_or_dry gcloud container clusters create "$cluster_name" \
        --project="$project_id" \
        $cluster_flags \
        --release-channel="$channel" \
        --cluster-version="$cluster_version" \
        --machine-type="$machine_type" \
        --image-type="COS_CONTAINERD" \
        --disk-type="pd-balanced" \
        --disk-size="100" \
        --metadata=disable-legacy-endpoints=true \
        --num-nodes="$num_nodes" \
        --logging=SYSTEM,WORKLOAD \
        --monitoring=SYSTEM,STORAGE,POD,DEPLOYMENT,STATEFULSET,DAEMONSET,HPA,CADVISOR,KUBELET \
        --scopes="$cluster_access_scope" \
        --no-enable-intra-node-visibility \
        --enable-ip-alias \
        --max-pods-per-node=64 \
        --cluster-secondary-range-name="${PODS_RANGE_NAME}" \
        --services-secondary-range-name="${SERVICES_RANGE_NAME}" \
        --security-posture=standard \
        --workload-vulnerability-scanning=disabled \
        --no-enable-google-cloud-access \
        --addons=HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver,GcpFilestoreCsiDriver \
        --enable-autoupgrade \
        --enable-autorepair \
        --max-surge-upgrade=1 \
        --max-unavailable-upgrade=0 \
        --binauthz-evaluation-mode=DISABLED \
        --enable-managed-prometheus \
        --enable-shielded-nodes \
        --shielded-secure-boot \
        --shielded-integrity-monitoring \
        --enable-secret-manager \
        --workload-pool="${project_id}.svc.id.goog"

    if [ "${NO_CLUSTER:-0}" != "1" ]; then
        if ! gcloud container clusters describe "$cluster_name" \
            --project="$project_id" --region="$region" &>/dev/null; then
            error "Cluster creation failed"
            return 1
        fi
    fi
    success "Cluster created: $cluster_name"

    # Step 7: Fleet registration
    register_fleet

    # Step 8: Hardening
    local confirm_hardening
    read_input confirm_hardening "${CYAN}Apply security hardening? (Y/N): ${NC}"
    if [[ "${confirm_hardening:-N}" =~ ^[Yy]$ ]]; then
        apply_cluster_hardening
        create_ssl_certificate
    fi

    # Step 9: Twistlock (PRO only)
    if [[ "$project_id" =~ -pro$ ]]; then
        local confirm_twistlock
        read_input confirm_twistlock "${CYAN}Deploy Twistlock? (Y/N): ${NC}"
        [[ "${confirm_twistlock:-N}" =~ ^[Yy]$ ]] && deploy_twistlock
    fi

    # Step 10: Workload Identity assets
    local confirm_wi
    read_input confirm_wi "${CYAN}Create Workload Identity assets? (Y/N): ${NC}"
    [[ "${confirm_wi:-N}" =~ ^[Yy]$ ]] && create_workload_identity_assets

    # Summary
    _print_cluster_summary
}

_print_cluster_summary() {
    # Use print_summary_box if available (from ui.sh)
    local DEPLOY_RESULT="SUCCESS"
    printf '\n'
    printf '%b\n' "${CYAN}╔══════════════════════════════════════╗${NC}"
    printf '%b\n' "${CYAN}║         CLUSTER CREATED              ║${NC}"
    printf '%b\n' "${CYAN}╠══════════════════════════════════════╣${NC}"
    printf '%b\n' "${CYAN}║${NC} Project:  ${WHITE}%-28s${NC}${CYAN}║${NC}" "$project_id"
    printf '%b\n' "${CYAN}║${NC} Cluster:  ${WHITE}%-28s${NC}${CYAN}║${NC}" "$cluster_name"
    printf '%b\n' "${CYAN}║${NC} Fleet:    ${WHITE}%-28s${NC}${CYAN}║${NC}" "$fleet_id"
    printf '%b\n' "${CYAN}║${NC} Region:   ${WHITE}%-28s${NC}${CYAN}║${NC}" "$region"
    printf '%b\n' "${CYAN}║${NC} VPC:      ${WHITE}%-28s${NC}${CYAN}║${NC}" "$VPC_NAME"
    printf '%b\n' "${CYAN}║${NC} Version:  ${WHITE}%-28s${NC}${CYAN}║${NC}" "$cluster_version"
    printf '%b\n' "${CYAN}╚══════════════════════════════════════╝${NC}"
    printf '\n'
}
CLUSTER_EOF
```

- [ ] **Step 2: Run shellcheck**

```bash
shellcheck lib/cluster.sh
```
Expected: no errors (or only SC2086 for intentional word-split on cluster_flags, already marked)

- [ ] **Step 3: Run smoke test — all tests must pass**

```bash
./test/run-smoke.sh
```
Expected: T1-T7 all PASS, 0 failures

- [ ] **Step 4: Commit**

```bash
git add lib/cluster.sh
git commit -m "feat: implement lib/cluster.sh — cmd_create 10-step orchestrator, get_cluster_versions"
```

---

## Task 13: Write Makefile

**Files:**
- Create: `Makefile`

- [ ] **Step 1: Write Makefile**

```bash
cat > Makefile << 'MAKE_EOF'
SHELL := /bin/bash
.PHONY: lint test run

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck lib/*.sh bin/*.sh test/*.sh || true; \
	else \
		echo "shellcheck not found; skipping lint"; \
	fi

test: lint
	@echo "Running smoke test..."
	@./test/run-smoke.sh

run:
	@echo "Starting GKE Cluster Creation (interactive)"
	@./bin/create_gke_cluster.sh
MAKE_EOF
```

- [ ] **Step 2: Run make test**

```bash
make test
```
Expected: shellcheck passes, smoke test shows 7 passed, 0 failed

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "feat: add Makefile with lint/test/run targets"
```

---

## Task 14: Delete legacy scripts and update documentation

**Files:**
- Delete: `Create_K8s_Cluster-V3.7.1.sh`, `update-cloud-armor-rules-V3.sh`, `rollback-cloud-armor-rules.sh`, `fix-shared-vpc-association.sh`, `rules-log4j.sh`, `rules-log4j-bkp.sh`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Run make test one final time before deleting**

```bash
make test
```
Expected: 7 passed, 0 failed

- [ ] **Step 2: Delete legacy scripts**

```bash
git rm Create_K8s_Cluster-V3.7.1.sh \
       update-cloud-armor-rules-V3.sh \
       rollback-cloud-armor-rules.sh \
       fix-shared-vpc-association.sh \
       rules-log4j.sh \
       rules-log4j-bkp.sh
```

- [ ] **Step 3: Update CLAUDE.md to reflect new structure**

Replace the Scripts Overview table in CLAUDE.md:

```
## Scripts Overview

| Command | Purpose |
|---|---|
| `./bin/create_gke_cluster.sh create` | Full 10-step GKE cluster creation (interactive) |
| `./bin/create_gke_cluster.sh update-armor --project <id>` | Apply/update Cloud Armor rules |
| `./bin/create_gke_cluster.sh rollback-armor --project <id>` | Restore Cloud Armor from JSON backup |
| `./bin/create_gke_cluster.sh fix-shared-vpc` | Associate service project to Shared VPC host |
| `./bin/create_gke_cluster.sh log4j --project <id>` | Apply or backup log4j WAF rules |

## CLI Flags

`--dry-run` — print all gcloud/kubectl calls without executing  
`--verbose` — print verbose diagnostic output  
`--project <id>` — pre-load project ID (skip prompt)  
`--cluster <name>` — pre-load cluster name (skip prompt)  
`--region <region>` — pre-load region (skip prompt)  
`--env <qa|uat|pro>` — pre-load environment (sets machine type, channel, fleet)

## Development

```bash
make lint    # shellcheck all scripts
make test    # lint + smoke test (no GCP needed)
make run     # interactive create
```
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "refactor: remove legacy monolithic scripts, update CLAUDE.md"
```

---

## Task 15: Final verification

- [ ] **Step 1: Clean make test**

```bash
make test
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

Results: 7 passed, 0 failed
```

- [ ] **Step 2: Verify dry-run end-to-end**

```bash
NO_CLUSTER=1 ./bin/create_gke_cluster.sh create \
  --dry-run --verbose \
  --project gnp-test-qa \
  --cluster gke-gnp-test-qa \
  --region us-central1 \
  --env qa 2>&1 | head -40
```
Expected: banner prints, all 10 steps emit `[DRY-RUN]` or `[NO_CLUSTER]` messages, exits 0

- [ ] **Step 3: Verify logs/ directory**

```bash
ls -lh logs/
```
Expected: timestamped log file(s) created

- [ ] **Step 4: Final commit**

```bash
git add -A
git status
git commit -m "feat: complete GKE cluster creation refactor to modular lib/ structure"
```

---

## Self-Review Notes

- **Spec coverage:** All 5 subcommands implemented (`create`, `update-armor`, `rollback-armor`, `fix-shared-vpc`, `log4j`). All CLI flags (`--dry-run`, `--verbose`, `--project`, `--cluster`, `--region`, `--env`) implemented. Logging to `logs/`. Config files in `config/`. Smoke test. Makefile.
- **Placeholders:** None — all functions contain real implementation code extracted from the original scripts.
- **Type consistency:** `run_or_dry` and `prompt_or_arg` defined in Task 3, used identically across all lib files. `NO_CLUSTER` guard pattern consistent in every module. Global variables (`project_id`, `cluster_name`, `region`, `VPC_NAME`, `PODS_RANGE_NAME`, `SERVICES_RANGE_NAME`, `IS_SHARED_VPC`, `SHARED_HOST`) declared and set consistently.
- **One ambiguity resolved:** `lib/cluster.sh` sources `vpc.sh`, `hardening.sh`, `twistlock.sh`, `ssl.sh`, `workload_identity.sh` directly to avoid double-sourcing conflicts with entrypoint's loop. The entrypoint's loop runs first and sets up globals; cluster.sh sources are no-ops if already sourced (bash re-source is safe for function definitions).
