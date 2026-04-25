#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"
cmd_update_armor() { warn "[STUB] update-armor not yet implemented"; }
cmd_rollback_armor() { warn "[STUB] rollback-armor not yet implemented"; }
apply_cluster_hardening() { warn "[STUB] apply_cluster_hardening not yet implemented"; }
