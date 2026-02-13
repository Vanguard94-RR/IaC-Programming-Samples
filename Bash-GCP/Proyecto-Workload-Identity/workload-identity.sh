#!/bin/bash
# =============================================================================
# Workload Identity Manager for GCP/GKE
# Configure GCP Workload Identity between GCP SA and Kubernetes SA
# 
# Project: GCP Infrastructure Management
# Version: 2.0.0
# Author: Infrastructure Team
# License: Internal Use
#
# Features:
#   - Interactive menu system with colored output
#   - Automatic ticket-based log organization
#   - CSV registry of all operations with status tracking
#   - Robust error handling and validation
#   - Support for batch operations
#
# Usage:
#   ./workload-identity.sh              # Run interactive menu
#   ./workload-identity.sh --help       # Show help
#   ./workload-identity.sh --version    # Show version
# =============================================================================

# Script safety settings
set -euo pipefail
IFS=$'\n\t'

# Metadata
readonly G_VERSION="2.0.0"
readonly G_SCRIPT_NAME="Workload Identity Manager"
readonly G_SCRIPT_DESC="Configure GCP Workload Identity between GCP SA and Kubernetes SA"

# Trap errors and cleanup
trap 'handle_error $? $LINENO' ERR
handle_error() {
    local exit_code=$1
    local line_no=$2
    echo -e "\n${RED}✗ Error at line $line_no (exit code: $exit_code)${NC}" >&2
    exit "$exit_code"
}

# --- Colors for terminal output ---
LGREEN='\033[1;32m'
LCYAN='\033[1;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
RED='\033[0;31m'
GRAY='\033[0;37m'
NC='\033[0m'

# --- Global Variables (prefixed with G_) ---
readonly G_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly G_BASE_DIR="$(dirname "$G_SCRIPT_DIR")"
readonly G_TICKETS_DIR="$G_BASE_DIR/Tickets"
readonly G_CONTROL_FILE="$G_SCRIPT_DIR/workload-identity-registry.csv"
readonly G_TEMP_DIR="/tmp/workload-identity-$$"

G_LOG_DIR=""
G_LOG_FILE=""
G_TICKET_ID=""
G_PROJECT_ID=""
G_CLUSTER_NAME=""
G_NAMESPACE="apps"

# Cleanup on exit
trap 'cleanup' EXIT
cleanup() {
    rm -rf "$G_TEMP_DIR" 2>/dev/null || true
}
mkdir -p "$G_TEMP_DIR"

# --- Initialize and secure control file ---
init_control_file() {
    if [[ ! -f "$G_CONTROL_FILE" ]]; then
        echo "Fecha,Ticket,ProjectId,Cluster,Location,Namespace,KSA,IAM_SA,Status" > "$G_CONTROL_FILE"
    fi
    
    # Secure file permissions (sensitive data)
    chmod 600 "$G_CONTROL_FILE" 2>/dev/null || true
    
    # Migrate old format if needed
    if [[ -f "$G_CONTROL_FILE" ]]; then
        local header
        header=$(head -1 "$G_CONTROL_FILE" 2>/dev/null || echo "")
        if [[ -n "$header" && ! "$header" =~ "Status" ]]; then
            sed -i '1s/$/,Status/' "$G_CONTROL_FILE"
            sed -i '2,$s/$/,activo/' "$G_CONTROL_FILE"
            chmod 600 "$G_CONTROL_FILE"
        fi
    fi
}

# --- Register execution in control file ---
register_execution() {
    local ticket="$1"
    local project="$2"
    local cluster="$3"
    local location="$4"
    local namespace="$5"
    local ksa="$6"
    local iam_sa="$7"
    local status="${8:-activo}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Use "-" if no ticket
    [[ -z "$ticket" ]] && ticket="-"
    
    echo "${timestamp},${ticket},${project},${cluster},${location},${namespace},${ksa},${iam_sa},${status}" >> "$G_CONTROL_FILE"
}

# --- Update registry status (optimized with awk) ---
update_registry_status() {
    local project="$1"
    local cluster="$2"
    local namespace="$3"
    local ksa="$4"
    local new_status="$5"
    
    [[ ! -f "$G_CONTROL_FILE" ]] && return 1
    
    # Use awk for efficient single-pass update
    local temp_file
    temp_file=$(mktemp --tmpdir="$G_TEMP_DIR")
    
    awk -F',' -v p="$project" -v c="$cluster" -v ns="$namespace" -v k="$ksa" -v s="$new_status" '
        BEGIN { OFS="," }
        NR==1 { print; next }
        $3==p && $4==c && $6==ns && $7==k { $9=s }
        { print }
    ' "$G_CONTROL_FILE" > "$temp_file"
    
    mv "$temp_file" "$G_CONTROL_FILE"
    chmod 600 "$G_CONTROL_FILE"
}

# --- Setup log directory (called after ticket input) ---
setup_log_directory() {
    local ticket="$1"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    if [[ -n "$ticket" ]]; then
        # Create ticket folder structure
        G_LOG_DIR="$G_TICKETS_DIR/$ticket/logs"
        mkdir -p "$G_LOG_DIR" 2>/dev/null || {
            echo -e "${RED}✗ Failed to create log directory: $G_LOG_DIR${NC}" >&2
            return 1
        }
        G_LOG_FILE="$G_LOG_DIR/workload_identity_${timestamp}.log"
        
        # Create additional folders for ticket
        mkdir -p "$G_TICKETS_DIR/$ticket/docs" 2>/dev/null || true
        mkdir -p "$G_TICKETS_DIR/$ticket/scripts" 2>/dev/null || true
    else
        # Use default logs folder
        G_LOG_DIR="$G_SCRIPT_DIR/logs"
        mkdir -p "$G_LOG_DIR" 2>/dev/null || {
            echo -e "${RED}✗ Failed to create log directory: $G_LOG_DIR${NC}" >&2
            return 1
        }
        G_LOG_FILE="$G_LOG_DIR/workload_identity_${timestamp}.log"
    fi
    
    # Initialize log file with header
    {
        echo "===================================="
        echo "Workload Identity Manager - Execution Log"
        echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "===================================="
        echo ""
    } > "$G_LOG_FILE"
    
    return 0
}

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    local message="$1"
    # Only log if LOG_FILE is set
    [[ -z "$G_LOG_FILE" ]] && return 0
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$G_LOG_FILE"
}

log_and_print() {
    local message="$1"
    local color="${2:-$NC}"
    echo -e "${color}${message}${NC}"
    log "$message"
}

print_header() {
    echo -e "${LGREEN}========================================${NC}"
    echo -e "${LGREEN} $1${NC}"
    echo -e "${LGREEN}========================================${NC}"
    log "========================================"
    log " $1"
    log "========================================"
}

print_info() {
    local label="$1"
    local value="$2"
    echo -e "${WHITE}${label}:${NC} ${LCYAN}${value}${NC}"
    log "${label}: ${value}"
}

print_success() {
    echo -e "${LGREEN}✓ $1${NC}"
    log "✓ $1"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
    log "✗ $1"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
    log "⚠ $1"
}

# =============================================================================
# Input Functions
# =============================================================================

prompt_input() {
    local prompt_text="$1"
    local variable_name="$2"
    local default_value="${3:-}"
    
    if [[ -n "$default_value" ]]; then
        echo -ne "${YELLOW}${prompt_text} [${default_value}]: ${NC}"
    else
        echo -ne "${YELLOW}${prompt_text}: ${NC}"
    fi
    
    read input_value
    
    if [[ -z "$input_value" ]] && [[ -n "$default_value" ]]; then
        input_value="$default_value"
    fi
    
    eval "$variable_name='$input_value'"
    log "Input - ${prompt_text}: ${input_value}"
}

prompt_selection() {
    local prompt_text="$1"
    local options_var="$2"
    local result_var="$3"
    
    local -n options="$options_var"
    local count=${#options[@]}
    
    echo -e "${WHITE}${prompt_text}${NC}"
    echo ""
    
    for i in "${!options[@]}"; do
        echo -e "  ${LCYAN}$((i+1)))${NC} ${options[$i]}"
    done
    
    echo ""
    echo -ne "${YELLOW}Select an option [1-${count}]: ${NC}"
    read selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$count" ]]; then
        eval "$result_var='${options[$((selection-1))]}'"
        log "Selection - ${prompt_text}: ${options[$((selection-1))]}"
        return 0
    else
        print_error "Invalid selection"
        return 1
    fi
}

# =============================================================================
# GCP Functions
# =============================================================================

get_current_project() {
    gcloud config get-value project 2>/dev/null
}

list_gke_clusters() {
    local project_id="$1"
    gcloud container clusters list --project "$project_id" --format="value(name,location)" 2>/dev/null
}

# =============================================================================
# Validation Functions
# =============================================================================

# Validate GCP project ID format and existence
validate_project_id() {
    local project="$1"
    
    if [[ ! "$project" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]]; then
        echo -e "${RED}✗ Invalid project ID format: $project${NC}" >&2
        return 1
    fi
    
    if ! gcloud projects describe "$project" &>/dev/null; then
        echo -e "${RED}✗ Project not found or you lack permissions: $project${NC}" >&2
        return 1
    fi
    return 0
}

# Validate IAM SA email format
validate_iam_sa_email() {
    local email="$1"
    
    if [[ ! "$email" =~ ^[a-z0-9-]+@[a-z0-9-]+\.iam\.gserviceaccount\.com$ ]]; then
        echo -e "${RED}✗ Invalid IAM Service Account email: $email${NC}" >&2
        return 1
    fi
    return 0
}

# Validate Kubernetes name format (DNS-1123 subdomain)
validate_k8s_name() {
    local name="$1"
    local context="$2"  # For error message
    
    if [[ ! "$name" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || (( ${#name} > 63 )); then
        echo -e "${RED}✗ Invalid $context name: $name (must be lowercase alphanumeric with hyphens, max 63 chars)${NC}" >&2
        return 1
    fi
    return 0
}

# Validate namespace exists
validate_namespace() {
    local namespace="$1"
    
    if ! kubectl get namespace "$namespace" &>/dev/null; then
        echo -e "${RED}✗ Namespace not found: $namespace${NC}" >&2
        return 1
    fi
    return 0
}

connect_to_cluster() {
    local cluster_name="$1"
    local location="$2"
    local project_id="$3"
    
    log "Connecting to cluster: $cluster_name in $location"
    
    # Determine if regional or zonal
    if [[ "$location" =~ ^[a-z]+-[a-z]+[0-9]+$ ]]; then
        # Regional (e.g., us-central1)
        if [[ -n "$G_LOG_FILE" ]]; then
            gcloud container clusters get-credentials "$cluster_name" \
                --region "$location" \
                --project "$project_id" 2>&1 | tee -a "$G_LOG_FILE"
        else
            gcloud container clusters get-credentials "$cluster_name" \
                --region "$location" \
                --project "$project_id" &>/dev/null
        fi
    else
        # Zonal (e.g., us-central1-a)
        if [[ -n "$G_LOG_FILE" ]]; then
            gcloud container clusters get-credentials "$cluster_name" \
                --zone "$location" \
                --project "$project_id" 2>&1 | tee -a "$G_LOG_FILE"
        else
            gcloud container clusters get-credentials "$cluster_name" \
                --zone "$location" \
                --project "$project_id" &>/dev/null
        fi
    fi
}

verify_iam_sa() {
    local sa_email="$1"
    local project_id="$2"
    
    gcloud iam service-accounts describe "$sa_email" --project "$project_id" &>/dev/null
}

create_iam_sa() {
    local sa_name="$1"
    local project_id="$2"
    local display_name="${3:-$sa_name}"
    
    gcloud iam service-accounts create "$sa_name" \
        --project "$project_id" \
        --display-name "$display_name" 2>&1 | tee -a "$G_LOG_FILE"
}

create_namespace() {
    local namespace="$1"
    
    if kubectl get namespace "$namespace" &>/dev/null; then
        log "Namespace $namespace already exists"
        return 0
    fi
    
    kubectl create namespace "$namespace" 2>&1 | tee -a "$G_LOG_FILE"
}

create_ksa() {
    local ksa_name="$1"
    local namespace="$2"
    
    if kubectl get serviceaccount "$ksa_name" -n "$namespace" &>/dev/null; then
        log "KSA $ksa_name already exists in $namespace"
        return 0
    fi
    
    kubectl create serviceaccount "$ksa_name" -n "$namespace" 2>&1 | tee -a "$G_LOG_FILE"
}

add_iam_binding() {
    local iam_sa_email="$1"
    local project_id="$2"
    local ksa_name="$3"
    local namespace="$4"
    
    local member="serviceAccount:${project_id}.svc.id.goog[${namespace}/${ksa_name}]"
    
    gcloud iam service-accounts add-iam-policy-binding "$iam_sa_email" \
        --project "$project_id" \
        --role "roles/iam.workloadIdentityUser" \
        --member "$member" 2>&1 | tee -a "$G_LOG_FILE"
}

annotate_ksa() {
    local ksa_name="$1"
    local namespace="$2"
    local iam_sa_email="$3"
    
    kubectl annotate serviceaccount "$ksa_name" \
        --namespace "$namespace" \
        "iam.gke.io/gcp-service-account=${iam_sa_email}" \
        --overwrite 2>&1 | tee -a "$G_LOG_FILE"
}

remove_iam_binding() {
    local iam_sa_email="$1"
    local project_id="$2"
    local ksa_name="$3"
    local namespace="$4"
    
    local member="serviceAccount:${project_id}.svc.id.goog[${namespace}/${ksa_name}]"
    
    gcloud iam service-accounts remove-iam-policy-binding "$iam_sa_email" \
        --project "$project_id" \
        --role "roles/iam.workloadIdentityUser" \
        --member "$member" 2>&1 | tee -a "$G_LOG_FILE"
}

delete_ksa() {
    local ksa_name="$1"
    local namespace="$2"
    
    kubectl delete serviceaccount "$ksa_name" -n "$namespace" 2>&1 | tee -a "$G_LOG_FILE"
}

get_ksa_annotation() {
    local ksa_name="$1"
    local namespace="$2"
    
    kubectl get serviceaccount "$ksa_name" -n "$namespace" \
        -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' 2>/dev/null
}

list_workload_identities() {
    local namespace="$1"
    
    echo -e "${WHITE}Kubernetes Service Accounts with Workload Identity in namespace: ${LCYAN}${namespace}${NC}"
    echo ""
    
    # Get all KSAs in namespace using kubectl
    local ksa_output=$(kubectl get serviceaccounts -n "$namespace" -o json 2>/dev/null)
    
    if [[ -z "$ksa_output" ]]; then
        echo -e "  ${GRAY}No Service Accounts found in namespace${NC}"
        return 0
    fi
    
    local found=false
    
    # Parse JSON output
    echo "$ksa_output" | jq -r '.items[] | "\(.metadata.name)|\(.metadata.annotations["iam.gke.io/gcp-service-account"] // "")"' 2>/dev/null | while IFS='|' read -r ksa annotation; do
        if [[ -z "$ksa" ]]; then
            continue
        fi
        
        if [[ -n "$annotation" ]]; then
            echo -e "  ${LCYAN}•${NC} KSA: ${LGREEN}${ksa}${NC}"
            echo -e "    IAM SA: ${LCYAN}${annotation}${NC}"
            echo ""
        fi
    done
    
    # Count total and show availability
    local total=$(echo "$ksa_output" | jq '.items | length' 2>/dev/null)
    
    # Show all KSAs if none have annotations
    echo "$ksa_output" | jq -r '.items[] | select(.metadata.annotations["iam.gke.io/gcp-service-account"] == null or .metadata.annotations["iam.gke.io/gcp-service-account"] == "") | .metadata.name' 2>/dev/null | while read -r ksa; do
        if [[ -n "$ksa" ]]; then
            found=false
        fi
    done
    
    # If found no configured ones, show all
    if ! echo "$ksa_output" | jq '.items[] | select(.metadata.annotations["iam.gke.io/gcp-service-account"] != null and .metadata.annotations["iam.gke.io/gcp-service-account"] != "")' 2>/dev/null | grep -q .; then
        echo -e "  ${GRAY}✗ No KSAs with Workload Identity annotation${NC}"
        echo ""
        echo -e "${WHITE}Available Service Accounts in namespace (${total}):${NC}"
        echo "$ksa_output" | jq -r '.items[] | .metadata.name' 2>/dev/null | while read -r ksa; do
            if [[ -n "$ksa" ]]; then
                echo -e "  ${YELLOW}•${NC} ${LGREEN}${ksa}${NC}"
            fi
        done
    fi
}

# =============================================================================
# Help and Version Functions
# =============================================================================

show_help() {
    cat << 'HELP_TEXT'

  ╔════════════════════════════════════════════════════════════════╗
  ║        WORKLOAD IDENTITY MANAGER - HELP                       ║
  ╚════════════════════════════════════════════════════════════════╝

  DESCRIPCIÓN:
    Herramienta interactiva para configurar GCP Workload Identity
    entre Service Accounts de GCP y Kubernetes.

  USO:
    ./workload-identity.sh              # Run interactive menu
    ./workload-identity.sh --help       # Show this help
    ./workload-identity.sh --version    # Show version

  MENU OPTIONS:
    1) Configure Workload Identity
       - Creates and configures binding between IAM SA and KSA
       - Records operation in CSV
       - Organizes logs by ticket

    2) Verify Workload Identity
       - Validates IAM SA exists
       - Validates KSA exists
       - Verifies annotation and binding

    3) Delete Workload Identity
       - Shows active configurations
       - Allows selecting deletion level
       - Updates status in registry

    4) List Workload Identities
       - Shows projects from registry
       - Shows available clusters
       - Lists KSAs with Workload Identity

    5) View Operations Registry
       - Shows latest operations
       - Indicates status (active/deleted)

  REQUIREMENTS:
    - gcloud CLI authenticated
    - kubectl configured
    - IAM permissions to create service accounts
    - Access to GKE clusters

  FILES:
    workload-identity-registry.csv    Operations registry
    logs/                             Local logs
    Tickets/[TICKET]/logs/            Logs organized by ticket

  EXAMPLES:
    $ ./workload-identity.sh
    > Select option 1 to configure

  DOCUMENTATION:
    README.md                         Complete documentation

HELP_TEXT
}

show_version() {
    cat << 'VERSION_TEXT'

  ╔════════════════════════════════════════════════════════════════╗
  ║        WORKLOAD IDENTITY MANAGER                               ║
  ╚════════════════════════════════════════════════════════════════╝

  Nombre:          Workload Identity Manager
  Version:         VERSION
  Project:        GCP Infrastructure Management
  Description:     Configure GCP Workload Identity for GKE

  Autor:           Infrastructure Team
  Licencia:        Internal Use
  Repositorio:     IaC-Programming-Samples

  Features:
    ✓ Interactive interface
    ✓ Organization by tickets
    ✓ Registro CSV de operaciones
    ✓ Robust validation
    ✓ Logs estructurados

VERSION_TEXT
    # Reemplazar VERSION con el valor real
    sed "s/VERSION/$G_VERSION/" <<< "$VERSION_TEXT"
}

# =============================================================================
# Menu Functions
# =============================================================================

show_main_menu() {
    clear
    echo -e "${LGREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${LGREEN}║${NC}   ${WHITE}Workload Identity Manager${NC}            ${LGREEN}║${NC}"
    echo -e "${LGREEN}╠════════════════════════════════════════╣${NC}"
    echo -e "${LGREEN}║${NC}                                        ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}1)${NC} Configure Workload Identity        ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}2)${NC} Verify Configuration               ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}3)${NC} Delete Workload Identity           ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}4)${NC} List Bindings in Namespace         ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}5)${NC} View Operations Registry           ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}                                        ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}0)${NC} Exit                               ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}                                        ${LGREEN}║${NC}"
    echo -e "${LGREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -ne "${YELLOW}Select an option: ${NC}"
}

# =============================================================================
# Operation: Setup Workload Identity
# =============================================================================

operation_setup() {
    clear
    print_header "Configure Workload Identity"
    echo ""
    
    # --- Step 0: Ticket/CTask (Optional) ---
    echo -e "${GRAY}  (Optional) Associate with ticket for organizing logs${NC}"
    prompt_input "Ticket or CTASK number (optional, press Enter to skip)" "TICKET_ID" ""
    G_TICKET_ID="$TICKET_ID"
    
    # Setup log directory based on ticket
    setup_log_directory "$G_TICKET_ID"
    
    if [[ -n "$G_TICKET_ID" ]]; then
        echo -e "${LGREEN}✓ Logs will be saved in: ${LCYAN}Tickets/$G_TICKET_ID/logs/${NC}"
    fi
    
    echo ""
    log "Session started - Operation: SETUP"
    [[ -n "$G_TICKET_ID" ]] && log "Ticket/CTask: $G_TICKET_ID"
    
    # --- Step 1: Project ID ---
    local current_project=$(get_current_project)
    prompt_input "Enter Project ID" "project_id" "$current_project"
    
    if [[ -z "$project_id" ]]; then
        print_error "Project ID is required"
        exit 1
    fi
    
    echo ""
    
    # --- Step 2: IAM Service Account ---
    prompt_input "Enter IAM Service Account name (without @...)" "iam_sa_name"
    
    if [[ -z "$iam_sa_name" ]]; then
        print_error "IAM Service Account es requerido"
        exit 1
    fi
    
    # Build full email
    local iam_sa_email="${iam_sa_name}@${project_id}.iam.gserviceaccount.com"
    local iam_sa_exists=true
    
    # Verify IAM SA exists (just check, don't create yet)
    echo ""
    echo -ne "${GRAY}Verifying IAM account...${NC}"
    if verify_iam_sa "$iam_sa_email" "$project_id"; then
        echo -e "\r${LGREEN}✓ IAM account verified${NC}     "
        log "IAM SA verified: $iam_sa_email"
    else
        echo -e "\r${YELLOW}⚠ IAM Account does not exist (will be created)${NC}     "
        log "IAM SA not found, will be created: $iam_sa_email"
        iam_sa_exists=false
    fi
    
    echo ""
    
    # --- Step 3: Kubernetes Service Account ---
    prompt_input "Enter Kubernetes Service Account name" "ksa_name"
    
    if [[ -z "$ksa_name" ]]; then
        print_error "Kubernetes Service Account es requerido"
        exit 1
    fi
    
    echo ""
    
    # --- Step 4: List and Select Cluster ---
    echo -ne "${GRAY}Searching for clusters in the project...${NC}"
    
    local clusters_raw=$(list_gke_clusters "$project_id")
    
    if [[ -z "$clusters_raw" ]]; then
        echo -e "\r${RED}✗ No clusters found${NC}     "
        print_error "No hay clusters GKE en el proyecto $project_id"
        exit 1
    fi
    
    echo -e "\r${LGREEN}✓ Clusters found${NC}          "
    echo ""
    
    # Parse clusters into arrays
    declare -a cluster_names
    declare -a cluster_locations
    declare -a cluster_options
    
    while IFS=$'\t' read -r name location; do
        cluster_names+=("$name")
        cluster_locations+=("$location")
        cluster_options+=("$name ($location)")
    done <<< "$clusters_raw"
    
    # Show selection menu
    if [[ ${#cluster_options[@]} -eq 1 ]]; then
        selected_cluster="${cluster_names[0]}"
        selected_location="${cluster_locations[0]}"
        print_info "Single cluster found" "$selected_cluster ($selected_location)"
    else
        prompt_selection "Select GKE cluster:" cluster_options selected_option
        
        # Find selected cluster
        for i in "${!cluster_options[@]}"; do
            if [[ "${cluster_options[$i]}" == "$selected_option" ]]; then
                selected_cluster="${cluster_names[$i]}"
                selected_location="${cluster_locations[$i]}"
                break
            fi
        done
    fi
    
    echo ""
    
    # --- Step 5: Connect to Cluster ---
    echo -ne "${GRAY}Connecting to cluster...${NC}"
    
    if connect_to_cluster "$selected_cluster" "$selected_location" "$project_id" >/dev/null 2>&1; then
        echo -e "\r${LGREEN}✓ Connected to cluster${NC}          "
        log "Connected to cluster: $selected_cluster"
    else
        echo -e "\r${RED}✗ Connection error${NC}          "
        print_error "No se pudo conectar al cluster"
        exit 1
    fi
    
    echo ""
    
    # --- Step 6: Namespace Selection ---
    prompt_input "Enter namespace" "namespace" "apps"
    
    echo ""
    
    # --- Confirmation ---
    print_header "Configuration"
    if [[ -n "$G_TICKET_ID" ]]; then
        print_info "Ticket/CTask" "$G_TICKET_ID"
    fi
    print_info "Project ID" "$project_id"
    print_info "Cluster" "$selected_cluster"
    print_info "Location" "$selected_location"
    print_info "Namespace" "$namespace"
    print_info "Kubernetes SA" "$ksa_name"
    if [[ "$iam_sa_exists" == "false" ]]; then
        echo -e "${WHITE}IAM SA:${NC} ${YELLOW}${iam_sa_email} (new)${NC}"
        log "IAM SA: ${iam_sa_email} (new)"
    else
        print_info "IAM SA" "$iam_sa_email"
    fi
    echo -e "${LGREEN}========================================${NC}"
    
    echo ""
    
    # --- Confirmation before creating resources ---
    local confirm_msg="The following resources will be created/configured in Workload Identity:"
    [[ "$iam_sa_exists" == "false" ]] && confirm_msg+=$'\n  • IAM Service Account (new)'
    confirm_msg+=$'\n  • Kubernetes namespace\n  • Kubernetes Service Account\n  • IAM Binding'
    
    if ! ask_confirmation "$confirm_msg" "create"; then
        print_warning "Operation cancelled"
        return 0
    fi
    
    echo ""
    
    # --- Step 7: Execute Configuration ---
    print_header "Executing Configuration"
    echo ""
    
    local step=1
    local total_steps=4
    
    # Create IAM SA if needed
    if [[ "$iam_sa_exists" == "false" ]]; then
        total_steps=5
        echo -ne "${WHITE}[${step}/${total_steps}]${NC} Creating IAM account..."
        if create_iam_sa "$iam_sa_name" "$project_id" >/dev/null 2>&1; then
            echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creating IAM account... ${LGREEN}✓${NC}"
            log "IAM SA created: $iam_sa_email"
        else
            echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creating IAM account... ${RED}✗${NC}"
            print_error "Error creating IAM account"
            exit 1
        fi
        ((step++))
    fi
    
    # Create namespace
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Creating namespace..."
    if create_namespace "$namespace" >/dev/null 2>&1; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creating namespace... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creating namespace... ${YELLOW}(existing)${NC}"
    fi
    ((step++))
    
    # Create KSA
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Creating Kubernetes SA..."
    if create_ksa "$ksa_name" "$namespace" >/dev/null 2>&1; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creating Kubernetes SA... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creating Kubernetes SA... ${YELLOW}(existing)${NC}"
    fi
    ((step++))
    
    # Add IAM binding
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Adding IAM binding..."
    if add_iam_binding "$iam_sa_email" "$project_id" "$ksa_name" "$namespace" >/dev/null 2>&1; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Adding IAM binding... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Adding IAM binding... ${RED}✗${NC}"
        print_error "Error al agregar IAM binding"
    fi
    ((step++))
    
    # Annotate KSA
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Annotating Kubernetes SA..."
    if annotate_ksa "$ksa_name" "$namespace" "$iam_sa_email" >/dev/null 2>&1; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Annotating Kubernetes SA... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Annotating Kubernetes SA... ${RED}✗${NC}"
        print_error "Error al anotar KSA"
    fi
    
    echo ""
    
    # --- Register in control file ---
    register_execution "$G_TICKET_ID" "$project_id" "$selected_cluster" "$selected_location" "$namespace" "$ksa_name" "$iam_sa_email"
    
    # --- Final Summary ---
    print_header "Workload Identity Configured"
    if [[ -n "$G_TICKET_ID" ]]; then
        print_info "Ticket" "$G_TICKET_ID"
    fi
    print_info "Project" "$project_id"
    print_info "Cluster" "$selected_cluster"
    print_info "Namespace" "$namespace"
    print_info "Kubernetes SA" "$ksa_name"
    print_info "IAM SA" "$iam_sa_email"
    echo -e "${LGREEN}========================================${NC}"
    
    echo ""
    echo -e "${GRAY}Log saved to: $G_LOG_FILE${NC}"
    echo -e "${GRAY}Record added to: $G_CONTROL_FILE${NC}"
    log "Session completed successfully"
    log "Registered in control file: $G_CONTROL_FILE"
    
    echo ""
    echo -ne "${YELLOW}Press Enter to continue...${NC}"
    read
}

# =============================================================================
# Operation: Verify Workload Identity
# =============================================================================

operation_verify() {
    clear
    print_header "Verify Workload Identity"
    echo ""
    
    # Setup temporary log
    setup_log_directory ""
    log "Session started - Operation: VERIFY"
    
    # --- List active projects from registry ---
    if [[ -f "$G_CONTROL_FILE" ]]; then
        echo -e "${WHITE}Active configurations from registry:${NC}"
        echo ""
        
        # Use awk to process CSV and filter active configurations
        local active_count=$(awk -F',' 'NR>1 && $9 ~ /^activo/ {count++} END {print count+0}' "$G_CONTROL_FILE")
        
        if [[ $active_count -gt 0 ]]; then
            awk -F',' 'NR>1 && $9 ~ /^activo/ {
                printf "  \033[1;36m•\033[0m Project: \033[1;37m%s\033[0m\n", $3
                printf "    Cluster: \033[1;36m%s\033[0m | Location: \033[1;33m%s\033[0m\n", $4, $5
                printf "    Namespace: \033[1;33m%s\033[0m | KSA: \033[1;32m%s\033[0m\n", $6, $7
                printf "    IAM SA: \033[1;34m%s\033[0m\n\n", $8
            }' "$G_CONTROL_FILE"
        else
            echo -e "  ${GRAY}(No active configurations)${NC}"
        fi
        
        echo ""
    else
        print_warning "No registry file found. Manual configuration entry required."
        echo ""
    fi
    
    # --- Menu options ---
    echo -e "${WHITE}Options:${NC}"
    echo -e "  ${LCYAN}1)${NC} Continue with verification"
    echo -e "  ${LCYAN}0)${NC} Return to main menu"
    echo ""
    echo -ne "${YELLOW}Select an option: ${NC}"
    read verify_option
    
    if [[ "$verify_option" != "1" ]]; then
        return 0
    fi
    
    echo ""
    
    # --- Project ID ---
    local current_project=$(get_current_project)
    prompt_input "Enter Project ID to verify" "project_id" "$current_project"
    
    if [[ -z "$project_id" ]]; then
        print_error "Project ID is required"
        return 1
    fi
    
    echo ""
    
    # --- List and Select Cluster ---
    echo -ne "${GRAY}Searching for clusters in the project...${NC}"
    
    local clusters_raw=$(list_gke_clusters "$project_id")
    
    if [[ -z "$clusters_raw" ]]; then
        echo -e "\r${RED}✗ No clusters found${NC}     "
        return 1
    fi
    
    echo -e "\r${LGREEN}✓ Clusters found${NC}          "
    echo ""
    
    declare -a cluster_names
    declare -a cluster_locations
    declare -a cluster_options
    
    while IFS=$'\t' read -r name location; do
        cluster_names+=("$name")
        cluster_locations+=("$location")
        cluster_options+=("$name ($location)")
    done <<< "$clusters_raw"
    
    if [[ ${#cluster_options[@]} -eq 1 ]]; then
        selected_cluster="${cluster_names[0]}"
        selected_location="${cluster_locations[0]}"
    else
        prompt_selection "Select GKE cluster:" cluster_options selected_option
        for i in "${!cluster_options[@]}"; do
            if [[ "${cluster_options[$i]}" == "$selected_option" ]]; then
                selected_cluster="${cluster_names[$i]}"
                selected_location="${cluster_locations[$i]}"
                break
            fi
        done
    fi
    
    echo ""
    
    # --- Connect to Cluster ---
    echo -ne "${GRAY}Connecting to cluster...${NC}"
    if connect_to_cluster "$selected_cluster" "$selected_location" "$project_id" >/dev/null 2>&1; then
        echo -e "\r${LGREEN}✓ Connected to cluster${NC}          "
    else
        echo -e "\r${RED}✗ Connection error${NC}          "
        return 1
    fi
    
    echo ""
    
    # --- KSA and Namespace ---
    prompt_input "Enter namespace" "namespace" "apps"
    prompt_input "Enter KSA name to verify" "ksa_name"
    prompt_input "Enter IAM Service Account name (without @...)" "iam_sa_name" "$ksa_name"
    
    local iam_sa_email="${iam_sa_name}@${project_id}.iam.gserviceaccount.com"
    
    echo ""
    
    # --- Verify ---
    print_header "Verification Results"
    
    local ksa_exists=false
    local iam_sa_exists=false
    local annotation=""
    
    # Check IAM SA exists
    echo -ne "Verificando IAM SA..."
    if gcloud iam service-accounts describe "$iam_sa_email" --project "$project_id" &>/dev/null; then
        echo -e "\r${LGREEN}✓ IAM SA existe${NC}                 "
        print_info "IAM SA" "$iam_sa_email"
        iam_sa_exists=true
    else
        echo -e "\r${RED}✗ IAM SA not found${NC}          "
    fi
    
    # Check KSA exists
    echo -ne "Verificando KSA..."
    if kubectl get serviceaccount "$ksa_name" -n "$namespace" &>/dev/null; then
        echo -e "\r${LGREEN}✓ KSA existe${NC}                    "
        ksa_exists=true
    else
        echo -e "\r${RED}✗ KSA not found${NC}             "
    fi
    
    # Check annotation (only if KSA exists)
    if [[ "$ksa_exists" == "true" ]]; then
        annotation=$(get_ksa_annotation "$ksa_name" "$namespace")
        echo -ne "Verifying annotation..."
        if [[ -n "$annotation" ]]; then
            echo -e "\r${LGREEN}✓ Annotation configured${NC}         "
            print_info "Annotation" "$annotation"
        else
            echo -e "\r${YELLOW}⚠ No Workload Identity annotation${NC}"
        fi
    fi
    
    # Check IAM binding (only if IAM SA exists)
    if [[ "$iam_sa_exists" == "true" ]]; then
        echo -ne "Verificando IAM binding..."
        local member="serviceAccount:${project_id}.svc.id.goog[${namespace}/${ksa_name}]"
        if gcloud iam service-accounts get-iam-policy "$iam_sa_email" --project "$project_id" 2>/dev/null | grep -q "$member"; then
            echo -e "\r${LGREEN}✓ IAM binding configured${NC}       "
        else
            echo -e "\r${YELLOW}⚠ IAM binding not found${NC}     "
        fi
    fi
    
    echo ""
    
    # Summary
    print_header "Resumen"
    echo ""
    echo -e "  IAM Service Account: $([ "$iam_sa_exists" == "true" ] && echo "${LGREEN}Existe${NC}" || echo "${RED}No existe${NC}")"
    echo -e "  Kubernetes SA:       $([ "$ksa_exists" == "true" ] && echo "${LGREEN}Existe${NC}" || echo "${RED}No existe${NC}")"
    if [[ "$ksa_exists" == "true" ]]; then
        echo -e "  WI Annotation:        $([ -n "$annotation" ] && echo "${LGREEN}Configured${NC}" || echo "${YELLOW}Not configured${NC}")"
    fi
    echo ""
    print_header "Verification Completed"
    
    echo ""
    echo -ne "${YELLOW}Press Enter to continue...${NC}"
    read
}

# =============================================================================
# Safety Functions
# =============================================================================

# Function: ask_confirmation
# Description: Request double confirmation for critical operations
# Parameters: $1=message, $2=action (e.g.: "delete")
# Returns: 0=confirmado, 1=cancelado
ask_confirmation() {
    local message="$1"
    local action="${2:-continue}"
    
    echo -e "\n${YELLOW}⚠ Confirmation Required${NC}"
    echo -e "${GRAY}─────────────────────────────────────${NC}"
    echo -e "  ${message}"
    echo -e "${GRAY}─────────────────────────────────────${NC}"
    echo ""
    
    # First question - accept Y/y/N/n or yes/no
    echo -ne "Are you sure you want to ${action}? ${LCYAN}(Y/N)${NC}: "
    local response1
    read response1
    
    # Convert to lowercase for comparison
    response1=$(echo "$response1" | tr '[:upper:]' '[:lower:]')
    
    # Accept: yes, y, or empty (default yes for critical operations)
    if [[ ! "$response1" =~ ^(yes|y)$ ]]; then
        echo -e "${LGREEN}✓ Operation cancelled${NC}"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Operation: Cleanup Workload Identity
# =============================================================================

operation_cleanup() {
    clear
    print_header "Delete Workload Identity"
    echo ""
    
    # Setup temporary log
    setup_log_directory ""
    log "Session started - Operation: CLEANUP"
    
    # --- Check if registry has active records ---
    local project_id=""
    local selected_cluster=""
    local selected_location=""
    local namespace=""
    local ksa_name=""
    local annotation=""
    
    if [[ -f "$G_CONTROL_FILE" ]]; then
        # Get active records from CSV
        local active_records=$(tail -n +2 "$G_CONTROL_FILE" | awk -F',' '$9 == "activo"')
        
        if [[ -n "$active_records" ]]; then
            echo -e "${WHITE}Active configurations in registry:${NC}"
            echo ""
            
            declare -a record_options
            declare -a record_projects
            declare -a record_clusters
            declare -a record_locations
            declare -a record_namespaces
            declare -a record_ksas
            declare -a record_iam_sas
            local idx=1
            
            while IFS=',' read -r fecha ticket proj clust loc ns ksa iam_sa status; do
                record_options+=("$proj | $clust | $ns | $ksa")
                record_projects+=("$proj")
                record_clusters+=("$clust")
                record_locations+=("$loc")
                record_namespaces+=("$ns")
                record_ksas+=("$ksa")
                record_iam_sas+=("$iam_sa")
                echo -e "  ${LCYAN}${idx})${NC} ${WHITE}$proj${NC} | ${YELLOW}$clust${NC} | ${LCYAN}$ns${NC} | ${LGREEN}$ksa${NC}"
                ((idx++))
            done <<< "$active_records"
            
            echo -e "  ${LCYAN}${idx})${NC} ${YELLOW}Delete configuration manually${NC}"
            echo ""
            
            local max_opt=${#record_options[@]}
            ((max_opt++))
            
            echo -ne "${WHITE}Select an option [1-${max_opt}]:${NC} "
            read selection
            
            if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$max_opt" ]]; then
                if [[ "$selection" -eq "$max_opt" ]]; then
                    # Manual selection - continue with normal flow
                    :
                else
                    # Use selected record
                    local sel_idx=$((selection-1))
                    project_id="${record_projects[$sel_idx]}"
                    selected_cluster="${record_clusters[$sel_idx]}"
                    selected_location="${record_locations[$sel_idx]}"
                    namespace="${record_namespaces[$sel_idx]}"
                    ksa_name="${record_ksas[$sel_idx]}"
                    annotation="${record_iam_sas[$sel_idx]}"
                    
                    echo ""
                    echo -e "${LGREEN}✓ Selected:${NC} ${WHITE}$ksa_name${NC} en ${LCYAN}$namespace${NC}"
                    
                    # Connect to cluster
                    echo ""
                    echo -ne "${GRAY}Connecting to cluster...${NC}"
                    if connect_to_cluster "$selected_cluster" "$selected_location" "$project_id" >/dev/null 2>&1; then
                        echo -e "\r${LGREEN}✓ Connected to cluster${NC}          "
                    else
                        echo -e "\r${RED}✗ Connection error${NC}          "
                        echo -ne "${YELLOW}Press Enter to continue...${NC}"
                        read
                        return 1
                    fi
                fi
            else
                echo -e "${RED}Invalid option${NC}"
                echo -ne "${YELLOW}Press Enter to continue...${NC}"
                read
                return 1
            fi
        fi
    fi
    
    # --- Manual selection if not selected from registry ---
    if [[ -z "$project_id" ]]; then
        local current_project=$(get_current_project)
        prompt_input "Enter Project ID" "project_id" "$current_project"
        
        echo ""
        
        # --- List and Select Cluster ---
        echo -ne "${GRAY}Searching for clusters in the project...${NC}"
        
        local clusters_raw=$(list_gke_clusters "$project_id")
        
        if [[ -z "$clusters_raw" ]]; then
            echo -e "\r${RED}✗ No clusters found${NC}     "
            return 1
        fi
        
        echo -e "\r${LGREEN}✓ Clusters found${NC}          "
        echo ""
        
        declare -a cluster_names
        declare -a cluster_locations
        declare -a cluster_options
        
        while IFS=$'\t' read -r name location; do
            cluster_names+=("$name")
            cluster_locations+=("$location")
            cluster_options+=("$name ($location)")
        done <<< "$clusters_raw"
        
        if [[ ${#cluster_options[@]} -eq 1 ]]; then
            selected_cluster="${cluster_names[0]}"
            selected_location="${cluster_locations[0]}"
        else
            prompt_selection "Select GKE cluster:" cluster_options selected_option
            for i in "${!cluster_options[@]}"; do
                if [[ "${cluster_options[$i]}" == "$selected_option" ]]; then
                    selected_cluster="${cluster_names[$i]}"
                    selected_location="${cluster_locations[$i]}"
                    break
                fi
            done
        fi
        
        echo ""
        
        # --- Connect to Cluster ---
        echo -ne "${GRAY}Connecting to cluster...${NC}"
        if connect_to_cluster "$selected_cluster" "$selected_location" "$project_id" >/dev/null 2>&1; then
            echo -e "\r${LGREEN}✓ Connected to cluster${NC}          "
        else
            echo -e "\r${RED}✗ Connection error${NC}          "
            return 1
        fi
        
        echo ""
        
        # --- KSA and Namespace ---
        prompt_input "Enter namespace" "namespace" "apps"
        prompt_input "Enter KSA name to delete" "ksa_name"
        
        # Get current annotation
        annotation=$(get_ksa_annotation "$ksa_name" "$namespace")
    fi
    
    if [[ -z "$annotation" ]]; then
        print_warning "KSA does not have Workload Identity configured"
        echo ""
        echo -ne "${YELLOW}Press Enter to continue...${NC}"
        read
        return 0
    fi
    
    echo ""
    
    # --- Confirmation ---
    print_header "Resources to Delete"
    print_info "Project" "$project_id"
    print_info "Cluster" "$selected_cluster"
    print_info "Namespace" "$namespace"
    print_info "KSA" "$ksa_name"
    print_info "IAM SA" "$annotation"
    echo -e "${LGREEN}========================================${NC}"
    
    echo ""
    echo -e "${WHITE}What would you like to delete?${NC}"
    echo -e "  ${LCYAN}1)${NC} Delete binding only (keep KSA and IAM SA)"
    echo -e "  ${LCYAN}2)${NC} Delete binding + KSA (keep IAM SA)"
    echo -e "  ${LCYAN}3)${NC} Delete everything (binding + KSA + IAM SA)"
    echo -e "  ${LCYAN}0)${NC} Cancel"
    echo ""
    echo -ne "${YELLOW}Select an option: ${NC}"
    read cleanup_option
    
    if [[ "$cleanup_option" == "0" ]]; then
        print_warning "Operation cancelled"
        echo ""
        echo -ne "${YELLOW}Press Enter to continue...${NC}"
        read
        return 0
    fi
    
    if [[ ! "$cleanup_option" =~ ^[1-3]$ ]]; then
        print_error "Invalid option"
        echo ""
        echo -ne "${YELLOW}Press Enter to continue...${NC}"
        read
        return 0
    fi
    
    echo ""
    echo -e "${RED}⚠ This action cannot be undone${NC}"
    echo -ne "${YELLOW}Are you sure? (Y/N): ${NC}"
    read confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "Operation cancelled"
        echo ""
        echo -ne "${YELLOW}Press Enter to continue...${NC}"
        read
        return 0
    fi
    
    echo ""
    
    # --- Confirmation before destructive operation ---
    local confirm_message="The following resources will be deleted:"
    [[ "$cleanup_option" == "1" ]] && confirm_message+=$'\n  • IAM Binding'
    [[ "$cleanup_option" == "2" ]] && confirm_message+=$'\n  • IAM Binding\n  • Kubernetes Service Account'
    [[ "$cleanup_option" == "3" ]] && confirm_message+=$'\n  • IAM Binding\n  • Kubernetes Service Account\n  • GCP IAM Service Account'
    
    confirm_message+=$'\n\nProject: '"$project_id"$'\nCluster: '"$selected_cluster"$'\nNamespace: '"$namespace"$'\nKSA: '"$ksa_name"
    
    if ! ask_confirmation "$confirm_message" "delete"; then
        return 0
    fi
    
    # --- Execute Cleanup ---
    print_header "Executing Cleanup"
    echo ""
    
    local total_steps=2
    [[ "$cleanup_option" == "2" ]] && total_steps=3
    [[ "$cleanup_option" == "3" ]] && total_steps=4
    local step=1
    
    # Step 1: Remove IAM binding
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Deleting IAM binding..."
    if remove_iam_binding "$annotation" "$project_id" "$ksa_name" "$namespace" >/dev/null 2>&1; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Deleting IAM binding... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Deleting IAM binding... ${YELLOW}(may not exist)${NC}"
    fi
    ((step++))
    
    # Step 2: Remove annotation
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Removing KSA annotation..."
    if kubectl annotate serviceaccount "$ksa_name" -n "$namespace" "iam.gke.io/gcp-service-account-" >/dev/null 2>&1; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Removing KSA annotation... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Removing KSA annotation... ${YELLOW}(may not exist)${NC}"
    fi
    ((step++))
    
    # Step 3: Delete KSA (if option 2 or 3)
    if [[ "$cleanup_option" =~ ^[23]$ ]]; then
        echo -ne "${WHITE}[${step}/${total_steps}]${NC} Deleting KSA..."
        if delete_ksa "$ksa_name" "$namespace" >/dev/null 2>&1; then
            echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Deleting KSA... ${LGREEN}✓${NC}"
        else
            echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Deleting KSA... ${RED}✗${NC}"
        fi
        ((step++))
    fi
    
    # Step 4: Delete IAM SA (if option 3)
    if [[ "$cleanup_option" == "3" ]]; then
        echo -ne "${WHITE}[${step}/${total_steps}]${NC} Deleting IAM account..."
        if gcloud iam service-accounts delete "$annotation" --project "$project_id" --quiet >/dev/null 2>&1; then
            echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Deleting IAM account... ${LGREEN}✓${NC}"
        else
            echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Deleting IAM account... ${RED}✗${NC}"
        fi
    fi
    
    echo ""
    
    # --- Update registry status ---
    local status_text=""
    case "$cleanup_option" in
        1) status_text="eliminado-binding" ;;
        2) status_text="eliminado-binding-ksa" ;;
        3) status_text="eliminado-todo" ;;
    esac
    
    # Get cluster info from current context
    local current_context=$(kubectl config current-context 2>/dev/null)
    local current_cluster=$(echo "$current_context" | grep -oP 'gke_[^_]+_[^_]+_\K[^_]+')
    
    if update_registry_status "$project_id" "$current_cluster" "$namespace" "$ksa_name" "$status_text"; then
        echo -e "${GRAY}Registry updated: ${status_text}${NC}"
    fi
    
    print_header "✓ Cleanup Completed Successfully"
    echo ""
    echo -e "${LGREEN}Resources deleted:${NC}"
    echo -e "  • Project: ${LCYAN}${project_id}${NC}"
    echo -e "  • Cluster: ${LCYAN}${selected_cluster}${NC}"
    echo -e "  • Namespace: ${LCYAN}${namespace}${NC}"
    echo -e "  • KSA: ${LCYAN}${ksa_name}${NC}"
    echo -e "  • Status: ${LGREEN}${status_text}${NC}"
    
    log "Cleanup completed for $ksa_name in $namespace - Status: $status_text"
    
    echo ""
    echo -ne "${YELLOW}Press Enter to continue...${NC}"
    read
}

# =============================================================================
# Operation: List Workload Identities
# =============================================================================

operation_list() {
    clear
    print_header "List Workload Identities"
    echo ""
    
    # --- Project Selection from Registry or Manual ---
    local project_id=""
    local current_project=$(get_current_project)
    
    # Check if registry has projects (only active ones)
    if [[ -f "$G_CONTROL_FILE" ]]; then
        # Get unique projects from CSV (column 3) - only active records (Status = activo)
        local registry_projects=$(tail -n +2 "$G_CONTROL_FILE" | awk -F',' '$9 == "activo" {print $3}' | sort -u | grep -v '^$')
        
        if [[ -n "$registry_projects" ]]; then
            echo -e "${WHITE}Active projects in registry:${NC}"
            echo ""
            
            declare -a project_options
            local idx=1
            
            while IFS= read -r proj; do
                project_options+=("$proj")
                echo -e "  ${LCYAN}${idx})${NC} $proj"
                ((idx++))
            done <<< "$registry_projects"
            
            echo -e "  ${LCYAN}${idx})${NC} ${YELLOW}Enter another project manually${NC}"
            echo ""
            
            local max_opt=${#project_options[@]}
            ((max_opt++))
            
            echo -ne "${WHITE}Select an option [1-${max_opt}]:${NC} "
            read selection
            
            if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$max_opt" ]]; then
                if [[ "$selection" -eq "$max_opt" ]]; then
                    # Manual input
                    prompt_input "Enter Project ID" "project_id" "$current_project"
                else
                    project_id="${project_options[$((selection-1))]}"
                    echo -e "${LGREEN}✓ Selected project:${NC} ${WHITE}$project_id${NC}"
                fi
            else
                echo -e "${RED}Invalid option${NC}"
                echo -ne "${YELLOW}Press Enter to continue...${NC}"
                read
                return 1
            fi
        else
            prompt_input "Enter Project ID" "project_id" "$current_project"
        fi
    else
        prompt_input "Enter Project ID" "project_id" "$current_project"
    fi
    
    echo ""
    
    # --- Cluster Selection from Registry or GCP ---
    local selected_cluster=""
    local selected_location=""
    
    # Check if registry has clusters for this project
    if [[ -f "$G_CONTROL_FILE" ]]; then
        # Get unique clusters for this project (columns 4=cluster, 5=location) - only active records
        local registry_clusters=$(tail -n +2 "$G_CONTROL_FILE" | awk -F',' -v proj="$project_id" '$3 == proj && $9 == "activo" {print $4 "," $5}' | sort -u | grep -v '^,$')
        
        if [[ -n "$registry_clusters" ]]; then
            echo -e "${WHITE}Clusters in registry for ${LCYAN}$project_id${NC}:${NC}"
            echo ""
            
            declare -a reg_cluster_names
            declare -a reg_cluster_locations
            local idx=1
            
            while IFS=',' read -r cluster_name cluster_location; do
                reg_cluster_names+=("$cluster_name")
                reg_cluster_locations+=("$cluster_location")
                echo -e "  ${LCYAN}${idx})${NC} $cluster_name (${cluster_location})"
                ((idx++))
            done <<< "$registry_clusters"
            
            echo -e "  ${LCYAN}${idx})${NC} ${YELLOW}Buscar otros clusters en GCP${NC}"
            echo ""
            
            local max_opt=${#reg_cluster_names[@]}
            ((max_opt++))
            
            echo -ne "${WHITE}Select an option [1-${max_opt}]:${NC} "
            read selection
            
            if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$max_opt" ]]; then
                if [[ "$selection" -eq "$max_opt" ]]; then
                    # Search clusters in GCP
                    echo ""
                    echo -ne "${GRAY}Searching for clusters in the project...${NC}"
                    
                    local clusters_raw=$(list_gke_clusters "$project_id")
                    
                    if [[ -z "$clusters_raw" ]]; then
                        echo -e "\r${RED}✗ No clusters found${NC}     "
                        echo ""
                        echo -ne "${YELLOW}Press Enter to continue...${NC}"
                        read
                        return 1
                    fi
                    
                    echo -e "\r${LGREEN}✓ Clusters found${NC}          "
                    echo ""
                    
                    declare -a cluster_names
                    declare -a cluster_locations
                    declare -a cluster_options
                    
                    while IFS=$'\t' read -r name location; do
                        cluster_names+=("$name")
                        cluster_locations+=("$location")
                        cluster_options+=("$name ($location)")
                    done <<< "$clusters_raw"
                    
                    if [[ ${#cluster_options[@]} -eq 1 ]]; then
                        selected_cluster="${cluster_names[0]}"
                        selected_location="${cluster_locations[0]}"
                    else
                        prompt_selection "Select GKE cluster:" cluster_options selected_option
                        for i in "${!cluster_options[@]}"; do
                            if [[ "${cluster_options[$i]}" == "$selected_option" ]]; then
                                selected_cluster="${cluster_names[$i]}"
                                selected_location="${cluster_locations[$i]}"
                                break
                            fi
                        done
                    fi
                else
                    selected_cluster="${reg_cluster_names[$((selection-1))]}"
                    selected_location="${reg_cluster_locations[$((selection-1))]}"
                    echo -e "${LGREEN}✓ Selected cluster:${NC} ${WHITE}$selected_cluster${NC}"
                fi
            else
                echo -e "${RED}Invalid option${NC}"
                echo -ne "${YELLOW}Press Enter to continue...${NC}"
                read
                return 1
            fi
        fi
    fi
    
    # If no cluster selected from registry, search in GCP
    if [[ -z "$selected_cluster" ]]; then
        echo -ne "${GRAY}Searching for clusters in the project...${NC}"
        
        local clusters_raw=$(list_gke_clusters "$project_id")
        
        if [[ -z "$clusters_raw" ]]; then
            echo -e "\r${RED}✗ No clusters found${NC}     "
            echo ""
            echo -ne "${YELLOW}Press Enter to continue...${NC}"
            read
            return 1
        fi
        
        echo -e "\r${LGREEN}✓ Clusters found${NC}          "
        echo ""
        
        declare -a cluster_names
        declare -a cluster_locations
        declare -a cluster_options
        
        while IFS=$'\t' read -r name location; do
            cluster_names+=("$name")
            cluster_locations+=("$location")
            cluster_options+=("$name ($location)")
        done <<< "$clusters_raw"
        
        if [[ ${#cluster_options[@]} -eq 1 ]]; then
            selected_cluster="${cluster_names[0]}"
            selected_location="${cluster_locations[0]}"
        else
            prompt_selection "Select GKE cluster:" cluster_options selected_option
            for i in "${!cluster_options[@]}"; do
                if [[ "${cluster_options[$i]}" == "$selected_option" ]]; then
                    selected_cluster="${cluster_names[$i]}"
                    selected_location="${cluster_locations[$i]}"
                    break
                fi
            done
        fi
    fi
    
    echo ""
    
    # --- Connect to Cluster ---
    echo -ne "${GRAY}Connecting to cluster...${NC}"
    if connect_to_cluster "$selected_cluster" "$selected_location" "$project_id" >/dev/null 2>&1; then
        echo -e "\r${LGREEN}✓ Connected to cluster${NC}          "
    else
        echo -e "\r${RED}✗ Connection error${NC}          "
        echo ""
        echo -ne "${YELLOW}Press Enter to continue...${NC}"
        read
        return 1
    fi
    
    echo ""
    
    # --- Namespace ---
    prompt_input "Enter namespace (o 'all' para todos)" "namespace" "apps"
    
    echo ""
    print_header "Configured Workload Identities"
    echo ""
    
    if [[ "$namespace" == "all" ]]; then
        local namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
        for ns in $namespaces; do
            list_workload_identities "$ns"
            echo ""
        done
    else
        list_workload_identities "$namespace"
    fi
    
    echo ""
    echo -ne "${YELLOW}Press Enter to continue...${NC}"
    read
}

# =============================================================================
# Operation: View Registry
# =============================================================================

operation_view_registry() {
    clear
    print_header "Operations Registry"
    echo ""
    
    if [[ ! -f "$G_CONTROL_FILE" ]]; then
        print_warning "No records available"
        echo ""
        echo -ne "${YELLOW}Press Enter to continue...${NC}"
        read
        return 0
    fi
    
    # Count records (handle missing trailing newline)
    local total=$(cat "$G_CONTROL_FILE" | tail -n +2 | wc -l)
    # If last line doesn't end with newline, add 1
    if [[ $(tail -c 1 "$G_CONTROL_FILE" | wc -l) -eq 0 ]]; then
        ((total++))
    fi
    
    # Count active records
    local active=$(cat "$G_CONTROL_FILE" | tail -n +2 | awk -F',' '{status=$NF; gsub(/^[[:space:]]+|[[:space:]]+$/, "", status); if (status == "activo") count++} END {print count+0}')
    local deleted=$((total - active))
    echo -e "${WHITE}Total records:${NC} ${LCYAN}${total}${NC} (${LGREEN}${active} active${NC}, ${RED}${deleted} deleted${NC})"
    echo ""
    
    # Show all records
    echo -e "${WHITE}All records:${NC}"
    echo -e "${GRAY}──────────────────────────────────────────────────────────────────────────────────────────────${NC}"
    
    # Header
    echo -e "${WHITE}Fecha               | Ticket     | Project          | Namespace | KSA              | Status${NC}"
    echo -e "${GRAY}──────────────────────────────────────────────────────────────────────────────────────────────${NC}"
    
    # Data (skip header, show all records - add newline to handle EOF without newline)
    (cat "$G_CONTROL_FILE" && echo "") | tail -n +2 | while IFS=',' read -r fecha ticket project cluster location namespace ksa iam_sa status; do
        # Skip empty lines
        [[ -z "$fecha" ]] && continue
        
        # Trim status
        status=$(echo "$status" | xargs)
        
        local status_color="${LGREEN}"
        [[ "$status" =~ ^eliminado ]] && status_color="${RED}"
        printf "${LCYAN}%-19s${NC} | ${YELLOW}%-10s${NC} | ${WHITE}%-16s${NC} | ${LCYAN}%-9s${NC} | ${LGREEN}%-16s${NC} | ${status_color}%s${NC}\n" \
            "$fecha" "$ticket" "$project" "$namespace" "$ksa" "$status"
    done
    
    echo -e "${GRAY}────────────────────────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${GRAY}File: $G_CONTROL_FILE${NC}"
    
    echo ""
    echo -ne "${YELLOW}Press Enter to continue...${NC}"
    read
}

# =============================================================================
# Main Menu Loop
# =============================================================================

main() {
    while true; do
        show_main_menu
        read option
        
        case $option in
            1) operation_setup ;;
            2) operation_verify ;;
            3) operation_cleanup ;;
            4) operation_list ;;
            5) operation_view_registry ;;
            0) 
                clear
                echo -e "${LGREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

# =============================================================================
# Entry Point
# =============================================================================

# Handle command line arguments
main_entry() {
    local arg="${1:-}"
    
    case "$arg" in
        --help|-h)
            show_help
            exit 0
            ;;
        --version|-v)
            show_version
            exit 0
            ;;
        "")
            # No arguments - run interactive menu
            ;;
        *)
            echo -e "${RED}✗ Argumento no reconocido: $arg${NC}"
            echo -e "Use: ./workload-identity.sh --help for more information"
            exit 1
            ;;
    esac
}

# Check dependencies
for cmd in gcloud kubectl; do
    if ! command -v $cmd &>/dev/null; then
        echo -e "${RED}✗ Error: $cmd is not installed${NC}"
        echo -e "${GRAY}Instale las herramientas necesarias e intente nuevamente${NC}"
        exit 1
    fi
done

# Initialize control file
init_control_file

# Process arguments
main_entry "$@"

# Run main menu
main "$@"
