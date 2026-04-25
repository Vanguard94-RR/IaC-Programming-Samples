# GKE Cluster Creation — Refactor Design

**Date:** 2026-04-25  
**Author:** Juan Manuel Cortes  
**Status:** Approved

## Goal

Refactor `Create_K8s_Cluster-V3.7.1.sh` and all auxiliary scripts into a modular, professional structure mirroring `Proyecto-Update-Ingress`. Preserve 100% of existing functionality. Improve code quality, testability, and maintainability.

---

## Scope

All scripts in the project are in scope:

| Current file | Disposition |
|---|---|
| `Create_K8s_Cluster-V3.7.1.sh` | Broken into `bin/create_gke_cluster.sh` + `lib/` modules |
| `update-cloud-armor-rules-V3.sh` | Absorbed into `lib/hardening.sh` + subcommand `update-armor` |
| `rollback-cloud-armor-rules.sh` | Absorbed into `lib/hardening.sh` + subcommand `rollback-armor` |
| `fix-shared-vpc-association.sh` | Absorbed into `lib/shared_vpc.sh` + subcommand `fix-shared-vpc` |
| `rules-log4j.sh` + `rules-log4j-bkp.sh` | Absorbed into `lib/log4j.sh` + subcommand `log4j` |
| `daemonset.yaml` + `bundle.cer` | Moved to `config/` |

---

## Directory Structure

```
Proyecto-GKE-Cluster-Creation-v4/
├── bin/
│   └── create_gke_cluster.sh        # Single entrypoint
├── lib/
│   ├── ui.sh                        # TTY-aware UI (reused from Update-Ingress)
│   ├── utils.sh                     # Shared utilities, logging, dry-run wrapper
│   ├── vpc.sh                       # VPC selection, Cloud NAT, secondary ranges
│   ├── shared_vpc.sh                # Shared VPC association and IAM permissions
│   ├── cluster.sh                   # GKE cluster creation orchestrator
│   ├── hardening.sh                 # Cloud Armor rules (update + rollback)
│   ├── workload_identity.sh         # Namespace, KSA, IAM SA, Workload Identity
│   ├── twistlock.sh                 # Twistlock DaemonSet deploy
│   ├── ssl.sh                       # Classic SSL certificate creation
│   └── log4j.sh                     # log4j WAF rules (apply + backup)
├── config/
│   ├── daemonset.yaml               # Twistlock manifest
│   └── bundle.cer                   # SSL certificate bundle
├── logs/                            # Auto-created at runtime
├── test/
│   ├── fixtures/
│   │   └── cluster_params.env       # Mock parameter fixture
│   └── run-smoke.sh                 # Smoke test (NO_CLUSTER=1)
├── docs/
│   └── superpowers/specs/
├── Makefile
├── CLAUDE.md
└── README.md
```

---

## Entrypoint: `bin/create_gke_cluster.sh`

Thin script. Responsibilities: source all lib modules, parse flags, dispatch subcommand.

```bash
#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Source all modules
for lib in ui utils vpc shared_vpc cluster hardening workload_identity twistlock ssl log4j; do
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/lib/${lib}.sh"
done

SUBCOMMAND="${1:-create}"
shift || true

# Global flags
DRY_RUN=false
VERBOSE=false

# Optional pre-load params (skip corresponding prompts when set)
ARG_PROJECT=""
ARG_CLUSTER=""
ARG_REGION=""
ARG_ENV=""   # qa | uat | pro

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --dry-run)        DRY_RUN=true; shift ;;
        --verbose)        VERBOSE=true; shift ;;
        --project)        ARG_PROJECT="$2"; shift 2 ;;
        --cluster)        ARG_CLUSTER="$2"; shift 2 ;;
        --region)         ARG_REGION="$2"; shift 2 ;;
        --env)            ARG_ENV="$2"; shift 2 ;;
        -h|--help)        usage; exit 0 ;;
        *)                error "Unknown flag: $1"; exit 1 ;;
    esac
done

# Centralized log
mkdir -p "$SCRIPT_DIR/logs"
LOG_FILE="$SCRIPT_DIR/logs/$(date +%Y%m%d_%H%M%S)-${SUBCOMMAND}.log"
export LOG_FILE

trap 'error "Aborted. Log: $LOG_FILE"' ERR INT TERM

case "$SUBCOMMAND" in
    create)          cmd_create ;;
    update-armor)    cmd_update_armor ;;
    rollback-armor)  cmd_rollback_armor ;;
    fix-shared-vpc)  cmd_fix_shared_vpc ;;
    log4j)           cmd_log4j ;;
    *)               error "Unknown subcommand: $SUBCOMMAND"; usage; exit 1 ;;
esac
```

### Subcommand interface

| Subcommand | Replaces | Description |
|---|---|---|
| `create` (default) | `Create_K8s_Cluster-V3.7.1.sh` | Full 10-step GKE cluster creation |
| `update-armor` | `update-cloud-armor-rules-V3.sh` | Apply/update Cloud Armor rules to a project |
| `rollback-armor` | `rollback-cloud-armor-rules.sh` | Restore Cloud Armor rules from JSON backup |
| `fix-shared-vpc` | `fix-shared-vpc-association.sh` | Associate service project to Shared VPC host |
| `log4j` | `rules-log4j.sh` + `rules-log4j-bkp.sh` | Apply or backup log4j WAF rules |

### CLI flags

| Flag | Type | Effect |
|---|---|---|
| `--dry-run` | global | Print all `gcloud`/`kubectl` calls without executing |
| `--verbose` | global | Print verbose diagnostic output |
| `--project <id>` | create, update-armor | Pre-load project ID, skip prompt |
| `--cluster <name>` | create | Pre-load cluster name, skip prompt |
| `--region <region>` | create | Pre-load region, skip prompt |
| `--env <qa\|uat\|pro>` | create | Pre-load environment, skip related prompts |
| `-h, --help` | all | Print usage and exit |

---

## Module Contracts

### `lib/ui.sh`

Reused verbatim from `Proyecto-Update-Ingress`. Provides:
- TTY-aware color variables (graceful fallback when no TTY or `NO_COLOR` set)
- `step`, `info`, `success`, `warn`, `error` — prefixed terminal output
- `spinner_start` / `spinner_stop` — animated progress indicator
- `print_banner_box`, `print_summary_box`, `print_command_box`
- `read_input <varname> [prompt]` — safe input with EOF/interrupt handling
- `vprint` — verbose-only output (respects `$VERBOSE`)

### `lib/utils.sh`

Shared primitives consumed by all other modules.

```bash
# Dry-run aware command execution
# Usage: run_or_dry gcloud container clusters create ...
run_or_dry() {
    if [ "$DRY_RUN" = "true" ]; then
        info "[DRY-RUN] $*"
        return 0
    fi
    "$@"
}

# Prompt that respects a pre-loaded value from CLI flags
# Usage: prompt_or_arg project_id "$ARG_PROJECT" "Enter project ID" "my-default"
prompt_or_arg() {
    local __var="$1" preloaded="$2" prompt_text="$3" default="$4"
    if [ -n "$preloaded" ]; then
        printf -v "$__var" '%s' "$preloaded"
        info "Using $__var: $preloaded (from flag)"
        return
    fi
    read_input "$__var" "${WHITE}>> ${prompt_text} (default: ${CYAN}${default}${NC}): "
    [ -z "${!__var}" ] && printf -v "$__var" '%s' "$default"
}

# Centralized log output: terminal + log file simultaneously
log() { printf '%b\n' "$1" | tee -a "$LOG_FILE"; }

# Input validation — reused verbatim from Update-Ingress utils.sh
# Validates input is a number between 1 and max; emits error() and returns 1 if not
validate_number() { local input=$1 max=$2; ... }

# Usage/help — defined in utils.sh, called by entrypoint on --help or unknown subcommand
usage() {
    print_banner_box "GKE Cluster Creation"
    info "Usage: create_gke_cluster.sh [SUBCOMMAND] [FLAGS]"
    info "Subcommands: create (default), update-armor, rollback-armor, fix-shared-vpc, log4j"
    info "Flags: --dry-run  --verbose  --project  --cluster  --region  --env  --help"
}
```

### `lib/vpc.sh`

Exports `cmd_vpc_select`. Handles:
- Menu: [1] use existing VPC, [2] create new VPC, [3] use Shared VPC
- If existing: validates VPC exists in project, calls `validate_secondary_ranges`
- If new: calls `calculate_secondary_ranges` to subdivide a /24, creates VPC + subnet
- If shared: prompts host project, VPC, subnet; calls `shared_vpc.sh::detect_secondary_ranges`
- Cloud NAT: creates Cloud Router + NAT if not exist (mandatory PRO, optional QA/UAT)

Sets globals: `VPC_NAME`, `SUBNET_NAME`, `PODS_RANGE_NAME`, `SERVICES_RANGE_NAME`, `IS_SHARED_VPC`.

### `lib/shared_vpc.sh`

Exports:
- `cmd_fix_shared_vpc` — entrypoint for `fix-shared-vpc` subcommand (replaces `fix-shared-vpc-association.sh`)
- `configure_shared_vpc_permissions(service_project, host_project)` — grants `roles/compute.networkUser` and `roles/container.hostServiceAgentUser` to GKE service accounts on host project
- `detect_secondary_ranges(subnet, host_project)` — auto-detects secondary range names (pods/servicios), supports naming variants, offers subnet creation if missing

### `lib/cluster.sh`

Exports `cmd_create` — the 10-step orchestrator:

1. Collect parameters via `prompt_or_arg` (respects CLI flags)
2. Enable GCP APIs (Kubernetes Engine, GKE Hub, Compute)
3. `cmd_vpc_select` (delegates to vpc.sh)
4. Cloud NAT (handled within vpc.sh)
5. `get_cluster_versions(region, channel)` — queries GCP live
6. `run_or_dry gcloud container clusters create ...`
7. Fleet registration + Workload Identity config
8. `apply_cluster_hardening` (delegates to hardening.sh)
9. `deploy_twistlock` (delegates to twistlock.sh, PRO only)
10. `create_workload_identity_assets` (delegates to workload_identity.sh)

Calls `print_summary_box` at end with all cluster details.

### `lib/hardening.sh`

Exports:
- `cmd_update_armor` — replaces `update-cloud-armor-rules-V3.sh`. Idempotent. Auto-creates backup to `logs/` before any change. Same 5 unified rules for PRO/QA/UAT.
- `cmd_rollback_armor` — replaces `rollback-cloud-armor-rules.sh`. Restores from JSON backup path.
- `apply_cluster_hardening` — called by `cluster.sh` during `create`. Applies Cloud Armor policies (PRO: 3 rules, QA/UAT: 7 rules) + SSL policy TLS 1.2+.

All `gcloud compute security-policies` calls wrapped in `run_or_dry`.  
Backup file path: `$SCRIPT_DIR/logs/<timestamp>-armor-backup-<PROJECT>.json`.

### `lib/workload_identity.sh`

Exports `create_workload_identity_assets`. Creates:
- Namespace `apps` (kubectl)
- Kubernetes SA `apps-gke` in namespace `apps` (default, overridable via prompt)
- IAM SA `apps-sa` in project (default, overridable via prompt)
- Workload Identity binding: `roles/iam.workloadIdentityUser`
- `kubectl annotate` on KSA

All calls wrapped in `run_or_dry`.

### `lib/twistlock.sh`

Exports `deploy_twistlock`. Reads manifest from `$SCRIPT_DIR/config/daemonset.yaml`. Detects namespace from file. Creates namespace if missing. Idempotent (checks existing deployment). PRO only — called conditionally by `cluster.sh`.

### `lib/ssl.sh`

Exports `create_ssl_certificate`. Reads `$SCRIPT_DIR/config/bundle.cer`. Creates Classic SSL certificate in Certificate Manager. Wrapped in `run_or_dry`.

### `lib/log4j.sh`

Exports `cmd_log4j`. Replaces `rules-log4j.sh` + `rules-log4j-bkp.sh`. Menu: [1] apply rules, [2] backup current rules. Backup written to `logs/`. All `gcloud` calls wrapped in `run_or_dry`.

---

## Error Handling

- `set -o errexit` + `set -o nounset` + `set -o pipefail` in every file
- `trap 'error "Aborted. Log: $LOG_FILE"' ERR INT TERM` in entrypoint
- Each module returns explicit exit codes with `error "..."` before `return 1`
- `gcloud`/`kubectl` stderr captured and logged; meaningful error messages emitted before abort
- No silent failures — every non-zero exit from a GCP call surfaces a human-readable message

---

## Logging

```bash
LOG_FILE="$SCRIPT_DIR/logs/$(date +%Y%m%d_%H%M%S)-${SUBCOMMAND}.log"
```

- Directory `logs/` auto-created by entrypoint
- All `log()` calls go to terminal + file simultaneously via `tee -a`
- Cloud Armor backups written to `logs/<timestamp>-armor-backup-<PROJECT>.json`
- Armor update logs written to `logs/<timestamp>-armor-update-<PROJECT>.log`

---

## Testing

### Smoke test (`test/run-smoke.sh`)

```bash
export NO_CLUSTER=1   # Suppresses gcloud container / kubectl calls
export DRY_RUN=true   # run_or_dry prints but does not execute

# Test 1: --help exits 0
"$ENTRY" --help

# Test 2: unknown subcommand exits non-zero
"$ENTRY" bad-cmd && exit 1 || true

# Test 3: create with all flags pre-loaded (no interactive prompts)
"$ENTRY" create --dry-run --project test-proj --cluster test-gke \
    --region us-central1 --env qa

# Test 4: update-armor dry-run
"$ENTRY" update-armor --dry-run --project test-proj

# Test 5: fix-shared-vpc dry-run
"$ENTRY" fix-shared-vpc --dry-run
```

`NO_CLUSTER=1` is checked inside modules that make live GCP/kubectl calls; they return early with a `warn` message. Combined with `--dry-run`, the full flow runs without any GCP dependency.

### Makefile

```makefile
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
	@echo "Run entrypoint (interactive)"
	@./bin/create_gke_cluster.sh
```

---

## Migration Notes

- Legacy scripts (`Create_K8s_Cluster-V3.7.1.sh`, auxiliaries) removed from repo root after implementation is verified
- `cluster.csv` remains in root — consumed by `log4j` subcommand (list of clusters for WAF rule application)
- `data-script.csv` remains in root — consumed by `update-armor` subcommand (format: `cluster_name,lb_url,backend_name,zone,project_id`)
- `backend-list.txt` remains in root — consumed by `hardening.sh` for backend service Cloud Armor sync
- Git history preserved (no force-push); old scripts deleted via normal commit

---

## Success Criteria

1. `make test` passes (shellcheck clean + smoke test exits 0) with no GCP credentials
2. `./bin/create_gke_cluster.sh create --dry-run --project X --cluster Y --region Z --env qa` runs end-to-end printing all 10 steps without executing any real GCP call
3. All subcommands (`update-armor`, `rollback-armor`, `fix-shared-vpc`, `log4j`) callable and functional
4. `logs/` directory populated after every run with timestamped log file
5. Shellcheck reports zero errors (warnings acceptable for intentional patterns marked with `# shellcheck disable`)
