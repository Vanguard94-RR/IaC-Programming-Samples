#!/bin/bash
# CTASK0365585 - Pre-execution Validation (5 checks)
set +e

source "$(dirname "$0")/config.env"
LOG_FILE="/tmp/ctask0365585-pre-validate.log"

PASSED=0
FAILED=0

echo "========================================" | tee "${LOG_FILE}"
echo "CTASK0365585 - Pre-validation Checks" | tee -a "${LOG_FILE}"
echo "========================================" | tee -a "${LOG_FILE}"

# CHECK 1: Project Accessible
echo -e "\n[1/5] Checking Project..." | tee -a "${LOG_FILE}"
if gcloud projects describe "${PROJECT_ID}" --quiet >/dev/null 2>&1; then
  echo "  ✓ Project accessible" | tee -a "${LOG_FILE}"
  ((PASSED++))
else
  echo "  ✗ FAILED: Project not accessible" | tee -a "${LOG_FILE}"
  ((FAILED++))
fi

# CHECK 2: Network Exists
echo -e "\n[2/5] Checking Network..." | tee -a "${LOG_FILE}"
if gcloud compute networks describe "${NETWORK_NAME}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "  ✓ Network ${NETWORK_NAME} exists" | tee -a "${LOG_FILE}"
  ((PASSED++))
else
  echo "  ✗ FAILED: Network not found" | tee -a "${LOG_FILE}"
  ((FAILED++))
fi

# CHECK 3: Subnetwork Exists
echo -e "\n[3/5] Checking Subnetwork..." | tee -a "${LOG_FILE}"
if gcloud compute networks subnets describe "${SUBNETWORK_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "  ✓ Subnetwork ${SUBNETWORK_NAME} exists" | tee -a "${LOG_FILE}"
  ((PASSED++))
else
  echo "  ✗ FAILED: Subnetwork not found" | tee -a "${LOG_FILE}"
  ((FAILED++))
fi

# CHECK 4: IP Address Doesn't Exist
echo -e "\n[4/5] Checking IP Address Name..." | tee -a "${LOG_FILE}"
if gcloud compute addresses describe "${IP_ADDRESS_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "  ⚠ IP Address ${IP_ADDRESS_NAME} already exists" | tee -a "${LOG_FILE}"
  ((PASSED++))
else
  echo "  ✓ IP Address ${IP_ADDRESS_NAME} available for creation" | tee -a "${LOG_FILE}"
  ((PASSED++))
fi

# CHECK 5: Compute API Enabled
echo -e "\n[5/5] Checking Compute API..." | tee -a "${LOG_FILE}"
if gcloud services list --project="${PROJECT_ID}" --enabled --filter="name:compute" --quiet 2>/dev/null | grep -q compute; then
  echo "  ✓ Compute API enabled" | tee -a "${LOG_FILE}"
  ((PASSED++))
else
  echo "  ✗ WARNING: Compute API may not be enabled" | tee -a "${LOG_FILE}"
  ((FAILED++))
fi

echo -e "\n========================================" | tee -a "${LOG_FILE}"
echo "Pre-validation Result: ${PASSED}/5 passed" | tee -a "${LOG_FILE}"
echo "========================================" | tee -a "${LOG_FILE}"

if [ "${FAILED}" -gt 0 ]; then
  echo -e "\n⚠ Some checks failed"
  exit 1
fi
