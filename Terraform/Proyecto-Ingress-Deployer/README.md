# Ingress Deployer — GNP Kubernetes Ingress Automation

**Status:** Production-ready | **Maintainers:** GNP Infrastructure Team  
**Last Updated:** 2026-06-03 | **Version:** 1.0.0

Terraform automation for managing Google Cloud Load Balancer Ingress resources on GKE with idempotent deployment, multi-environment support, and comprehensive disaster recovery.

---

## Quick Start

### 1. Install Dependencies (1 minute)

```bash
git clone <repo>
cd Proyecto-Ingress-Deployer
make install
```

**What happens:**
- Detects OS (Cloud Shell / Linux / macOS)
- Installs terraform, gcloud, kubectl, yq if missing
- Sets up `~/.gnp/ingress/` config directory
- Patches `~/.bashrc` with tool paths

### 2. Authenticate

```bash
gcloud auth login
gcloud auth application-default login  # For Application Default Credentials
```

### 3. Initialize Backend

```bash
export PROJECT_ID=gnp-plus-qa
make backend
```

Creates GCS state bucket + enables versioning for state protection.

### 4. Deploy Ingress

```bash
make deploy
```

Interactive workflow: choose cluster, review plan, confirm apply.

---

## Requirements

### Environment

| Item | Cloud Shell | Local Linux | Local macOS |
|------|---|---|---|
| terraform >= 1.0 | ✓ pre-installed | auto-install | auto-install |
| gcloud SDK | ✓ pre-installed | auto-install | auto-install |
| kubectl | ✓ pre-installed | auto-install | auto-install |
| yq >= 4.0 | auto-install | auto-install | auto-install |
| curl, tar | ✓ pre-installed | ✓ usually present | ✓ usually present |

**No sudo required:** All tools install to `~/.gnp/` or user home directory.

### GCP Permissions

Minimum roles for your GCP service account or user:

- **Compute**: `roles/compute.networkAdmin` (create static IPs, forwarding rules)
- **Kubernetes**: `roles/container.developer` (deploy manifests, port-forward)
- **Storage**: `roles/storage.admin` (GCS state bucket)

```bash
# Check your current permissions
gcloud projects get-iam-policy $PROJECT_ID --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:$(gcloud config get-value account)"
```

### GCP Resources

Must exist before deployment:

- **GKE Cluster**: Must be running in the target project
- **Network**: Cluster must be in a configured VPC
- **(Optional) Static IP**: If using named static IP for ingress (specify in ingress YAML)
- **(Optional) SSL Certificate**: Must be pre-created in target project

### GitLab (for manifest downloads)

If ingress YAML is in GitLab, provide a Personal Access Token:

```bash
export GITLAB_TOKEN_FILE=~/.gnp/tokens/gitlab.token  # or
export GITLAB_TOKEN=glpat-xxxxx
```

---

## Architecture

### Data Flow

```
environments/
  └── <project>.tfvars          ← Cluster, namespace, IP name

manifests/
  └── <project>/
      ├── ingress.yaml          ← Downloaded from GitLab / URL
      └── frontendconfig.yaml   ← Generated or downloaded

scripts/
  ├── setup.sh                  ← Dependency installer
  ├── deploy.sh                 ← Main orchestrator
  └── init-backend.sh           ← GCS backend setup

terraform/
  ├── main.tf                   ← Provider + module definitions
  └── modules/ingress/
      ├── main.tf               ← Ingress, static IP, FrontendConfig
      ├── variables.tf
      └── outputs.tf

GCS Bucket
  └── ingress/
      └── terraform.tfstate     ← Remote state (versioned)
```

### Workflow

```
1. setup.sh
   └─ Check/install terraform, gcloud, kubectl, yq
   └─ Patch ~/.bashrc
   └─ Create ~/.gnp/ingress/ config

2. deploy.sh (interactive)
   ├─ Validate gcloud authentication
   ├─ Download ingress YAML from URL/GitLab
   ├─ Prompt: ticket ID, project, cluster, namespace
   ├─ Query GCP for cluster, SSL cert, static IP
   ├─ Generate tfvars
   │
3. init-backend.sh
   └─ Create GCS bucket (if missing)
   └─ Enable versioning
   └─ Run terraform init

4. Terraform (plan/apply)
   ├─ Import pre-existing resources (namespace, static IP, ingress)
   ├─ Validate configuration
   ├─ Show plan (review before apply)
   └─ Apply: create/update ingress + LB resources

5. Post-apply
   ├─ Wait for ingress IP assignment
   ├─ Upload artifacts to GCS (backup, logs, plan)
   └─ Attach Cloud Armor if configured
```

### State Management

**State Bucket:** `gs://<project>-tf-state/ingress/terraform.tfstate`

**Versioning:** Enabled automatically → can restore any past state version.

**Lock File:** `.terraform/` directory prevents concurrent operations.

**Backup:** Before each apply, ingress YAML backed up to `~/.gnp/ingress/backups/` and GCS.

---

## Operations Guide

### Basic Deployment

```bash
# Plan (review changes without applying)
ACTION=plan make deploy

# Apply (create/update ingress)
ACTION=apply make deploy

# Destroy (delete ingress + static IP, keep namespace)
ACTION=destroy make deploy
```

### Advanced Flags

```bash
# Reuse local manifest (skip re-downloading)
SKIP_DOWNLOAD=true make deploy

# Plan only, don't ask to apply
DRY_RUN_ONLY=true make deploy

# Reconfigure dependencies
make install -- --reconfigure

# Validate all deps without deploying
make validate
```

### Debugging

#### Check current gcloud auth

```bash
gcloud auth list
gcloud config get-value project
```

#### Test cluster connectivity

```bash
export PROJECT_ID=gnp-plus-qa
export CLUSTER_NAME=my-cluster
export CLUSTER_LOCATION=us-central1

gcloud container clusters get-credentials $CLUSTER_NAME \
  --project=$PROJECT_ID --zone=$CLUSTER_LOCATION
kubectl cluster-info
kubectl get nodes
```

#### View Terraform state

```bash
cd terraform/
terraform state list
terraform state show module.ingress.kubernetes_manifest.ingress
```

#### Check ingress status in K8s

```bash
kubectl get ingress -n <namespace>
kubectl describe ingress <ingress-name> -n <namespace>
kubectl get events -n <namespace>
```

#### View Cloud Load Balancer

```bash
gcloud compute forwarding-rules list --project=$PROJECT_ID
gcloud compute target-https-proxies list --project=$PROJECT_ID
gcloud compute backend-services list --project=$PROJECT_ID
```

#### Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Error: Error when reading GCS bucket` | State bucket doesn't exist or wrong project | `make backend` to init backend |
| `Error: backend.gcs: error reading object` | Terraform state corrupted | `terraform state pull > backup.tfstate` then `terraform destroy` and redeploy |
| `Ingress failed to get IP` | LB provisioning delayed | Wait 10 minutes, check GCP console for warnings |
| `Denied: User not authorized` | Missing IAM roles | Ask admin to grant roles (see Requirements above) |
| `YAML validation error` | Downloaded manifest invalid | Check GitLab URL, token, or manifest format |

### State Recovery

#### Scenario: Terraform lock stuck

```bash
# Detect lock
ls -la .terraform/

# Force-unlock (use with caution)
terraform force-unlock <LOCK_ID>

# Retry deploy
make deploy
```

#### Scenario: State drift (manual K8s changes)

```bash
# Detect drift
terraform plan

# Refresh state without applying
terraform refresh

# If resource changed unexpectedly, import new state
terraform import module.ingress.kubernetes_manifest.ingress \
  'apiVersion=networking.k8s.io/v1,kind=Ingress,namespace=prod,name=my-ingress'
```

#### Scenario: Rollback to previous version

```bash
# List state versions
gsutil versioning get gs://<project>-tf-state

# Download specific version
gsutil cp gs://<project>-tf-state/ingress/terraform.tfstate#<VERSION> \
  ./terraform.tfstate.old

# Restore (DESTRUCTIVE — do this only after consultation)
gsutil cp terraform.tfstate.old gs://<project>-tf-state/ingress/terraform.tfstate
terraform refresh
make deploy --action=apply
```

### Destroy (Cleanup)

```bash
# Plan destroy
ACTION=destroy make deploy

# Confirm destruction — removes ingress + static IP, preserves namespace
```

**Note:** Namespace is NOT deleted. Use kubectl to clean up namespace if needed:

```bash
kubectl delete namespace <namespace>
```

---

## Contributing

### Adding a New Environment

1. **Create tfvars file:**

```bash
cat > environments/gnp-newenv-qa.tfvars <<'EOF'
project_id       = "gnp-newenv-qa"
cluster_name     = "gke-prod-primary"
cluster_location = "us-central1"
namespace        = "production"
static_ip_name   = "ingress-prod-ip"
EOF
```

2. **Create manifest directory:**

```bash
mkdir -p manifests/gnp-newenv-qa
```

3. **Add ingress YAML:**

```yaml
# manifests/gnp-newenv-qa/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prod-ingress
  namespace: production
  annotations:
    kubernetes.io/ingress.class: "gce"
    kubernetes.io/ingress.global-static-ip-name: "ingress-prod-ip"
    ingress.gcp.kubernetes.io/pre-shared-cert: "my-ssl-cert"
spec:
  rules:
    - host: "example.com"
      http:
        paths:
          - path: "/*"
            pathType: ImplementationSpecific
            backend:
              service:
                name: backend-service
                port:
                  number: 80
```

4. **Deploy:**

```bash
make deploy
# Select cluster and namespace interactively
```

### Modifying Module Logic

Ingress module is in `terraform/modules/ingress/`. To update:

1. Edit `terraform/modules/ingress/main.tf`
2. Plan to review changes: `make deploy ACTION=plan`
3. Apply: `make deploy ACTION=apply`

### Testing Changes

Use smoke test suite:

```bash
bash test/run-smoke.sh <ingress-yaml>
```

Validates YAML structure, GKE controller fields are stripped, etc.

### Secrets & Tokens

**Never commit** to git:
- `~/.gnp/ingress/config.env`
- `GITLAB_TOKEN` env var or token files
- Terraform state files

Use `.gitignore` (already configured) to prevent accidental commits.

---

## Troubleshooting

### Common Issues

**Q: "make install" times out downloading**
- Check internet connectivity: `curl https://go.dev/dl/`
- Increase timeout: Edit `scripts/setup.sh` curl calls

**Q: "gcloud auth" fails on Cloud Shell**
- Already authenticated on Cloud Shell by default
- If needed: `gcloud auth login` then `gcloud auth application-default login`

**Q: "terraform init" fails**
- Check GCS permissions: `gsutil ls gs://<project>-tf-state/`
- Verify bucket exists: `gcloud storage buckets describe gs://<project>-tf-state --project=<project>`

**Q: Ingress stuck in "pending" state**
- Wait 10-15 minutes for GCP LB provisioning
- Check GCP console for quota issues or errors
- Verify backend services are healthy: `kubectl get endpoints -n <namespace>`

**Q: SSL certificate not applied**
- Verify cert exists: `gcloud compute ssl-certificates list --project=<project>`
- Check ingress annotation: `kubectl get ingress <name> -n <namespace> -o yaml | grep pre-shared-cert`

### Getting Help

1. Check logs: `cat ~/.gnp/ingress/bootstrap.log`
2. View deploy log: `cat ~/.gnp/tickets/<ticket-id>/ingress-deployer-*.log`
3. Run with verbose terraform: `TF_LOG=DEBUG make deploy`
4. Ask infrastructure team with logs + error message

---

## Project Structure

```
Proyecto-Ingress-Deployer/
├── Makefile                       ← Entry point (install, deploy, etc)
├── README.md                      ← This file
├── .gitignore                     ← Excludes docs/, terraform state
│
├── scripts/
│   ├── setup.sh                   ← Dependency installer (idempotent)
│   ├── deploy.sh                  ← Main deployment orchestrator
│   ├── init-backend.sh            ← GCS backend initialization
│   ├── discover.sh                ← Discover GCP resources
│   └── lib/
│       ├── ui.sh                  ← Logging + UI functions
│       ├── downloader.sh          ← Download manifests from URLs
│       ├── yaml_cleaner.sh        ← Strip GKE-managed fields
│       └── cloud_armor.sh         ← Cloud Armor attachment
│
├── terraform/
│   ├── main.tf                    ← Root module (providers, data sources)
│   ├── variables.tf               ← Input variables
│   ├── outputs.tf                 ← Output values
│   ├── versions.tf                ← Provider versions
│   ├── backend.tf                 ← GCS backend configuration
│   └── modules/
│       └── ingress/
│           ├── main.tf            ← Ingress, LB, FrontendConfig resources
│           ├── variables.tf
│           ├── outputs.tf
│           └── versions.tf
│
├── environments/
│   ├── example.tfvars             ← Example environment config
│   ├── gnp-plus-qa.tfvars
│   ├── gnp-protecciondatosper-qa.tfvars
│   └── gnp-suscribe-asistidos-uat.tfvars
│
├── manifests/
│   └── <project>/
│       ├── ingress.yaml           ← K8s Ingress resource
│       └── frontendconfig.yaml    ← GKE-specific FrontendConfig
│
└── test/
    └── run-smoke.sh               ← Smoke test suite
```

---

## Performance & Optimization

### State Management

- **Versioning overhead:** GCS versioning adds ~10-20KB per state change (negligible)
- **Lock wait time:** Typically <30s. If longer, check `terraform.lock.hcl`

### Deployment Time

- **First deploy (new cluster):** 5-10 minutes (GCP LB provisioning)
- **Update (existing ingress):** 2-3 minutes (import + apply)
- **Destroy:** 3-5 minutes (resource cleanup + finalizer wait)

### Cost

- **GCS bucket versioning:** $0.02-0.05/month for typical state changes
- **Terraform state storage:** <$0.01/month
- **Load Balancer:** Billed by Google Cloud (ingress forwarding rules + backend services)

---

## Security

### State File Security

- **Encryption at rest:** GCS uniform bucket-level access enforces encryption
- **Encryption in transit:** HTTPS by default
- **Access control:** Only authenticated gcloud users with `storage.admin` can access

### RBAC & IAM

- **Terraform service account:** Recommended separate service account with minimal roles
- **kubectl RBAC:** Ingress deployment uses authenticated kubeconfig
- **GitLab tokens:** Store in `~/.gnp/tokens/` with mode 0600 (read-only)

### Sensitive Data

Never store in tfvars:
- SSL private keys (reference by name only)
- API keys or secrets (use Kubernetes Secrets instead)
- Database credentials

---

## FAQ

**Q: Can I deploy to multiple clusters simultaneously?**
A: No. Each deploy.sh run targets one cluster. Use CI/CD orchestration (GitLab CI, Cloud Build) to parallelize multiple cluster deployments.

**Q: How do I rollback?**
A: Keep backup ingress YAML (`~/.gnp/tickets/<ticket>/ingress_backup_*.yaml`), then:
```bash
kubectl apply -f ingress_backup_*.yaml
```
Or restore terraform state from GCS versioning (advanced).

**Q: Can I manage multiple ingresses in one project?**
A: Currently one ingress per namespace per deploy.sh run. Multiple ingresses require multiple module instances (requires terraform refactoring).

**Q: What if the cluster is deleted?**
A: Terraform state orphans. Clean up: `terraform state rm module.ingress.kubernetes_manifest.ingress` before re-deploying to new cluster.

**Q: How do I debug YAML validation errors?**
A: Check downloaded YAML: `cat manifests/<project>/ingress.yaml | yq .` then `make validate`.

---

## Support & Feedback

- **Issues:** Report bugs with logs + error message
- **Feature requests:** Discuss with infrastructure team
- **Security:** Report to infrastructure-security@gnp.com

---

**Last Updated:** 2026-06-03  
**Maintained by:** GNP Infrastructure Team  
**License:** Internal use only
