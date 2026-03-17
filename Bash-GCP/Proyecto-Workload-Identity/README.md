# Workload Identity Manager

## Overview

The Workload Identity Manager is a comprehensive utility designed to streamline the configuration and management of GCP Workload Identity between Google Cloud Platform service accounts and Kubernetes service accounts deployed on Google Kubernetes Engine (GKE) clusters. This tool abstracts away operational complexity through an intuitive interactive interface, enabling infrastructure teams to establish secure, audit-compliant workload authentication without manual configuration overhead.

### Core Objectives

- **Simplified Configuration Management** — Establish secure workload identity bindings through guided prompts rather than repetitive manual gcloud commands
- **Operational Transparency** — Maintain a complete, timestamped audit trail of all configuration changes and operations
- **Team Collaboration** — Enable knowledge sharing and consistency across infrastructure teams through centralized operation logging
- **Security Assurance** — Prevent misconfigurations through validation, reduce exposure of sensitive credentials, and ensure principle of least privilege
- **Operational Efficiency** — Reduce time-to-deployment and eliminate common configuration errors

## Prerequisites

Before utilizing this tool, ensure your environment meets the following requirements:

### Required Tools

- **Google Cloud SDK (`gcloud`)** — Version 420 or later, authenticated with appropriate credentials
  ```bash
  gcloud auth login
  gcloud config set project YOUR-PROJECT-ID
  gcloud auth application-default login  # For programmatic access
  ```

- **kubectl** — Version 1.24 or later, configured to access your GKE cluster
  ```bash
  gcloud container clusters get-credentials CLUSTER-NAME --zone ZONE-NAME
  kubectl cluster-info
  ```

- **jq** — Command-line JSON processor (required for response parsing)
  ```bash
  # macOS (Homebrew)
  brew install jq
  
  # Linux (Ubuntu/Debian)
  sudo apt-get install jq
  ```

### Required IAM Permissions

Your GCP service account or user account must possess the following IAM roles:

- `iam.serviceAccountAdmin` — Create and manage service accounts
- `iam.securityAdmin` — Configure IAM bindings
- `container.admin` — Access and manage GKE clusters
- `compute.admin` — Access cluster node information
- `storage.admin` — (Optional) For Cloud Storage bucket operations

### Network & Connectivity

- Outbound HTTPS connectivity to Google Cloud APIs (iap.googleapis.com, container.googleapis.com, iam.googleapis.com)
- kubectl port-forward access to your GKE cluster control plane

## Quick Start

To begin using the Workload Identity Manager, execute the main script with no arguments:

```bash
./workload-identity.sh
```

This launches the interactive menu interface. The application will guide you through all available operations with contextual prompts and validation.

## Usage Guide

The Workload Identity Manager provides five primary operations, each accessible through the interactive menu. This section details the workflow for each operation.

### Operation 1: Configure Workload Identity

This operation establishes a complete workload identity binding between a Kubernetes Service Account and a Google Cloud IAM Service Account.

**Workflow:**

```
1. Launch the tool:
   ./workload-identity.sh

2. Select "1) Configure Workload Identity"

3. When prompted:
   - Enter ticket identifier (required for audit tracking, e.g., CTASK0012345)
   - Select or specify GCP project ID
   - Select or specify GKE cluster and location
   - Provide target Kubernetes namespace (e.g., apps, staging, production)
   - Provide Kubernetes Service Account name (tool creates if nonexistent)
   - Provide GCP Service Account email (tool creates if nonexistent)

4. The tool will:
   ✓ Create the Kubernetes Service Account if absent
   ✓ Create the GCP Service Account if absent
   ✓ Establish IAM binding: `roles/iam.workloadIdentityUser`
   ✓ Annotate the KSA with GCP account information
   ✓ Log the operation with timestamp and ticket reference
```

**Outcome:** Kubernetes pods running under the specified KSA can now authenticate with GCP using the linked IAM Service Account identity.

---

### Operation 2: Verify Workload Identity Configuration

This operation performs comprehensive validation of an existing workload identity configuration.

**Workflow:**

```
1. Select "2) Verify Workload Identity"

2. When prompted:
   - Select GCP project and cluster
   - Provide KSA name and namespace

3. The tool validates:
   ✓ GCP Service Account exists
   ✓ Kubernetes Service Account exists
   ✓ IAM binding is properly configured
   ✓ KSA annotation is present and correct
   ✓ RBAC bindings permit pod access
```

**Outcome:** Receive a detailed status report identifying any configuration gaps or misalignments that require remediation.

---

### Operation 3: Remove/Cleanup Workload Identity

This operation safely removes workload identity configurations with granular cleanup options.

**Workflow:**

```
1. Select "3) Remove/Cleanup Workload Identity"

2. The tool displays active configurations from the registry

3. Select desired cleanup level:
   Level 1 (Binding only):
      - Remove IAM binding
      - Preserve KSA and IAM Service Account
      - Use case: Re-binding to different KSA or temporary disable

   Level 2 (Binding + KSA):
      - Remove IAM binding
      - Remove Kubernetes Service Account
      - Preserve GCP Service Account (may be used elsewhere)
      - Use case: Complete namespace cleanup while retaining GCP resources

   Level 3 (Full cleanup):
      - Remove IAM binding
      - Remove Kubernetes Service Account
      - Remove GCP Service Account
      - Use case: Complete resource deprovisioning
```

**Outcome:** Configuration is safely removed with audit trail maintained in registry.

---

### Operation 4: List Workload Identities

This operation provides visibility into all configured workload identities.

**Workflow:**

```
1. Select "4) List Workload Identities"

2. The tool displays:
   - All configured GCP projects
   - All configured clusters within projects
   - All workload identity bindings (by namespace and KSA)
   - Current status of each binding (active/removed)
```

**Outcome:** Quick reference of all workload identity configurations for audit and troubleshooting purposes.

---

### Operation 5: View Operations Registry

This operation displays the complete audit log of all operations performed.

**Workflow:**

```
1. Select "5) View Operations Registry"

2. The tool displays recent operations including:
   - Timestamp of operation
   - Associated ticket identifier
   - GCP project and cluster information
   - KSA and IAM Service Account details
   - Operation status (active/removed)
```

**Outcome:** Complete audit trail for compliance and troubleshooting purposes.

## Cloud Storage Synchronization (Enabled by Default)

The Workload Identity Manager includes integrated synchronization of the operations registry to the centralized GCP Cloud Storage bucket `gs://gnp-workloadidentity`. Registry synchronization is automatically enabled for all operations, providing team collaboration, distributed access, and automated backup of configuration state without additional configuration required.

For teams requiring isolation or private storage, the bucket target can be overridden via environment variables (see Phase 3 below).

### Benefits of Cloud Storage Integration

| Capability | Benefit |
|---|---|
| **Automatic Synchronization** | Registry syncs to gs://gnp-workloadidentity after every operation (setup, verify, cleanup) |
| **Distributed Access** | Team members access synchronized registry regardless of local disk state |
| **Zero Configuration** | Default bucket is pre-configured; works immediately without setup overhead |
| **Automatic Versioning** | GCS versioning maintains historical snapshots for recovery and audit |
| **Backup & Disaster Recovery** | Configuration state persists independently of local infrastructure |
| **Team Collaboration** | Single source of truth for workload identity inventory across the organization |
| **Compliance & Audit** | Immutable audit trail of all configuration changes |

### Prerequisites for Cloud Storage Integration

To enable registry synchronization, ensure:

1. **Bucket Exists** — The target bucket `gs://gnp-workloadidentity` has been created (see Phase 1 below)
2. **IAM Permissions** — Your user/service account has `storage.objectCreator` and `storage.objectViewer` roles
3. **gcloud CLI** — Properly configured and authenticated

### Configuration Steps (If Customization Required)

#### Phase 0: Verify Default Bucket (No Action Required)

The script defaults to `gs://gnp-workloadidentity`. No configuration is needed to use the default bucket.

To verify the default bucket is configured:

```bash
grep "G_GCS_BUCKET" workload-identity.sh | head -1
# Output: G_GCS_BUCKET="${WI_GCS_BUCKET:-gs://gnp-workloadidentity}"
```

#### Phase 1: Create Cloud Storage Bucket (Initial Setup Only)

This step is required ONLY if the bucket does not exist. Contact your infrastructure team to verify bucket creation status.

To create the bucket:

```bash
# Define configuration variables
BUCKET_NAME="gnp-workloadidentity"
PROJECT_ID="your-gcp-project-id"

# Create the bucket with STANDARD storage class
gsutil mb -p $PROJECT_ID -c STANDARD gs://$BUCKET_NAME/

# Enable object versioning for historical recovery
gsutil versioning set on gs://$BUCKET_NAME/

# Set lifecycle policy (optional: retain 30 versions)
cat << 'EOF' > /tmp/lifecycle.json
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"numNewerVersions": 30}
      }
    ]
  }
}
EOF
gsutil lifecycle set /tmp/lifecycle.json gs://$BUCKET_NAME/
```

#### Phase 2: Configure Access Control (Required for Default Bucket)

Grant team members permissions to read and write the default registry bucket:

```bash
# Your GCP user email
YOUR_EMAIL=$(gcloud config get-value account)

# Grant your own permissions
gsutil iam ch user:$YOUR_EMAIL:roles/storage.objectCreator gs://gnp-workloadidentity/
gsutil iam ch user:$YOUR_EMAIL:roles/storage.objectViewer gs://gnp-workloadidentity/

# Grant permissions to additional team members
TEAM_MEMBER_EMAIL="engineer@your-domain.com"
gsutil iam ch user:$TEAM_MEMBER_EMAIL:roles/storage.objectCreator gs://gnp-workloadidentity/
gsutil iam ch user:$TEAM_MEMBER_EMAIL:roles/storage.objectViewer gs://gnp-workloadidentity/

# Alternative: Grant permissions to entire Google Group
GROUP_EMAIL="infrastructure-team@your-domain.com"
gsutil iam ch group:$GROUP_EMAIL:roles/storage.objectCreator gs://gnp-workloadidentity/
gsutil iam ch group:$GROUP_EMAIL:roles/storage.objectViewer gs://gnp-workloadidentity/
```

#### Phase 3: Verify Synchronization (No Configuration Needed)

The script automatically synchronizes to `gs://gnp-workloadidentity` after any operation. To verify:

```bash
# Run any operation (setup, verify, or cleanup)
./workload-identity.sh

# You should observe confirmation messages such as:
# ✓ Registry pushed to gs://gnp-workloadidentity/workload-identity-registry.csv

# Monitor bucket contents
gsutil ls -l gs://gnp-workloadidentity/

# Review versioning history
gsutil ls -L gs://gnp-workloadidentity/workload-identity-registry.csv

# View recent sync status
tail -20 logs/workload_identity_*.log | grep -i "gcs\|remote\|bucket"
```

#### Phase 4: Optional - Override Default Bucket

To use a different bucket instead of the default `gs://gnp-workloadidentity`:

**Option A: Temporary (current session only)**
```bash
export WI_GCS_BUCKET="gs://your-custom-bucket"
./workload-identity.sh
```

**Option B: Persistent (add to shell profile)**
```bash
# Add to your shell profile (~/.bashrc, ~/.zshrc, or ~/.bash_profile)
echo 'export WI_GCS_BUCKET="gs://your-custom-bucket"' >> ~/.bashrc
source ~/.bashrc
```

**Option C: System-wide (via /etc/environment)**
```bash
# For production environments, set in system environment
echo 'WI_GCS_BUCKET="gs://your-custom-bucket"' | sudo tee -a /etc/environment
```

**Option D: Disable synchronization entirely**
```bash
export WI_GCS_BUCKET=""
./workload-identity.sh
```

### Troubleshooting Cloud Storage Integration

**Symptom: "✓ Registry pushed to gs://gnp-workloadidentity" appears in logs**
- **Status:** Synchronization is working correctly
- **Action:** No action needed

**Symptom: "⚠ WI_GCS_BUCKET not set — skipping remote sync"**
- **Cause:** Environment variable explicitly set to empty string
- **Resolution:** Unset the variable or set to valid bucket: `unset WI_GCS_BUCKET` or `export WI_GCS_BUCKET="gs://gnp-workloadidentity"`

**Symptom: "ERROR: GCS push failed"**
- **Cause:** Permission denied or bucket does not exist
- **Resolution:** Verify permissions with `gsutil iam get gs://your-bucket-name` and bucket existence with `gsutil ls -b gs://your-bucket-name`

**Symptom: "ERROR: GCS pull failed"**
- **Cause:** Registry object missing from bucket
- **Resolution:** Verify bucket contents with `gsutil ls gs://your-bucket-name/` and check object permissions

---

## Recent Updates (v4.5.0)

### Cloud Storage Integration Completed

- ✅ **Default Bucket Configured**: `gs://gnp-workloadidentity` is now the built-in default for all registry synchronization
- ✅ **Automatic Synchronization**: Registry automatically syncs after every operation (setup, verify, cleanup) — no manual steps required
- ✅ **Zero Configuration**: works immediately out-of-the-box with no setup overhead; bucket permissions are the only prerequisite
- ✅ **Override Capability**: Teams can still override to a custom bucket via `WI_GCS_BUCKET` environment variable if needed
- ✅ **Production Ready**: Lifecycle policies, versioning, and RBAC fully supported

### Key Changes

| Aspect | Before | After |
|--------|--------|-------|
| **Bucket Configuration** | User must configure via environment variables | Default: `gs://gnp-workloadidentity` (no setup needed) |
| **Synchronization** | Optional, required manual setup | Automatic and enabled by default |
| **Override Option** | N/A | Still possible via `WI_GCS_BUCKET` environment variable |
| **Lifecycle** | Manual | Automatic with 30-version retention policy |

### How to Upgrade

If you were using the previous version:

1. Pull the latest version of the script
2. Ensure your GCP user has access to `gs://gnp-workloadidentity` (ask your infrastructure team)
3. Grant yourself permissions (see Phase 2 above)
4. Run the script as normal — synchronization now works automatically!

No other changes or configuration needed.
