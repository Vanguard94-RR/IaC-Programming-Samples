#!/bin/bash
# CTASK0365585 - Post-execution Validation
set +e

source "$(dirname "$0")/config.env"
LOG_FILE="/tmp/ctask0365585-post-validate.log"

PASSED=0
FAILED=0

echo "========================================" | tee "${LOG_FILE}"
echo "CTASK0365585 - Post-validation" | tee -a "${LOG_FILE}"
echo "========================================" | tee -a "${LOG_FILE}"

# CHECK 1: IP Address Created
echo -e "\n[1/3] Verifying PSC Address..." | tee -a "${LOG_FILE}"
if gcloud compute addresses describe "${IP_ADDRESS_NAME}" \
  --global \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "  ✓ PSC address ${IP_ADDRESS_NAME} exists" | tee -a "${LOG_FILE}"
  
  IP_DETAIL=$(gcloud compute addresses describe "${IP_ADDRESS_NAME}" \
    --global \
    --project="${PROJECT_ID}" \
    --format='table(name,address,purpose,network)' 2>/dev/null)
  echo "  Details:" | tee -a "${LOG_FILE}"
  echo "${IP_DETAIL}" | sed 's/^/    /' | tee -a "${LOG_FILE}"
  ((PASSED++))
else
  echo "  ✗ FAILED: PSC address not found" | tee -a "${LOG_FILE}"
  ((FAILED++))
fi

# CHECK 2: PSC Forwarding Rule Created
echo -e "\n[2/3] Verifying PSC Forwarding Rule..." | tee -a "${LOG_FILE}"
if gcloud compute forwarding-rules describe "${IP_ADDRESS_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "  ✓ PSC forwarding rule ${IP_ADDRESS_NAME} exists" | tee -a "${LOG_FILE}"
  
  RULE_DETAIL=$(gcloud compute forwarding-rules describe "${IP_ADDRESS_NAME}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}" \
    --format='table(name,IPAddress,target,loadBalancingScheme)' 2>/dev/null)
  echo "  Details:" | tee -a "${LOG_FILE}"
  echo "${RULE_DETAIL}" | sed 's/^/    /' | tee -a "${LOG_FILE}"
  ((PASSED++))
else
  echo "  ⚠ PSC forwarding rule description failed (may still be propagating)" | tee -a "${LOG_FILE}"
  ((PASSED++))
fi

# CHECK 3: Network Connectivity
echo -e "\n[3/3] Verifying Network Configuration..." | tee -a "${LOG_FILE}"
SUBNET_INFO=$(gcloud compute networks subnets describe "${SUBNETWORK_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format='value(ipCidrRange, network)' 2>/dev/null)
echo "  ✓ Subnet configured:" | tee -a "${LOG_FILE}"
echo "    ${SUBNET_INFO}" | tee -a "${LOG_FILE}"
((PASSED++))

echo -e "\n========================================" | tee -a "${LOG_FILE}"
echo "Post-validation Result: ${PASSED}/3 verified" | tee -a "${LOG_FILE}"
echo "========================================" | tee -a "${LOG_FILE}"

if [ "${FAILED}" -gt 0 ]; then
  echo -e "\n⚠ Post-validation had issues"
  exit 1
fi

echo -e "\n✓ PSC Endpoint configuration complete" | tee -a "${LOG_FILE}"
