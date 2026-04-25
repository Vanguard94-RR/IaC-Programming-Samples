#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"
VPC_NAME=""
SUBNET_NAME=""
IS_SHARED_VPC="false"
get_node_subnet_cidr() { echo "${1%/*}/26"; }
calculate_secondary_ranges() { echo "servicios=10.0.0.64/26,pods=10.0.0.128/25"; }
validate_secondary_ranges() { warn "[STUB] validate_secondary_ranges"; }
cmd_vpc_select() { warn "[STUB] vpc_select not yet implemented"; VPC_NAME="stub-vpc"; SUBNET_NAME="stub-subnet"; PODS_RANGE_NAME="pods"; SERVICES_RANGE_NAME="servicios"; }
