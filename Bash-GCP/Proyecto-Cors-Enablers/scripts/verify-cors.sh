#!/bin/bash

# verify-cors.sh - Verify CORS configuration on a GCP Cloud Storage bucket
# Usage: ./verify-cors.sh --project <PROJECT_ID> --bucket <BUCKET_NAME>

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
echo "Verify CORS Configuration"
echo "========================================"
echo "Project: $PROJECT_ID"
echo "Bucket: gs://$BUCKET_NAME"
echo ""

# Set project
gcloud config set project "$PROJECT_ID"

# Get CORS configuration
echo "Current CORS configuration:"
echo ""
gsutil cors get "gs://$BUCKET_NAME"

echo ""
echo "✓ CORS verification complete"
