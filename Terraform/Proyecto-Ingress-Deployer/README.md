# Ingress Deployer — GNP Kubernetes Ingress Automation

**Status:** Production-ready | **Maintainers:** GNP Infrastructure Team | **Last Updated:** 2026-06-10

Terraform + Bash automation for deploying and managing GKE Ingress resources across GCP projects. Idempotent deployment, Cloud Armor integration, and full IaC lifecycle management — plan, apply, and destroy via a single command.

---

## Quick Start

### 1. Install Dependencies

```bash
make install
```

Detects OS (Cloud Shell / Linux / macOS) and installs terraform, gcloud, kubectl, yq. No sudo required.

### 2. Authenticate

```bash
gcloud auth login
gcloud auth application-default login
```

Both are required: `gcloud auth login` for CLI commands; `application-default login` for the Terraform GCS backend (ADC).

### 3. Configure GitLab Token

Required when the manifest URL is a GitLab API URL.

```bash
export GITLAB_TOKEN=glpat-xxxxxxxxxxxxxxxxxxxx
```

For permanent setup, store in a file and point `GITLAB_TOKEN_FILE` to it:

```bash
echo "glpat-xxxxxxxxxxxxxxxxxxxx" > ~/Documents/GNP/PersonalGitLabToken
chmod 600 ~/Documents/GNP/PersonalGitLabToken
export GITLAB_TOKEN_FILE=~/Documents/GNP/PersonalGitLabToken
```

`deploy.sh` auto-loads the file if `GITLAB_TOKEN` is not set. For non-GitLab URLs (HTTPS, local path) no token is needed.

### 4. Initialize State Backend

```bash
export PROJECT_ID=gnp-plus-qa
make backend
```

Creates `gs://<project>-tf-state` bucket with versioning enabled.

### 5. Deploy

```bash
make deploy
```

Interactive: prompts for ticket ID, project, manifest URL, and action. Selects cluster, reviews plan, confirms apply.

---

## Requirements

### Tools

| Tool | Version | Cloud Shell | Auto-Install |
|------|---------|-------------|--------------|
| terraform | ≥ 1.0 | ✓ | ✓ |
| gcloud SDK | latest | ✓ | ✓ |
| kubectl | latest | ✓ | ✓ |
| yq | ≥ 4.0 | — | ✓ |
| curl, tar | any | ✓ | ✓ usually present |

No sudo required — all tools install to `~/.gnp/` or user home.

### GCP Permissions

| Role | Purpose |
|------|---------|
| `roles/compute.networkAdmin` | Static IPs, forwarding rules |
| `roles/container.developer` | Deploy manifests to GKE |
| `roles/storage.admin` | GCS state bucket |

---

## Documentation

- **[Architecture, Features & Operations Guide](docs/ARCHITECTURE.md)** — component diagrams, IaC flow, deploy commands, environment variables, troubleshooting, FAQ
- **[Namespace Migration Runbook](docs/runbooks/namespace-migration.md)** — delete-and-redeploy pattern for namespace changes with a shared static IP

---

*Internal use only — GNP Infrastructure Team*
