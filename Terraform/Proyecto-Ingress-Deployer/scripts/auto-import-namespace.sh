#!/usr/bin/env bash
set -euo pipefail

# Get the base directory (project root), not the scripts directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$PROJECT_ROOT/scripts"
source "$PROJECT_ROOT/lib/path_helper.sh"
_load_gnp_environment

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

step() {
    echo -e "${YELLOW}[*]${NC} $*"
}

ok() {
    echo -e "${GREEN}[✓]${NC} $*"
}

error() {
    echo -e "${RED}[✗]${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[!]${NC} $*"
}

# Usage
if [[ $# -lt 3 ]]; then
    error "Usage: $0 <namespace> <terraform-dir> <tfvars-file>"
    echo "  Example: $0 ingress-ns ./terraform ./environments/project.tfvars"
    exit 1
fi

NAMESPACE="$1"
TF_DIR="$2"
TFVARS_FILE="$3"

# Convert to absolute paths
TF_DIR="$(cd "$TF_DIR" && pwd)"
TFVARS_FILE="$(cd "$(dirname "$TFVARS_FILE")" && pwd)/$(basename "$TFVARS_FILE")"

# Validate tfvars file exists
if [[ ! -f "$TFVARS_FILE" ]]; then
    error "tfvars file not found: $TFVARS_FILE"
    exit 1
fi

# Validate kubectl is available
_require_command kubectl "kubectl not found. Please install kubectl first."

# Check if namespace exists in cluster
step "Checking if namespace '$NAMESPACE' exists in cluster..."
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    ok "Namespace '$NAMESPACE' exists in cluster"
    
    # Check if it's already in Terraform state
    step "Checking if namespace is already in Terraform state..."
    cd "$TF_DIR"
    
    # Check for both possible resource addresses
    if terraform state show "module.ingress.kubernetes_namespace_v1.ingress" &>/dev/null; then
        ok "Namespace already in Terraform state, skipping import"
        exit 0
    fi
    
    # Import the namespace into Terraform state with full module path and tfvars
    step "Importing namespace into Terraform state..."
    
    if terraform import \
        -var-file="$TFVARS_FILE" \
        "module.ingress.kubernetes_namespace_v1.ingress" \
        "$NAMESPACE" 2>&1; then
        
        # Verify import was successful
        if terraform state show "module.ingress.kubernetes_namespace_v1.ingress" &>/dev/null; then
            ok "Successfully imported namespace '$NAMESPACE' into Terraform state"
            exit 0
        else
            error "Import command completed but namespace not found in state"
            exit 1
        fi
    else
        error "Failed to import namespace"
        exit 1
    fi
else
    step "Namespace '$NAMESPACE' does not exist in cluster"
    step "Terraform will create it during 'terraform apply'"
fi

exit 0


