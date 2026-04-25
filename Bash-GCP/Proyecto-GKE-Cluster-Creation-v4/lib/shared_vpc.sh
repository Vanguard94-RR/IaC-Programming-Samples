#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"
SHARED_HOST=""
IS_SHARED_VPC="false"
PODS_RANGE_NAME=""
SERVICES_RANGE_NAME=""
cmd_fix_shared_vpc() { warn "[STUB] fix-shared-vpc not yet implemented"; }
configure_shared_vpc_permissions() { warn "[STUB] configure_shared_vpc_permissions not yet implemented"; }
detect_secondary_ranges() { warn "[STUB] detect_secondary_ranges not yet implemented"; PODS_RANGE_NAME="pods"; SERVICES_RANGE_NAME="servicios"; }
