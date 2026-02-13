#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Thin wrapper: keep variable declarations and source smaller kube modules
# The file intentionally declares globals that are referenced by the
# smaller kube_* modules. Silence the "unused variable" ShellCheck warning
# for this file.
# shellcheck disable=SC2034
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ui.sh"

PROJECT_ID=""
CLUSTER_NAME=""
CLUSTER_ZONE=""
INGRESS_NAME=""
NAMESPACE=""
BACKUP_FILE=""
CLEAN_FILE=""
BACKUP_DIR="."

# Source modular kube helpers
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/kube_select.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/kube_backup.sh"
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/kube_compare_apply.sh"

# Utilities
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

:
