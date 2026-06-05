# Ingress Deployer — Architecture

**Audience:** DevOps / Infrastructure engineers  
**Last Updated:** 2026-06-04  
**Format:** Mermaid diagrams (render natively in GitLab, GitHub, VSCode)

---

## Contents

1. [System Context](#1-system-context)
2. [Internal Components](#2-internal-components)
3. [Deploy Sequence](#3-deploy-sequence)
4. [State Management](#4-state-management)
5. [Operational Gotchas](#5-operational-gotchas)

---

## 1. System Context

High-level view of actors and external systems. Each GCP project is an independent deployment target with its own GCS state bucket, GKE cluster, and Cloud Armor policy.

```mermaid
flowchart TB
    eng["👤 Infra Engineer\nlocal / Cloud Shell"]
    deployer["🔧 Ingress Deployer\nmake deploy"]
    gitlab["📦 GitLab\ningress YAML source"]
    gcp["☁️ GCP Project\nN independent environments"]
    gke["⚙️ GKE Cluster\nKubernetes"]
    gcs["🗄️ GCS Bucket\nPROJECT-tf-state"]
    armor["🛡️ Cloud Armor\nsecurity policy"]

    eng -->|"ticket · project · URL · action"| deployer
    deployer -->|"PRIVATE-TOKEN / API v4"| gitlab
    deployer -->|"gcloud + kubectl"| gcp
    deployer -->|"terraform apply"| gke
    deployer -->|"state + artifacts"| gcs
    deployer -->|"attach policy"| armor

    style deployer fill:#1f6feb,stroke:#388bfd,color:#fff
    style gke fill:#0d3025,stroke:#3fb950,color:#3fb950
    style gcs fill:#3d1f00,stroke:#f0a500,color:#f0a500
    style armor fill:#2d1b3d,stroke:#a371f7,color:#a371f7
```

---

## 2. Internal Components

`deploy.sh` is the single orchestrator. All lib files are sourced functions — no subprocesses. The Terraform module is called once per run and manages exactly three GCP/K8s resources.

```mermaid
graph TB
    subgraph entry["Makefile — entry point"]
        mk["make deploy / install / backend / clean"]
    end

    subgraph scripts["scripts/"]
        deploy["deploy.sh\norchestrator"]
        init["init-backend.sh\nGCS bucket + terraform init"]
        setup["setup.sh\ndependency installer"]
    end

    subgraph lib["lib/"]
        ui["ui.sh\nlogging · banner · wait_for_ip · get_credentials"]
        dl["downloader.sh\nGitLab API v4 · HTTPS URL · local path"]
        yc["yaml_cleaner.sh\nstrip GKE controller-managed fields"]
        ca["cloud_armor.sh\nauto-detect policy · attach to backends"]
    end

    subgraph tf["terraform/"]
        tfmain["main.tf\nproviders · module instantiation"]
        subgraph mod["modules/ingress/"]
            res["kubernetes_manifest — Ingress\nkubernetes_manifest — FrontendConfig\ngoogle_compute_global_address — Static IP"]
        end
    end

    mk --> deploy
    mk --> setup
    mk --> init
    deploy --> ui
    deploy --> dl
    deploy --> yc
    deploy --> ca
    deploy --> init
    deploy --> tfmain
    tfmain --> res

    style deploy fill:#1f6feb,stroke:#388bfd,color:#fff
    style res fill:#0d3025,stroke:#3fb950,color:#3fb950
```

---

## 3. Deploy Sequence

Full happy-path for `ACTION=plan` followed by interactive apply. The `ACTION=apply` variant skips the confirmation prompt and runs plan+apply in one shot.

```mermaid
sequenceDiagram
    actor Eng as Engineer
    participant D as deploy.sh
    participant GL as GitLab
    participant GCP as GCP APIs
    participant TF as Terraform
    participant GKE as GKE Cluster
    participant GCS as GCS Bucket

    Eng->>D: make deploy (ticket, project, URL, action)

    D->>GCP: auth check
    D->>GL: download ingress YAML via PRIVATE-TOKEN
    GL->>D: ingress.yaml

    D->>D: clean YAML, strip GKE controller fields
    D->>D: extract single Ingress document
    D->>GCP: list clusters and SSL certs
    GCP->>D: cluster name, location, cert name

    D->>D: generate project.tfvars
    D->>GKE: get-credentials
    D->>D: diff current vs new ingress
    D->>GCS: backup current ingress YAML

    D->>TF: init backend (GCS bucket)
    D->>TF: import existing resources (idempotent)
    Note over TF: namespace, static IP, Ingress, FrontendConfig

    D->>TF: plan
    TF->>D: plan summary
    D->>GCS: upload plan file

    D->>Eng: confirm apply?
    Eng->>D: yes

    D->>TF: apply
    TF->>GKE: apply Ingress + FrontendConfig
    TF->>GCP: create or update static IP

    D->>GCS: upload log and manifests
    D->>GKE: wait for IP assignment
    D->>GCP: attach Cloud Armor policy
```

---

## 4. State Management

One GCS bucket per GCP project. Versioning is enabled automatically by `init-backend.sh`, enabling state rollback. Artifacts from every run are stored alongside the state for audit and rollback reference.

```mermaid
graph TB
    subgraph gcs["GCS — PROJECT-tf-state  versioning enabled"]
        tfstate["ingress/terraform.tfstate\nall versions retained"]
        subgraph art["ingress-artifacts / TICKET / YYYYMMDD"]
            plan["plan-HHMMSS.tfplan"]
            backup["ingress_backup_HHMMSS.yaml"]
            fc["frontendconfig.yaml"]
            log["deploy.log"]
        end
    end

    deploy["deploy.sh"] -->|"terraform init backend"| tfstate
    deploy -->|"gsutil cp"| art
    tf["Terraform"] -->|"read and write state"| tfstate
    tf -->|"terraform import idempotent"| tfstate

    style tfstate fill:#3d1f00,stroke:#f0a500,color:#f0a500
    style art fill:#161b22,stroke:#30363d
```

### Rollback procedure

```bash
# List state versions
gsutil ls -a gs://<project>-tf-state/ingress/terraform.tfstate

# Restore a specific version (replace #<VERSION> with generation number)
gsutil cp "gs://<project>-tf-state/ingress/terraform.tfstate#<VERSION>" \
  gs://<project>-tf-state/ingress/terraform.tfstate

# Or restore from backup YAML (faster for ingress-only rollback)
kubectl apply -f "$TICKETS_BASE/<TICKET>/ingress_backup_<DATE>_<TIME>.yaml"
```

---

## 5. Operational Gotchas

Issues encountered in production environments. Each entry includes the root cause and verified fix.

---

### IngressClass resource missing → LB controller silently ignores ingress

**Symptom:** Ingress created with no events, `ADDRESS` empty after 10+ hours. `kubectl describe` shows `Events: <none>`.

**Root cause:** `spec.ingressClassName: gce` in the ingress spec requires an `IngressClass` resource named `gce` to exist in the cluster. If it doesn't exist, the GKE LB controller ignores the ingress completely — no errors, no events.

```bash
# Verify
kubectl get ingressclass

# Fix — add legacy annotation (recognized by controller without IngressClass resource)
kubectl annotate ingress <name> -n <namespace> \
  kubernetes.io/ingress.class=gce --overwrite
```

---

### Multi-document YAML breaks `terraform yamldecode`

**Symptom:** `Error: Call to function "yamldecode" failed: on line N, column 1: unexpected extra content after value`

**Root cause:** Ingress YAMLs fetched from GitLab may contain multiple documents separated by `---` (e.g., Ingress + Service + Deployment). `yamldecode()` in Terraform only accepts a single YAML document.

**Fix:** `deploy.sh` runs `yq 'select(.kind == "Ingress")'` after `clean_ingress_yaml` to extract only the Ingress document before passing the file to Terraform.

---

### GitLab PRIVATE-TOKEN + gcloud Bearer → SAML redirect (HTML response)

**Symptom:** Downloaded YAML file contains HTML instead of YAML. `yq` validation fails with parse error.

**Root cause:** Sending `Authorization: Bearer <gcloud-token>` to a GitLab instance with SAML SSO configured returns a 302 redirect to the identity provider login page instead of the file.

**Fix:** `downloader.sh` routes URLs matching `/api/v4/projects/` exclusively with `PRIVATE-TOKEN` header. gcloud Bearer token is only used for non-GitLab GCP endpoints.

---

### Terraform GCS backend requires ADC — `gcloud auth login` alone is insufficient

**Symptom:** `Error: Error when reading or editing Storage Bucket` during `terraform init` despite valid `gcloud` session.

**Root cause:** Terraform's GCS backend authenticates via Application Default Credentials (ADC), not the `gcloud` CLI session.

**Fix:** Run both:
```bash
gcloud auth login                        # CLI session (gcloud, kubectl commands)
gcloud auth application-default login   # ADC (Terraform GCS backend)
```

---

### `.terraform.lock.hcl` is not a state lock

**Symptom:** Confusion when the file is present and developers assume Terraform is locked.

**Clarification:** `.terraform.lock.hcl` is the provider dependency lock file — it records provider versions and checksums. It is always present after `terraform init` and **must be committed to version control**. The actual state lock lives in GCS (released automatically on success or via `terraform force-unlock`).

---

### Forwarding rules in conflict → LB sync Error 400

**Symptom:** `Error syncing to GCP: error running load balancer syncing routine: ... googleapi: Error 400: Invalid value for field 'resource.IPAddress': '...'. Specified IP address is in-use and would result in a conflict.`

**Root cause:** One or more GCP forwarding rules already occupy the static IP before the GKE LB controller can build its managed stack. Common sources:
- Manual forwarding rules created outside GKE (e.g. a quick SSL termination rule named `https`)
- Orphan `k8s2-fr-*` GKE rules from a previous incomplete LB creation

**Fix (automated):** `deploy.sh` runs `check_ip_conflicts` before `terraform plan/apply` and offers to delete conflicting rules interactively.

```bash
# Manual resolution if needed
gcloud compute forwarding-rules list \
  --project=<project> --filter="IPAddress=<ip>"
gcloud compute forwarding-rules delete <rule-name> --global --project=<project>
```

**Note:** If the conflicting rule belongs to a different GKE ingress, the deployer will not offer to delete it — coordinate with the team owning that ingress first.

---

*See [README.md](../README.md) for operational usage, deployment commands, and troubleshooting reference.*
