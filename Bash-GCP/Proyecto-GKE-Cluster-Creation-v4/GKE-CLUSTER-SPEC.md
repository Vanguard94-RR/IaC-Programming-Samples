# GKE Cluster Specification

This document describes the configuration applied by `bin/create_gke_cluster.sh` when creating a GKE cluster. Maintained alongside the script — update when defaults change.

## Overview

**Entrypoint:** `./bin/create_gke_cluster.sh [SUBCOMMAND] [FLAGS]`

### Subcommands

| Subcommand | Purpose |
| ----- | ----- |
| `create` (default) | Full 11-step GKE cluster creation (12 for PRO, interactive) |
| `update-armor --project <id>` | Apply/update Cloud Armor rules |
| `rollback-armor --project <id>` | Restore Cloud Armor from JSON backup |
| `fix-shared-vpc` | Associate service project to Shared VPC host |
| `log4j --project <id>` | Apply or backup log4j WAF rules |

### CLI Flags

| Flag | Effect |
| ----- | ----- |
| `--dry-run` | Print all gcloud/kubectl calls without executing |
| `--verbose` | Print verbose diagnostic output |
| `--project <id>` | Pre-load project ID (skip prompt) |
| `--cluster <name>` | Pre-load cluster name (skip prompt) |
| `--region <region>` | Pre-load region (skip prompt) |
| `--env <qa\|uat\|pro>` | Pre-load environment (sets machine type, channel, fleet) |

### Environment Auto-detection

If `--env` is not provided, environment is inferred from the project ID suffix:

| Project ID suffix | Environment |
| ----- | ----- |
| `-pro` | PRO |
| `-uat` | UAT |
| anything else | QA |

---

## Shared Defaults

Configuration identical across all environments.

### GKE Cluster Flags

| Flag | Value |
| ----- | ----- |
| Image type | `COS_CONTAINERD` |
| Disk type | `pd-balanced` |
| Disk size | 100 GB |
| Max pods per node | 110 |
| Logging | `SYSTEM, WORKLOAD` |
| Monitoring | `SYSTEM, STORAGE, POD, DEPLOYMENT, STATEFULSET, DAEMONSET, HPA, CADVISOR, KUBELET` |
| Intra-node visibility | Disabled |
| IP aliasing (VPC-native) | Enabled |
| Legacy endpoint metadata | Disabled (`disable-legacy-endpoints=true`) |
| Security posture | `standard` |
| Workload vulnerability scanning | Disabled |
| Google Cloud access | Disabled |
| Binary Authorization | `DISABLED` |
| Managed Prometheus | Enabled |
| Shielded nodes | Enabled |
| Shielded secure boot | Enabled |
| Shielded integrity monitoring | Enabled |
| Secret Manager integration | Enabled |
| Auto-upgrade | Enabled |
| Auto-repair | Enabled |
| Max surge upgrade | 1 |
| Max unavailable upgrade | 0 |
| Addons | `HorizontalPodAutoscaling, HttpLoadBalancing, GcePersistentDiskCsiDriver, GcpFilestoreCsiDriver` |
| Workload pool | `{project_id}.svc.id.goog` |

### Cloud NAT

Mandatory for all environments. Always uses a fixed reserved static IP — auto-allocation is never used.

| Parameter | Value |
| ----- | ----- |
| Router name | `{project_id}-router` |
| NAT gateway name | `{project_id}-nat` |
| Static IP name | `{project_id}-nat-ip` |
| Subnet coverage | All subnet IP ranges |
| ICMP idle timeout | 30 s |
| TCP established idle timeout | 1200 s (20 min) |
| TCP transitory idle timeout | 30 s |
| UDP idle timeout | 30 s |

### Cloud Armor

Policy name: `cve-canary`

| Priority | Name | Expression | Action |
| ----- | ----- | ----- | ----- |
| 100 | CVE-Canary WAF | `evaluatePreconfiguredExpr('cve-canary')` | deny-403 |
| 200 | XSS / SQLi WAF | `evaluatePreconfiguredExpr('xss-stable') OR evaluatePreconfiguredExpr('sqli-stable')` | deny-403 |
| 300 | Allow known IPs | `inIpRange(origin.ip, '35.238.84.248,34.121.197.40')` | allow |
| 400 | Rate limit | `true` | throttle |
| 2147483647 | Default deny | all | deny-403 |

**Rate limit (priority 400):** 100 requests / 60 s per source IP. Exceeding requests: deny-403.

> **Maintenance note:** Allowed IPs at priority 300 are hardcoded in `lib/hardening.sh:11`. Update when egress IPs change. Policy name `cve-canary` is hardcoded in `lib/hardening.sh:9`. Update if policy is renamed.

### SSL Policy

Policy name: `sslsecure`

| Parameter | Value |
| ----- | ----- |
| Profile | `MODERN` |
| Minimum TLS version | 1.2 |

---

## Environment Specifications

### QA / UAT

#### Cluster

**Shared settings:**

| Parameter | Value |
| ----- | ----- |
| Machine type | `n1-standard-2` |
| Release channel | `regular` |
| Default region | `us-central1` |
| Node zone | `{region}-f` |
| GKE version | Auto-fetched from server-config for `regular` channel |

**Per-environment differences:**

| Parameter | QA | UAT |
| ----- | ----- | ----- |
| Default node count | 1 | 2 |
| Fleet project | `gnp-fleets-qa` | `gnp-fleets-uat` |

#### Networking

| Parameter | Value |
| ----- | ----- |
| VPC name | `{project_id}-vpc` (new VPC path) |
| Subnet name | `{project_id}-subnet` (new VPC path) |
| Primary subnet CIDR | User-provided — full range used as-is (nodes, ILBs) |
| Pods secondary range | GKE auto-allocated at cluster creation |
| Services secondary range | GKE auto-allocated at cluster creation |
| Stack type | IPv4 only |
| MTU | 1460 |
| BGP routing mode | Regional |
| Private Google access | Enabled |
| Cluster type | Private nodes (default) |
| Control plane CIDR | `172.19.0.0/28` (default — must be unique per cluster within VPC) |
| Authorized networks | Optional — auto-detected from current public IP when provided |

#### Security

| Parameter | Value |
| ----- | ----- |
| Cloud Armor | Applied (see Shared Defaults) |
| SSL policy | Applied (see Shared Defaults) |
| Workload identity pool | `{project_id}.svc.id.goog` |

#### Post-creation Components

| Component | Value |
| ----- | ----- |
| Namespace | `apps` |
| Kubernetes Service Account (KSA) | `apps-gke` |
| GCP IAM Service Account | `apps-sa` |
| Workload Identity binding | `apps-sa@{project_id}.iam.gserviceaccount.com` ↔ `apps/apps-gke` |
| Twistlock | Not deployed |

---

### PRO

#### Cluster

| Parameter | Value |
| ----- | ----- |
| Machine type | `n2-standard-2` |
| Default node count | 2 |
| Release channel | `stable` |
| Fleet project | `gnp-fleets-pro` |
| Default region | `us-central1` |
| Node zone | `{region}-f` |
| GKE version | Auto-fetched from server-config for `stable` channel |

#### Networking

Same as QA. See QA — Networking section above.

#### Security

Same as QA. See QA — Security section above.

#### Post-creation Components

| Component | Value |
| ----- | ----- |
| Namespace | `apps` |
| Kubernetes Service Account (KSA) | `apps-gke` |
| GCP IAM Service Account | `apps-sa` |
| Workload Identity binding | `apps-sa@{project_id}.iam.gserviceaccount.com` ↔ `apps/apps-gke` |
| Twistlock | Deployed (see below) |

**Twistlock DaemonSet (PRO only):**

| Parameter | Value |
| ----- | ----- |
| Namespace | `twistlock` |
| Defender image | `registry-auth.twistlock.com/tw_0uchx1fydjtjdemwtvgh538up3q5t1qq/twistlock/defender:defender_34_02_133` |
| Console endpoint | `wss://us-west1.cloud.twistlock.com:443` |
| Cluster ID | `6179b9dd-f72a-7c11-9384-87e75f50dc62` (per-organization; obtain from Twistlock console) |
| Memory limit | 512 Mi |
| CPU limit | 900 m |
| CPU request | 256 m |
| Deploy retry attempts | 3 |

> **Maintenance note:** Twistlock image tag is pinned. Update `config/daemonset.yaml` when upgrading Defender version.

---

## Shared VPC

Used when the cluster's project is a service project attached to a Shared VPC host.

| Parameter | Value |
| ----- | ----- |
| Default host project | `gnp-red-data-central` |
| GKE service account | `service-{project_number}@container-engine-robot.iam.gserviceaccount.com` |
| API service account | `{project_number}@cloudservices.gserviceaccount.com` |
| Role on host subnet (both SAs) | `roles/compute.networkUser` |
| Additional role on host subnet (GKE SA only) | `roles/container.hostServiceAgentUser` |
| Secondary range detection | Auto-detected from subnet; prompts user if non-standard names found |
| IAM propagation delay | 10 s (override with `IAM_PROPAGATION_DELAY` env var) |

---

## GCP APIs Enabled by Script

| API | Purpose |
| ----- | ----- |
| `container.googleapis.com` | GKE cluster management |
| `gkehub.googleapis.com` | Fleet registration |
| `compute.googleapis.com` | VPC, subnets, Cloud NAT, static IPs |
| `containersecurity.googleapis.com` | Container security posture |

---

## GCP Permissions Required

### Service project

| Role | Purpose |
| ----- | ----- |
| `roles/container.admin` | Create and manage GKE clusters |
| `roles/compute.admin` | VPC, subnets, Cloud NAT, static IPs |
| `roles/iam.securityAdmin` | Workload Identity IAM bindings |

### Host project (Shared VPC only)

| Role | Purpose |
| ----- | ----- |
| `roles/compute.xpnAdmin` | Enable Shared VPC service project association |
| `roles/compute.networkAdmin` | Grant subnet access to GKE service accounts |
