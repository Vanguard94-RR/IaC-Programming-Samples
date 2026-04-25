#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"
project_id=""
cluster_name=""
region=""
zone=""
machine_type=""
num_nodes=""
channel=""
fleet_id=""
cluster_version=""
cluster_access_scope=""
private_nodes=""
control_plane_ip=""
get_cluster_versions() { echo "1.31.0-gke.1000000"; }
register_fleet() { warn "[STUB] register_fleet not yet implemented"; }
cmd_create() { warn "[STUB] create not yet implemented"; }
