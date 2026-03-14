#!/bin/bash
# =============================================================================
# Workload Identity Manager - Configuration File
# =============================================================================
# This file contains all configurable parameters for the Workload Identity
# Manager script. Edit these values to customize behavior for your environment.
#
# Copyright: GNP Infrastructure Team
# License: Internal Use Only
# Version: 4.0.0
# =============================================================================

# Security: IAM role for Workload Identity binding
# Default: roles/iam.workloadIdentityUser (required for WI to work)
export WI_IAM_ROLE="${WI_IAM_ROLE:-roles/iam.workloadIdentityUser}"

# Default Kubernetes namespace if user doesn't specify one
# Default: apps (change to match your primary namespace)
export WI_DEFAULT_NAMESPACE="${WI_DEFAULT_NAMESPACE:-apps}"

# Kubernetes annotation key for linking to GCP service account
# Default: iam.gke.io/gcp-service-account (do not change unless using custom namespace)
export WI_ANNOTATION_KEY="${WI_ANNOTATION_KEY:-iam.gke.io/gcp-service-account}"

# Registry file for tracking all Workload Identity configurations
# Default: workload-identity-registry.csv (stored in script directory)
# This CSV maintains audit trail of all WI bindings created/modified/deleted
export WI_REGISTRY_FILE="${WI_REGISTRY_FILE:-workload-identity-registry.csv}"

# Base directory for logs organized by ticket/CTASK
# Default: Tickets/ (parent of current directory)
# Logs are then organized by CTASK number: Tickets/CTASK0001234/logs/
export WI_LOG_BASE_DIR="${WI_LOG_BASE_DIR:-Tickets}"

# Maximum retries for gcloud/kubectl operations before failing
# Default: 3 (with exponential backoff: 1s, 2s, 4s)
# Increase if experiencing network instability
export WI_MAX_RETRIES="${WI_MAX_RETRIES:-3}"

# Timeout for gcloud authentication (seconds)
# Default: 30 (check gcloud token expiration)
# Increase if corp proxy slows down gcloud calls
export WI_AUTH_TIMEOUT="${WI_AUTH_TIMEOUT:-30}"

# Enable verbose logging (1=yes, 0=no)
# Default: 0 (only errors and important info)
# Set to 1 for detailed debugging in production incidents
export WI_VERBOSE="${WI_VERBOSE:-0}"

# Enable dry-run mode (1=yes, 0=no) 
# Default: 0 (execute all operations)
# Set to 1 to preview changes without applying them
export WI_DRY_RUN="${WI_DRY_RUN:-0}"

# CSV field separator (should not change unless legacy compatibility needed)
# Default: comma (,)
# Some environments may need semicolon (;) for different locale settings
export WI_CSV_SEPARATOR="${WI_CSV_SEPARATOR:-,}"

# Color coding for terminal output (1=enabled, 0=disabled)
# Default: 1 (use colors for better readability)
# Set to 0 for automation/CI where colors cause issues
export WI_USE_COLORS="${WI_USE_COLORS:-1}"

# Email domain for service account creation if only name provided
# Default: gserviceaccount.com (GCP standard)
# Corporate GCP instances may use different domain
export WI_SA_DOMAIN="${WI_SA_DOMAIN:-gserviceaccount.com}"

# =============================================================================
# Phase 4: Security & Backup Settings
# =============================================================================

# Encrypt the registry CSV with AES-256-CBC (1=yes, 0=no)
# Default: 0 (plaintext CSV, chmod 600)
# Set to 1 to store registry as workload-identity-registry.csv.enc
# Requires WI_REGISTRY_PASSPHRASE to be set in the environment
export WI_ENCRYPT_REGISTRY="${WI_ENCRYPT_REGISTRY:-0}"

# Passphrase for AES-256-CBC registry encryption
# Default: empty (encryption disabled when empty)
# NEVER store the passphrase in this file — set it in the shell environment:
#   export WI_REGISTRY_PASSPHRASE="your-strong-passphrase"
export WI_REGISTRY_PASSPHRASE="${WI_REGISTRY_PASSPHRASE:-}"

# Directory for automatic backups of the registry
# Default: <script_dir>/backups/
# Backups are named: workload-identity-registry_YYYYMMDD_HHMMSS.csv[.enc]
export WI_BACKUP_DIR="${WI_BACKUP_DIR:-}"

# Maximum number of local backups to keep (older ones are automatically pruned)
# Default: 10
export WI_BACKUP_MAX="${WI_BACKUP_MAX:-10}"

# GCS bucket for remote state synchronization (optional)
# Default: empty (no remote sync)
# Format: gs://your-bucket/path  (do NOT include trailing slash)
# Example: gs://gnp-wi-state/workload-identity
export WI_GCS_BUCKET="${WI_GCS_BUCKET:-}"

# =============================================================================
# End of Configuration File
# =============================================================================
# NOTE: All variables are optional and have reasonable defaults.
#       Only override values that don't match your environment.
# =============================================================================
