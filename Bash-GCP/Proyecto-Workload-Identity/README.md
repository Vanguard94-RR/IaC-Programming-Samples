# Workload Identity Manager

Your friendly tool for setting up secure authentication between Kubernetes and Google Cloud. No more managing complex service account keys — let your pods authenticate safely and directly with Google Cloud services!

## What's This Tool Do?

Workload Identity is a secure way for your Kubernetes pods to authenticate with Google Cloud services without passing around sensitive keys. Think of it as giving your pod an identity that GCP recognizes and trusts.

This tool walks you through the entire setup process step-by-step:
- ✨ Creates the Kubernetes Service Account (KSA) for your pod
- ✨ Creates the Google Cloud Service Account (IAM SA) 
- ✨ Links them together so they trust each other
- ✨ Sets up the annotation so pods know which GCP account to use
- ✨ Keeps a detailed log of everything for your team

Perfect for teams that want a simple, audit-friendly way to manage workload identity configurations.

## Getting Started (30 seconds)

Just run the interactive menu:

```bash
./workload-identity.sh
```

Follow the prompts — the tool guides you through everything! No flags or command-line arguments needed.

## What You Get

- **Interactive Menu** — No need to memorize commands, just follow the colorful prompts
- **Full Audit Trail** — CSV registry tracks every configuration and change
- **Team-Friendly Logs** — Organized by ticket number for easy tracking
- **Smart Validation** — Catches typos and common mistakes before they cause problems
- **Clear Error Messages** — When something goes wrong, you'll know exactly what and why
- **One-Click Verification** — Verify your setup is working correctly
- **Easy Cleanup** — Remove configurations safely when you need to

## How to Use It — Step by Step

### Option 1: Set Up Workload Identity for a New App

```bash
./workload-identity.sh
→ Select: 1) Setup Workload Identity
→ Enter ticket number (e.g., CTASK0012345)
→ Choose your GCP project
→ Pick your GKE cluster
→ Enter namespace (e.g., apps, staging, production)
→ Enter Kubernetes Service Account name for your app
→ Enter GCP Service Account email (it'll create it if it doesn't exist)
→ Done! ✨
```

Your pod can now authenticate with GCP. Easy, right?

### Option 2: Verify Everything is Wired Correctly

Already set something up and want to make sure it works?

```bash
./workload-identity.sh
→ Select: 2) Verify Workload Identity
→ Choose your project and cluster
→ Verify checks:
   ✓ Is the GCP account there?
   ✓ Is the Kubernetes account there?
   ✓ Are they linked correctly?
   ✓ Does the pod annotation work?
```

Gives you a clean report of what's working and what's not.

### Option 3: Clean Up When You're Done

Need to remove a workload identity setup?

```bash
./workload-identity.sh
→ Select: 3) Remove/Cleanup Workload Identity
→ Choose what to remove:
   • Just the connection (keep both accounts)
   • Connection + Kubernetes account (keep GCP account)
   • Everything (clean slate)
```

Safe and reversible!

### Option 4: See Everything That's Configured

Lost track of what you've set up?

```bash
./workload-identity.sh
→ Select: 4) List Workload Identities
→ Shows all your projects, clusters, and configurations
```

See everything at a glance.

### Option 5: Check Your Operation History

Curious about what was done and when?

```bash
./workload-identity.sh
→ Select: 5) View Operations Registry
→ Shows recent operations with dates and status
```

Complete audit trail.

## Setting Up Cloud Storage (Optional but Recommended)

Want your workload identity registry backed up and synced across your team? Cloud Storage auto-sync keeps everyone in sync!

### Why Use Cloud Storage?

- 🤝 **Team Collaboration** — Everyone has the same registry
- 📦 **Automatic Backup** — Your configuration is always backed up
- 🔄 **Sync Across Machines** — Pull latest configs when you run the tool
- 🛡️ **Never Lose History** — GCS keeps versions of your registry

### Quick Setup (5 minutes)

#### Step 1: Create a Cloud Storage Bucket

```bash
# Choose a unique bucket name (globally unique across all of Google Cloud!)
BUCKET_NAME="my-company-workload-identity-registry"
PROJECT_ID="your-gcp-project-id"

# Create the bucket
gsutil mb -p $PROJECT_ID gs://$BUCKET_NAME/

# Make it versioned so you can recover old versions
gsutil versioning set on gs://$BUCKET_NAME/
```

#### Step 2: Set Up Permissions

Everyone who uses this tool needs read/write access:

```bash
# Get your GCP user email
gcloud config get-value account

# Add yourself and team members
gsutil iam ch user:YOUR-EMAIL:objectCreator gs://$BUCKET_NAME/
gsutil iam ch user:YOUR-EMAIL:objectViewer gs://$BUCKET_NAME/
```

#### Step 3: Enable Auto-Sync in the Tool

Before running the script, set one environment variable:

```bash
export WI_GCS_BUCKET="gs://my-company-workload-identity-registry"

# Now run the tool as usual
./workload-identity.sh
```

Or make it permanent by adding to your shell profile (`.bashrc` or `.zshrc`):

```bash
echo 'export WI_GCS_BUCKET="gs://my-company-workload-identity-registry"' >> ~/.bashrc
source ~/.bashrc
```

**That's it!** Now every time you:
- ✅ Set up a workload identity
- ✅ Verify a configuration
- ✅ Clean something up

Your team's registry is automatically synced to Cloud Storage. When teammates run the tool, they'll see your latest configurations!

### Checking if It's Working

The tool will show a message like:
```
✓ Registry pushed to gs://my-company-workload-identity-registry/workload-identity-registry.csv
```

If you don't see that message, the bucket isn't set or there's a permission issue — no problem though, the tool works fine without it!

## What You Need Before Starting

Before you run this tool, make sure you have:

- ✅ **gcloud CLI** installed and logged in
  ```bash
  gcloud auth login
  gcloud config set project YOUR-PROJECT-ID
  ```

- ✅ **kubectl** installed and pointing to your GKE cluster
  ```bash
  kubectl cluster-info
  ```

- ✅ **jq** installed (for JSON parsing)
  ```bash
  # On Mac
  brew install jq
  # On Ubuntu/Debian
  sudo apt-get install jq
  ```

- ✅ **Permissions in GCP** to:
  - Create service accounts
  - Add IAM bindings
  - Manage Kubernetes namespaces and service accounts

That's really it! If you can run `gcloud` and `kubectl` commands manually, you can use this tool.

## Understanding Your Registry

The tool keeps a simple CSV file (`workload-identity-registry.csv`) that tracks everything:

```
Ticket,Project,Cluster,Namespace,KSA,IAM_SA,Status,Date
CTASK0012345,my-project,gke-cluster-1,apps,my-app,my-app@my-project.iam.gserviceaccount.com,active,2026-03-17
```

**What the Status column means:**
- `active` — This workload identity is up and running
- `removed-binding` — Connection was removed, but accounts still exist
- `removed-all` — Everything was cleaned up

This registry is your audit log — shows exactly what was done, when, and by which ticket.

## Estructura

```
Proyecto-Workload-Identity/
├── workload-identity.sh          # Script principal interactivo (1500+ líneas)
├── workload-identity-registry.csv # Registro de operaciones (ignorado en git)
├── README.md                     # Este archivo
└── .gitignore                    # Archivos ignorados
```

## Optimizaciones Implementadas

### Performance
- ✅ Actualización CSV con awk (single-pass en O(n) en vez de O(n²))
- ✅ Búsquedas consolidadas en una sola pasada
- ✅ Reutilización de variables

### Robustez
- ✅ `set -euo pipefail` para manejo seguro de errores
- ✅ Trap handlers para cleanup en caso de fallo
- ✅ Validación completa de entrada
- ✅ Manejo graceful de casos edge

### Seguridad
- ✅ Permisos CSV 600 (solo lectura/escritura propietario)
- ✅ Variables siempre quoted
- ✅ Validación de formato de IDs y nombres
- ✅ Sanitización de entrada de usuario

### Código
- ✅ Variables globales con prefijo `G_`
- ✅ Funciones documentadas con propósito claro
- ✅ Nomenclatura consistente
- ✅ Logging en todos los puntos críticos
- ✅ Errores con contexto de línea

