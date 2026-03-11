#!/bin/bash

# enable-cors.sh - Enable CORS on a GCP Cloud Storage bucket with security validation
# Usage: ./enable-cors.sh --project <PROJECT_ID> --bucket <BUCKET_NAME> [--config <CONFIG_FILE>] [--force]

set -e

PROJECT_ID=""
BUCKET_NAME=""
CONFIG_FILE="cors-template-secure-restricted.json"
FORCE_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --project)
      PROJECT_ID="$2"
      shift 2
      ;;
    --bucket)
      BUCKET_NAME="$2"
      shift 2
      ;;
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --force)
      FORCE_MODE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate arguments
if [ -z "$PROJECT_ID" ] || [ -z "$BUCKET_NAME" ]; then
  echo "Usage: $0 --project <PROJECT_ID> --bucket <BUCKET_NAME> [--config <CONFIG_FILE>] [--force]"
  exit 1
fi

echo "========================================"
echo "Enable CORS on Cloud Storage Bucket"
echo "========================================"
echo "Project: $PROJECT_ID"
echo "Bucket: gs://$BUCKET_NAME"
echo "Config: $CONFIG_FILE"
echo ""

# Set project
echo "Setting project..."
gcloud config set project "$PROJECT_ID"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Config file not found: $CONFIG_FILE"
  exit 1
fi

# Validate CORS security BEFORE applying
echo ""
echo "🔍 Performing security validation..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if bash "$SCRIPT_DIR/validate-cors-security.sh" --config "$CONFIG_FILE"; then
  echo "✅ Security validation PASSED"
else
  echo "❌ Security validation FAILED"
  if [ "$FORCE_MODE" = true ]; then
    echo "⚠️  FORCING deployment (--force flag used)"
  else
    echo ""
    echo "Use --force flag to override security checks (not recommended)"
    exit 1
  fi
fi

# Check if bucket exists
echo ""
echo "Verifying bucket exists..."
if ! gcloud storage buckets describe "gs://$BUCKET_NAME" &>/dev/null; then
  echo "Error: Bucket not found: gs://$BUCKET_NAME"
  exit 1
fi

# Get current CORS configuration to backup
echo "Backing up current CORS configuration..."
mkdir -p backups
BACKUP_FILE="backups/cors-backup-$(date +%Y%m%d-%H%M%S).json"
gsutil cors get "gs://$BUCKET_NAME" > "$BACKUP_FILE" 2>/dev/null || echo "[]" > "$BACKUP_FILE"
echo "Backup saved to: $BACKUP_FILE"

# Show what will be applied
echo ""
echo "📋 Configuration to be applied:"
echo "---"
cat "$CONFIG_FILE"
echo "---"
echo ""

# Confirm before applying
read -p "Apply this CORS configuration? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Cancelled by user"
  exit 0
fi

# Apply CORS configuration
echo ""
echo "Applying CORS configuration..."
if gsutil cors set "$CONFIG_FILE" "gs://$BUCKET_NAME"; then
  echo "✅ CORS configuration applied successfully"
else
  echo "❌ Failed to apply CORS configuration"
  exit 1
fi

# Verify CORS configuration was applied
echo ""
echo "Verifying CORS configuration..."
APPLIED_CONFIG=$(gsutil cors get "gs://$BUCKET_NAME")

if [ "$APPLIED_CONFIG" = "[]" ] || [ -z "$APPLIED_CONFIG" ]; then
  echo "❌ WARNING: CORS configuration appears empty after application"
  exit 1
fi

echo "✅ Current CORS configuration on bucket:"
echo "$APPLIED_CONFIG" | jq '.'

# Log the change
echo ""
echo "📝 Audit Log Entry:"
{
  echo "Timestamp: $(date -Iseconds)"
  echo "Action: CORS_ENABLED"
  echo "Project: $PROJECT_ID"
  echo "Bucket: $BUCKET_NAME"
  echo "Config: $CONFIG_FILE"
  echo "Applied By: $USER"
  echo "---"
  echo "Configuration:"
  cat "$CONFIG_FILE"
} | tee -a "cors-audit-$(date +%Y%m).log"

echo ""
echo "✅ CORS successfully enabled on gs://$BUCKET_NAME"
echo "Backup available at: $BACKUP_FILE"
