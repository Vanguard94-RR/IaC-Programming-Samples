#!/bin/bash

# enable-cors.sh - Enable CORS on a GCP Cloud Storage bucket
# Usage: ./enable-cors.sh --project <PROJECT_ID> --bucket <BUCKET_NAME> [--config <CONFIG_FILE>]

set -e

PROJECT_ID=""
BUCKET_NAME=""
CONFIG_FILE="cors-template-open.json"

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
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate arguments
if [ -z "$PROJECT_ID" ] || [ -z "$BUCKET_NAME" ]; then
  echo "Usage: $0 --project <PROJECT_ID> --bucket <BUCKET_NAME> [--config <CONFIG_FILE>]"
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

# Apply CORS configuration
echo "Applying CORS configuration..."
gsutil cors set "$CONFIG_FILE" "gs://$BUCKET_NAME"

# Verify CORS configuration
echo ""
echo "Verifying CORS configuration..."
gsutil cors get "gs://$BUCKET_NAME"

echo ""
echo "✓ CORS successfully enabled on gs://$BUCKET_NAME"
