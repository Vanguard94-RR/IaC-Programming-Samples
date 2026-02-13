#!/bin/bash

# disable-cors.sh - Disable CORS on a GCP Cloud Storage bucket
# Usage: ./disable-cors.sh --project <PROJECT_ID> --bucket <BUCKET_NAME>

set -e

PROJECT_ID=""
BUCKET_NAME=""

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
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate arguments
if [ -z "$PROJECT_ID" ] || [ -z "$BUCKET_NAME" ]; then
  echo "Usage: $0 --project <PROJECT_ID> --bucket <BUCKET_NAME>"
  exit 1
fi

echo "========================================"
echo "Disable CORS on Cloud Storage Bucket"
echo "========================================"
echo "Project: $PROJECT_ID"
echo "Bucket: gs://$BUCKET_NAME"
echo ""

# Set project
gcloud config set project "$PROJECT_ID"

# Create empty CORS configuration
EMPTY_CORS='[]'
TEMP_FILE=$(mktemp)
echo "$EMPTY_CORS" > "$TEMP_FILE"

# Apply empty CORS configuration to disable
echo "Disabling CORS configuration..."
gsutil cors set "$TEMP_FILE" "gs://$BUCKET_NAME"

# Clean up
rm "$TEMP_FILE"

echo ""
echo "✓ CORS successfully disabled on gs://$BUCKET_NAME"
