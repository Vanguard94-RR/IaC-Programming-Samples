#!/bin/bash
# CTASK0365585 - Execution (Create PSC Endpoint)
set +e

source "$(dirname "$0")/config.env"
LOG_FILE="/tmp/ctask0365585-execute.log"

PASSED=0
FAILED=0

echo "========================================" | tee "${LOG_FILE}"
echo "CTASK0365585 - Execution" | tee -a "${LOG_FILE}"
echo "========================================" | tee -a "${LOG_FILE}"

# STEP 1: Create static IP address for PSC (Global with purpose)
echo -e "\n[STEP 1/2] Creating PSC address ${IP_ADDRESS_NAME}..." | tee -a "${LOG_FILE}"
if gcloud compute addresses create "${IP_ADDRESS_NAME}" \
  --global \
  --addresses="${PSC_IP_ADDRESS}" \
  --purpose=PRIVATE_SERVICE_CONNECT \
  --network="${NETWORK_NAME}" \
  --project="${PROJECT_ID}" \
  --quiet 2>&1 | tee -a "${LOG_FILE}"; then
  echo "  ✓ PSC address created" | tee -a "${LOG_FILE}"
  ((PASSED++))
  
  # Get the allocated IP address
  ALLOCATED_IP=$(gcloud compute addresses describe "${IP_ADDRESS_NAME}" \
    --global \
    --project="${PROJECT_ID}" \
    --format='value(address)' 2>/dev/null)
  echo "  ℹ Allocated IP: ${ALLOCATED_IP}" | tee -a "${LOG_FILE}"
else
  echo "  ✗ FAILED: Could not create PSC address" | tee -a "${LOG_FILE}"
  ((FAILED++))
fi

# STEP 2: Create forwarding rule to bind PSC address to service attachment
echo -e "\n[STEP 2/2] Creating PSC forwarding rule..." | tee -a "${LOG_FILE}"
if gcloud compute forwarding-rules create "${IP_ADDRESS_NAME}" \
  --region="${REGION}" \
  --address="${IP_ADDRESS_NAME}" \
  --network="${NETWORK_NAME}" \
  --target-service-attachment="${TARGET_SERVICE_ATTACHMENT}" \
  --target-service-attachment-region="${REGION}" \
  --project="${PROJECT_ID}" \
  --quiet 2>&1 | tee -a "${LOG_FILE}"; then
  echo "  ✓ PSC forwarding rule created" | tee -a "${LOG_FILE}"
  ((PASSED++))
else
  echo "  ✗ FAILED: Could not create PSC forwarding rule" | tee -a "${LOG_FILE}"
  ((FAILED++))
fi

echo -e "\n========================================" | tee -a "${LOG_FILE}"
echo "Execution Result: ${PASSED}/2 completed" | tee -a "${LOG_FILE}"
echo "========================================" | tee -a "${LOG_FILE}"

if [ "${FAILED}" -gt 0 ]; then
  echo -e "\n⚠ Execution had failures"
  exit 1
fi
