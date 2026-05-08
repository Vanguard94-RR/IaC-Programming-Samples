# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Entrypoint

```bash
./bin/create_gke_cluster.sh [SUBCOMMAND] [FLAGS]
```

## Subcommands

| Command | Purpose |
|---|---|
| `create` (default) | Full 10-step GKE cluster creation (interactive) |
| `update-armor --project <id>` | Apply/update Cloud Armor rules |
| `rollback-armor --project <id>` | Restore Cloud Armor from JSON backup |
| `fix-shared-vpc` | Associate service project to Shared VPC host |
| `log4j --project <id>` | Apply or backup log4j WAF rules |

## CLI Flags

| Flag | Effect |
|---|---|
| `--dry-run` | Print all gcloud/kubectl calls without executing |
| `--verbose` | Print verbose diagnostic output |
| `--project <id>` | Pre-load project ID (skip prompt) |
| `--cluster <name>` | Pre-load cluster name (skip prompt) |
| `--region <region>` | Pre-load region (skip prompt) |
| `--env <qa\|uat\|pro>` | Pre-load environment (sets machine type, channel, fleet) |

## Development

```bash
make lint    # shellcheck all scripts
make test    # lint + smoke test (no GCP needed)
make run     # interactive create
```

Smoke test uses `NO_CLUSTER=1 DRY_RUN=true` — runs end-to-end without GCP credentials.

## Architecture

Single entrypoint `bin/create_gke_cluster.sh` sources all `lib/` modules and dispatches subcommands.

| Module | Exports |
|---|---|
| `lib/ui.sh` | TTY-aware colors, `step/info/success/warn/error`, `spinner_start/stop`, `print_banner_box`, `read_input`, `vprint` |
| `lib/utils.sh` | `run_or_dry`, `prompt_or_arg`, `log`, `validate_number`, `usage` |
| `lib/shared_vpc.sh` | `cmd_fix_shared_vpc`, `configure_shared_vpc_permissions`, `detect_secondary_ranges` |
| `lib/vpc.sh` | `cmd_vpc_select`, `calculate_secondary_ranges`, `validate_secondary_ranges`, Cloud NAT |
| `lib/hardening.sh` | `cmd_update_armor`, `cmd_rollback_armor`, `apply_cluster_hardening` |
| `lib/workload_identity.sh` | `create_workload_identity_assets` |
| `lib/twistlock.sh` | `deploy_twistlock` |
| `lib/ssl.sh` | `create_ssl_certificate` |
| `lib/log4j.sh` | `cmd_log4j` |
| `lib/cluster.sh` | `cmd_create`, `get_cluster_versions`, `register_fleet` |

### Key Patterns

- `run_or_dry`: wraps every `gcloud`/`kubectl` call — respects `--dry-run`
- `prompt_or_arg`: respects pre-loaded CLI flags, falls back to interactive prompt
- `NO_CLUSTER=1`: all modules skip GCP/kubectl calls and return early (enables offline smoke testing)
- Centralized log: `logs/<timestamp>-<subcommand>.log` — auto-created by entrypoint

### Execution Flow (`create` subcommand — 10 steps)

1. Collect parameters (`prompt_or_arg` respects `--project/--cluster/--region/--env`)
2. Enable GCP APIs
3. VPC selection: existing / new / Shared VPC → sets `VPC_NAME`, `SUBNET_NAME`, `PODS_RANGE_NAME`, `SERVICES_RANGE_NAME`
4. Cloud NAT (mandatory PRO, optional QA/UAT)
5. Fetch GKE version via `get_cluster_versions(region, channel)`
6. `gcloud container clusters create` with all flags
7. Fleet registration + Workload Identity config
8. Cloud Armor hardening + SSL policy TLS 1.2+
9. Twistlock DaemonSet (PRO only)
10. Namespace `apps`, KSA `apps-gke`, IAM SA `apps-sa`, Workload Identity binding

### Environment Conventions

| Env | Machine type | Channel | Fleet project |
|-----|-------------|---------|---------------|
| PRO | n2-standard-2 | regular | gnp-fleets-pro |
| UAT | n1-standard-2 | rapid | gnp-fleets-uat |
| QA | n1-standard-2 | rapid | gnp-fleets-qa |

Shared VPC host project: `gnp-red-data-central`

### Data Files (root)

- `cluster.csv` — cluster names for batch operations
- `data-script.csv` — `cluster_name,lb_url,backend_name,zone,project_id` (used by `update-armor`)
- `backend-list.txt` — backend service names for Cloud Armor sync

### Config Files

- `config/daemonset.yaml` — Twistlock DaemonSet manifest
- `config/bundle.cer` — SSL certificate bundle

## Dependencies

- `gcloud` (Google Cloud SDK), authenticated
- `kubectl`
- `jq`
- `bash 5.0+`

## GCP Permissions Required

**Service project:** `roles/container.admin`, `roles/compute.admin`, `roles/iam.securityAdmin`

**Host project (Shared VPC):** `roles/compute.xpnAdmin`, `roles/compute.networkAdmin`

## Hard Rules

- Always use caveman skill /caveman
- Never mention Claude in commits o as coauthor
- All commits must be in present tense and start with a verb (e.g. "Add", "Fix", "Update")
- Use `git commit -s` to sign off commits
- Follow the existing code style and patterns in the repository
- Ensure all new code is covered by tests (if applicable)
- Avoid hardcoding values; use variables or configuration files instead
- Always validate input parameters and handle errors gracefully
