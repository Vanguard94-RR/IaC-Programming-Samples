# GKE Cluster Creation — v4

Automated GKE cluster provisioning via a modular Bash library. Provides a single entrypoint with subcommand dispatch, dry-run support, centralized logging, and full rollback capability.

---

## Prerequisites

The following tools must be installed and available on `PATH`:

| Tool | Minimum version | Purpose |
|---|---|---|
| `gcloud` | Google Cloud SDK | GCP API calls |
| `kubectl` | — | Kubernetes resource management |
| `jq` | — | JSON parsing |
| `bash` | 5.0 | Script execution |

The operator must be authenticated to GCP before running any subcommand:

```bash
gcloud auth login
gcloud config set project PROJECT_ID
```

---

## Installation

```bash
git clone <repository-url>
cd Proyecto-GKE-Cluster-Creation-v4
chmod +x bin/create_gke_cluster.sh
```

---

## Quick Start

```bash
# Interactive cluster creation
./bin/create_gke_cluster.sh create

# Pre-loaded parameters (skips prompts)
./bin/create_gke_cluster.sh create \
  --project gnp-cfdi-qa \
  --cluster gke-gnp-cfdi-qa \
  --region us-central1 \
  --env qa

# Dry run — prints all gcloud/kubectl calls without executing
./bin/create_gke_cluster.sh create --dry-run --project gnp-cfdi-qa
```

---

## Subcommands

| Subcommand | Purpose |
|---|---|
| `create` *(default)* | Full 10-step GKE cluster creation (interactive) |
| `update-armor --project <id>` | Apply or update Cloud Armor security rules |
| `rollback-armor --project <id>` | Restore Cloud Armor policy from JSON backup |
| `fix-shared-vpc` | Associate a service project to a Shared VPC host |
| `log4j --project <id>` | Apply or back up log4j WAF rules |
| `rollback` | Delete all resources created for a given project |

---

## Global Flags

| Flag | Effect |
|---|---|
| `--dry-run` | Print all `gcloud`/`kubectl` calls without executing |
| `--verbose` | Print verbose diagnostic output |
| `--project <id>` | Pre-load project ID (skip prompt) |
| `--cluster <name>` | Pre-load cluster name (skip prompt) |
| `--region <region>` | Pre-load GCP region (skip prompt) |
| `--env <qa\|uat\|pro>` | Pre-load environment (sets machine type, release channel, fleet project) |
| `-h, --help` | Display usage information and exit |

---

## Execution Flow — `create` subcommand (10 steps)

1. Collect parameters — respects pre-loaded CLI flags
2. Enable GCP APIs (`container`, `gkehub`, `compute`)
3. VPC selection — existing VPC / new VPC / Shared VPC
4. Cloud NAT — mandatory for all environments; always uses a reserved static IP
5. Fetch GKE version dynamically via `get_cluster_versions(region, channel)`
6. Execute `gcloud container clusters create` with all configuration flags
7. Fleet registration and Workload Identity configuration
8. Security hardening — Cloud Armor policy and SSL policy (TLS 1.2+)
9. Twistlock DaemonSet deployment (PRO environment only)
10. Post-creation assets — namespace `apps`, KSA `apps-gke`, IAM SA `apps-sa`, Workload Identity binding

---

## Environment Conventions

The environment is auto-detected from the project ID suffix when `--env` is not provided.

| Environment | Machine type | Release channel | Fleet project |
|---|---|---|---|
| PRO (`*-pro`) | `n2-standard-2` | `regular` | `gnp-fleets-pro` |
| UAT (`*-uat`) | `n1-standard-2` | `rapid` | `gnp-fleets-uat` |
| QA *(default)* | `n1-standard-2` | `rapid` | `gnp-fleets-qa` |

Shared VPC host project: `gnp-red-data-central`

For full configuration values per environment, refer to `GKE-CLUSTER-SPEC.md`.

---

## Rollback

The `rollback` subcommand deletes all resources provisioned by `create` for a given project. Each deletion step is non-fatal — partial rollbacks proceed if individual resources are already absent.

```bash
./bin/create_gke_cluster.sh rollback --project gnp-cfdi-qa
```

Resources removed, in order:

1. Fleet membership
2. GKE cluster
3. IAM Service Account (`apps-sa`)
4. Cloud NAT, Cloud Router, static IP
5. Subnet and VPC network
6. Cloud Armor policy (`cve-canary`) and SSL policy (`sslsecure`)
7. SSL certificate

Confirmation requires the operator to type the project ID before any deletion proceeds.

---

## Development and Testing

```bash
make lint    # Run shellcheck on all scripts
make test    # Run lint + offline smoke test (no GCP credentials required)
make run     # Launch interactive cluster creation
```

The smoke test executes with `NO_CLUSTER=1 DRY_RUN=true` — the full flow runs without any real GCP calls.

---

## Repository Structure

```
Proyecto-GKE-Cluster-Creation-v4/
├── bin/
│   └── create_gke_cluster.sh     # Single entrypoint
├── lib/
│   ├── ui.sh                     # TTY-aware colors, spinners, output helpers
│   ├── utils.sh                  # run_or_dry, prompt_or_arg, preflight checks
│   ├── vpc.sh                    # VPC selection, Cloud NAT
│   ├── shared_vpc.sh             # Shared VPC permissions, secondary range detection
│   ├── cluster.sh                # 10-step orchestrator, get_cluster_versions
│   ├── hardening.sh              # Cloud Armor (apply/update/rollback)
│   ├── workload_identity.sh      # Namespace, KSA, IAM SA, Workload Identity binding
│   ├── twistlock.sh              # Twistlock DaemonSet deployment
│   ├── ssl.sh                    # Classic SSL certificate
│   ├── log4j.sh                  # log4j WAF rules (apply/backup)
│   └── rollback.sh               # Full resource teardown
├── config/
│   ├── daemonset.yaml            # Twistlock DaemonSet manifest
│   └── bundle.cer                # SSL certificate bundle
├── test/
│   ├── run-smoke.sh              # Smoke test runner
│   └── fixtures/
│       └── cluster_params.env    # Mock parameters for offline testing
├── logs/                         # Runtime log files (auto-created)
├── GKE-CLUSTER-SPEC.md           # Full cluster and networking specification
├── Makefile
└── README.md
```

---

## GCP Permissions Required

**Service project:**

| Role | Purpose |
|---|---|
| `roles/container.admin` | Create and manage GKE clusters |
| `roles/compute.admin` | VPC, subnets, Cloud NAT, static IPs |
| `roles/iam.securityAdmin` | Workload Identity IAM bindings |

**Host project (Shared VPC only):**

| Role | Purpose |
| --- | --- |
| `roles/compute.xpnAdmin` | Enable Shared VPC service project association |
| `roles/compute.networkAdmin` | Grant subnet access to GKE service accounts |

---

## Data Files

| File | Purpose |
| --- | --- |
| `cluster.csv` | Cluster names for batch operations |
| `data-script.csv` | `cluster_name,lb_url,backend_name,zone,project_id` — used by `update-armor` |
| `backend-list.txt` | Backend service names for Cloud Armor synchronization |
