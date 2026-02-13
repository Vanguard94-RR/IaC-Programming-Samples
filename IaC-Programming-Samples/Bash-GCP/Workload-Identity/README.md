# Workload Identity Manager

Configure GCP Workload Identity between GCP Service Accounts and Kubernetes Service Accounts.

## Quick Start

```bash
# Install/verify dependencies
make install

# Setup workload identity
make setup PROJECT=gnp-app-qa GCP_SA=sa-backend KSA=ka-backend NAMESPACE=apps

# Verify configuration
make verify PROJECT=gnp-app-qa GCP_SA=sa-backend KSA=ka-backend NAMESPACE=apps
```

## What is Workload Identity?

Workload Identity allows Kubernetes pods to authenticate as GCP service accounts without using service account keys. This tool automates the configuration:

1. **Create KSA** in target namespace
2. **Add IAM binding** between GCP SA and KSA
3. **Annotate KSA** so pods can access GCP services

## Commands

| Command | Description |
|---------|-------------|
| `make install` | Verify kubectl, gcloud, python3 are installed |
| `make setup` | Configure workload identity |
| `make verify` | Check workload identity configuration |
| `make cleanup` | Remove workload identity binding |
| `make list` | Show service accounts |
| `make batch` | Process multiple bindings from CSV |
| `make test` | Run setup in dry-run mode |
| `make logs` | View operation logs |
| `make clean` | Remove logs |

## Usage Examples

### Basic Setup

```bash
make setup PROJECT=gnp-app-qa GCP_SA=sa-backend KSA=ka-backend NAMESPACE=apps
```

### Namespace Migration

Move KSA from `default` to `apps` namespace:

```bash
make setup PROJECT=gnp-app-qa GCP_SA=sa-backend KSA=ka-backend NAMESPACE=default TARGET_NS=apps
```

### Dry-Run Mode

Test without making changes:

```bash
make test PROJECT=gnp-app-qa GCP_SA=sa-backend KSA=ka-backend NAMESPACE=apps

# Or with DRY_RUN flag
make setup PROJECT=gnp-app-qa GCP_SA=sa-backend KSA=ka-backend NAMESPACE=apps DRY_RUN=1
```

### Batch Processing

Process multiple bindings from CSV file:

```bash
make batch CSV_FILE=bindings.csv
make batch CSV_FILE=bindings.csv ACTION=verify
```

CSV format:
```csv
project,gcp_sa,ksa,namespace,target_namespace
gnp-app-qa,sa-backend,ka-backend,apps,
gnp-app-qa,sa-frontend,ka-frontend,default,apps
```

## Direct CLI Usage

```bash
# Setup
python3 workload-identity.py setup -p gnp-app-qa -g sa-backend -k ka-backend -n apps

# Setup with migration
python3 workload-identity.py setup -p gnp-app-qa -g sa-backend -k ka-backend -n default -t apps

# Verify
python3 workload-identity.py verify -p gnp-app-qa -g sa-backend -k ka-backend -n apps

# Cleanup
python3 workload-identity.py cleanup -p gnp-app-qa -g sa-backend -k ka-backend -n apps

# List
python3 workload-identity.py list -p gnp-app-qa

# Batch
python3 workload-identity.py batch -f bindings.csv -a setup

# Dry-run
python3 workload-identity.py --dry-run setup -p gnp-app-qa -g sa-backend -k ka-backend -n apps
```

## Parameters

| Parameter | Short | Description |
|-----------|-------|-------------|
| `--project` | `-p` | GCP Project ID |
| `--gcp-sa` | `-g` | GCP Service Account (name or full email) |
| `--ksa` | `-k` | Kubernetes Service Account name |
| `--namespace` | `-n` | Kubernetes namespace |
| `--target-namespace` | `-t` | Target namespace for migration |
| `--dry-run` | | Show actions without executing |
| `--no-log` | | Disable file logging |

## Prerequisites

- `kubectl` configured for your GKE cluster
- `gcloud` CLI authenticated
- `python3` (3.8+)

## References

- [GCP Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
