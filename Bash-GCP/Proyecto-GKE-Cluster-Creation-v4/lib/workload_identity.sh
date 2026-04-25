#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"
create_workload_identity_assets() { warn "[STUB] workload_identity not yet implemented"; }
