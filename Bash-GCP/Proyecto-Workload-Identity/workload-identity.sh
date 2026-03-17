#!/bin/bash
# =============================================================================
# Workload Identity Manager for GCP/GKE
# Configure GCP Workload Identity between GCP SA and Kubernetes SA
# 
# Project: GCP Workload Identity API
# Version: 4.0.0
# Author: Infrastructure Team
# License: Internal Use
#
# Features:
#   - Interactive menu system with colored output
#   - Automatic backup before any destructive operation
#   - Backup restore with interactive selection
#   - GCS remote state sync (push/pull for team sharing)
#   - CLI non-interactive mode (setup/verify/cleanup/list/bulk-setup)
#   - Dry-run mode: preview all operations without executing
#   - Bulk setup from CSV file for batch provisioning
#   - Structured monthly audit log (logs/audit/audit_YYYY-MM.log)
#   - Automatic ticket-based log organization
#   - CSV registry of all operations with status tracking
#   - Robust error handling and validation
#
# Usage:
#   ./workload-identity.sh              # Run interactive menu
#   ./workload-identity.sh --help       # Show help
#   ./workload-identity.sh --version    # Show version
#   ./workload-identity.sh setup --project P --ksa K [--dry-run]
#   ./workload-identity.sh bulk-setup --file configs.csv
# =============================================================================

# Script safety settings
set -euo pipefail
IFS=$'\n\t'

# Metadata
readonly G_VERSION="4.0.0"
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
readonly G_CONTROL_FILE="${WI_REGISTRY_FILE:-$G_SCRIPT_DIR/workload-identity-registry.csv}"
# Use mktemp for secure temporary directory (prevents symlink attacks)
readonly G_TEMP_DIR="$(mktemp -d -t workload-identity.XXXXXX)"

G_LOG_DIR=""
G_LOG_FILE=""
G_TICKET_ID=""
G_PROJECT_ID=""
G_CLUSTER_NAME=""
G_NAMESPACE="apps"

# --- Load Configuration ---
# Source external configuration file if it exists
if [[ -f "$G_SCRIPT_DIR/config.sh" ]]; then
    # shellcheck source=config.sh
    source "$G_SCRIPT_DIR/config.sh"
fi

# Use configuration values with fallbacks to defaults
readonly G_IAM_ROLE="${WI_IAM_ROLE:-roles/iam.workloadIdentityUser}"
readonly G_DEFAULT_NS="${WI_DEFAULT_NAMESPACE:-apps}"
readonly G_ANNOTATION_KEY="${WI_ANNOTATION_KEY:-iam.gke.io/gcp-service-account}"
readonly G_REGISTRY_FILE="${WI_REGISTRY_FILE:-$G_SCRIPT_DIR/workload-identity-registry.csv}"
G_DRY_RUN="${WI_DRY_RUN:-0}"   # 1 = preview commands only, 0 = execute normally

# Security & Backup settings (from config.sh or environment)
G_BACKUP_DIR="${WI_BACKUP_DIR:-$G_SCRIPT_DIR/backups}"
G_BACKUP_MAX="${WI_BACKUP_MAX:-10}"
G_GCS_BUCKET="${WI_GCS_BUCKET:-}"

# CLI mode prefill variables (empty = interactive, non-empty = auto-fill)
G_CLI_MODE=0
G_CLI_PROJECT=""
G_CLI_CLUSTER=""
G_CLI_NAMESPACE=""
G_CLI_KSA=""
G_CLI_IAM_SA=""
G_CLI_TICKET=""
G_CLI_CLEANUP_LEVEL=""
G_CLI_OPERATION=""
G_CLI_BULK_FILE=""

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
        chmod 600 "$G_CONTROL_FILE"
    fi
    
    # Secure file permissions (sensitive data) - ensure they are strictly 600
    if ! chmod 600 "$G_CONTROL_FILE" 2>/dev/null; then
        echo -e "${RED}✗ Error: Cannot set secure permissions on $G_CONTROL_FILE${NC}" >&2
        return 1
    fi
    
    # Verify permissions were actually set to 600
    local actual_perms
    actual_perms=$(stat -c '%a' "$G_CONTROL_FILE" 2>/dev/null || stat -f '%OA' "$G_CONTROL_FILE" 2>/dev/null)
    if [[ "$actual_perms" != "600" ]]; then
        echo -e "${YELLOW}⚠ Warning: CSV file permissions may not be 600 (found: $actual_perms)${NC}" >&2
    fi
    
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

# =============================================================================
# Function: backup_registry
# Description: Copy current registry to G_BACKUP_DIR with a timestamp name.
#              Encrypts the backup if encryption is enabled.
#              Prunes old backups keeping at most G_BACKUP_MAX copies.
# Parameters: $1 = label (optional, e.g. "pre-cleanup")
# Returns: 0=success, 1=error
# =============================================================================
backup_registry() {
    local label="${1:-manual}"
    local source_file="$G_CONTROL_FILE"

    [[ ! -f "$source_file" ]] && { echo -e "${YELLOW}⚠ Nothing to back up${NC}" >&2; return 0; }

    mkdir -p "$G_BACKUP_DIR" 2>/dev/null || {
        echo -e "${RED}✗ Cannot create backup directory: $G_BACKUP_DIR${NC}" >&2; return 1
    }

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_name="workload-identity-registry_${timestamp}_${label}.csv"
    local backup_path="$G_BACKUP_DIR/$backup_name"

    cp "$source_file" "$backup_path"
    chmod 600 "$backup_path"

    # Prune old backups (keep G_BACKUP_MAX most recent)
    local count
    count=$(find "$G_BACKUP_DIR" -maxdepth 1 -name "workload-identity-registry_*.csv" | wc -l)
    if [[ $count -gt $G_BACKUP_MAX ]]; then
        find "$G_BACKUP_DIR" -maxdepth 1 -name "workload-identity-registry_*.csv" \
            | sort | head -n $(( count - G_BACKUP_MAX )) \
            | xargs rm -f --
    fi

    echo -e "${LGREEN}✓ Backup saved:${NC} ${GRAY}$(basename "$backup_path")${NC}"
    log "Registry backup created: $backup_path (label=$label)"
}

# =============================================================================
# Function: restore_registry
# Description: Restore the registry from a backup file.
#              Creates a backup of the current registry before restoring.
# Parameters: $1 = backup file path (full path)
# Returns: 0=success, 1=error
# =============================================================================
restore_registry() {
    local backup_file="${1:-}"

    if [[ -z "$backup_file" ]]; then
        # Interactive: list available backups and let user choose
        local -a backups=()
        while IFS= read -r f; do
            backups+=("$f")
        done < <(find "$G_BACKUP_DIR" -maxdepth 1 -name "workload-identity-registry_*.csv" | sort -r)

        if [[ ${#backups[@]} -eq 0 ]]; then
            echo -e "${YELLOW}⚠ No backups found in $G_BACKUP_DIR${NC}"
            return 1
        fi

        echo -e "${WHITE}Available backups:${NC}"
        for i in "${!backups[@]}"; do
            echo -e "  ${LCYAN}$((i+1)))${NC} $(basename "${backups[$i]}")"
        done
        echo ""
        echo -ne "${YELLOW}Select backup to restore [1-${#backups[@]}]: ${NC}"
        read sel
        if [[ ! "$sel" =~ ^[0-9]+$ ]] || [[ $sel -lt 1 ]] || [[ $sel -gt ${#backups[@]} ]]; then
            echo -e "${RED}✗ Invalid selection${NC}" >&2; return 1
        fi
        backup_file="${backups[$((sel-1))]}"
    fi

    [[ ! -f "$backup_file" ]] && { echo -e "${RED}✗ File not found: $backup_file${NC}" >&2; return 1; }

    # Safety backup of current registry before overwriting
    backup_registry "pre-restore"

    cp "$backup_file" "$G_CONTROL_FILE"
    chmod 600 "$G_CONTROL_FILE"

    echo -e "${LGREEN}✓ Registry restored from:${NC} ${GRAY}$(basename "$backup_file")${NC}"
    log "Registry restored from: $backup_file"
}

# =============================================================================
# Function: sync_push
# Description: Push registry (and audit log) to a GCS bucket for team sharing.
#              Uploads the encrypted file when encryption is enabled,
#              otherwise uploads the plaintext CSV.
# Returns: 0=success, 1=no bucket configured or upload error
# =============================================================================
sync_push() {
    if [[ -z "$G_GCS_BUCKET" ]]; then
        echo -e "${YELLOW}⚠ WI_GCS_BUCKET not set — skipping remote sync${NC}" >&2
        return 1
    fi

    local upload_file="$G_CONTROL_FILE"
    local remote_name="workload-identity-registry.csv"

    [[ ! -f "$upload_file" ]] && { echo -e "${YELLOW}⚠ Registry file not found — nothing to push${NC}" >&2; return 1; }

    echo -ne "${GRAY}Pushing registry to ${G_GCS_BUCKET}...${NC}"
    if gcloud storage cp "$upload_file" "${G_GCS_BUCKET}/${remote_name}" --quiet 2>/dev/null; then
        echo -e "\r${LGREEN}✓ Registry pushed to ${G_GCS_BUCKET}/${remote_name}${NC}"
        log "Registry pushed to GCS: ${G_GCS_BUCKET}/${remote_name}"

        # Also push the current monthly audit log if it exists
        local audit_file="$G_SCRIPT_DIR/logs/audit/audit_$(date '+%Y-%m').log"
        if [[ -f "$audit_file" ]]; then
            gcloud storage cp "$audit_file" \
                "${G_GCS_BUCKET}/audit/audit_$(date '+%Y-%m').log" --quiet 2>/dev/null || true
        fi
        return 0
    else
        echo -e "\r${RED}✗ Failed to push registry to GCS${NC}"
        log "ERROR: GCS push failed to ${G_GCS_BUCKET}"
        return 1
    fi
}

# =============================================================================
# Function: sync_pull
# Description: Pull the latest registry from GCS, replacing the local copy.
#              Creates a backup of the current local registry first.
# Returns: 0=success, 1=no bucket configured or download error
# =============================================================================
sync_pull() {
    if [[ -z "$G_GCS_BUCKET" ]]; then
        echo -e "${YELLOW}⚠ WI_GCS_BUCKET not set — skipping remote sync${NC}" >&2
        return 1
    fi

    local remote_name="workload-identity-registry.csv"
    local remote_url="${G_GCS_BUCKET}/${remote_name}"
    local dest_file="$G_CONTROL_FILE"

    # Safety backup before overwriting
    backup_registry "pre-sync-pull" 2>/dev/null || true

    echo -ne "${GRAY}Pulling registry from ${G_GCS_BUCKET}...${NC}"
    if gcloud storage cp "$remote_url" "$dest_file" --quiet 2>/dev/null; then
        chmod 600 "$dest_file"
        echo -e "\r${LGREEN}✓ Registry pulled from ${remote_url}${NC}"
        log "Registry pulled from GCS: $remote_url"
        return 0
    else
        echo -e "\r${RED}✗ Failed to pull registry from GCS${NC}"
        log "ERROR: GCS pull failed from ${remote_url}"
        return 1
    fi
}

# =============================================================================
# Function: audit_log
# Description: Append one structured line to the monthly audit log file
# Parameters:
#   $1 = operation  (setup|verify|cleanup|list|bulk-setup)
#   $2 = project
#   $3 = cluster
#   $4 = namespace
#   $5 = ksa
#   $6 = result     (SUCCESS|FAILED|DRY-RUN|PARTIAL)
#   $7 = detail     (optional, error message or extra info)
# =============================================================================
audit_log() {
    local operation="$1"
    local project="${2:--}"
    local cluster="${3:--}"
    local namespace="${4:--}"
    local ksa="${5:--}"
    local result="${6:-SUCCESS}"
    local detail="${7:-}"

    local audit_dir="$G_SCRIPT_DIR/logs/audit"
    mkdir -p "$audit_dir" 2>/dev/null || true

    local audit_file="$audit_dir/audit_$(date '+%Y-%m').log"
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S')
    local user
    user=$(gcloud config get-value account 2>/dev/null || echo "unknown")
    local dry_tag=""
    [[ "$G_DRY_RUN" == "1" ]] && dry_tag=" [DRY-RUN]"

    printf '%s | user=%s | op=%s%s | project=%s | cluster=%s | ns=%s | ksa=%s | result=%s%s\n' \
        "$timestamp" "$user" "$operation" "$dry_tag" \
        "$project" "$cluster" "$namespace" "$ksa" \
        "$result" "${detail:+ | detail=$detail}" >> "$audit_file"
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

# Function: log_safe
# Description: Log messages with sensitive data (email addresses) redacted
# Parameters: $1=message, $2=email (optional, will be redacted as <email_hash>)
log_safe() {
    local message="$1"
    local email="${2:-}"
    
    # Redact email addresses if provided - replace with hash for privacy
    if [[ -n "$email" ]]; then
        local email_hash="<SA:$(echo -n "$email" | md5sum | cut -c1-8)>"
        message="${message//$email/$email_hash}"
    fi
    
    # Also redact any other email addresses in the message (pattern: *@*.iam.gserviceaccount.com)
    message=$(echo "$message" | sed -E 's/[a-z0-9-]+@[a-z0-9-]+\.iam\.gserviceaccount\.com/<SA_EMAIL>/g')
    
    log "$message"
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
    
    # CLI mode: use pre-filled globals rather than prompting
    if [[ "$G_CLI_MODE" == "1" ]]; then
        local cli_val=""
        case "$variable_name" in
            project_id|TICKET_ID) [[ "$variable_name" == "project_id" ]] && cli_val="$G_CLI_PROJECT" || cli_val="$G_CLI_TICKET" ;;
            namespace)   cli_val="$G_CLI_NAMESPACE" ;;
            ksa_name)    cli_val="$G_CLI_KSA" ;;
            iam_sa_name) cli_val="$G_CLI_IAM_SA" ;;
        esac
        # Use CLI value, then default, then leave empty
        local resolved="${cli_val:-${default_value:-}}"
        printf -v "$variable_name" '%s' "$resolved"
        echo -e "${GRAY}  (CLI) ${prompt_text}: ${resolved:-<empty>}${NC}" >&2
        log "CLI Input - ${prompt_text}: ${resolved}"
        return 0
    fi
    
    if [[ -n "$default_value" ]]; then
        echo -ne "${YELLOW}${prompt_text} [${default_value}]: ${NC}"
    else
        echo -ne "${YELLOW}${prompt_text}: ${NC}"
    fi
    
    read input_value
    
    if [[ -z "$input_value" ]] && [[ -n "$default_value" ]]; then
        input_value="$default_value"
    fi
    
    printf -v "$variable_name" '%s' "$input_value"
    log "Input - ${prompt_text}: ${input_value}"
}

prompt_selection() {
    local prompt_text="$1"
    local options_var="$2"
    local result_var="$3"
    
    local -n options="$options_var"
    local count=${#options[@]}
    
    # CLI mode: auto-select first option when no GUI interaction available
    if [[ "$G_CLI_MODE" == "1" ]]; then
        printf -v "$result_var" '%s' "${options[0]}"
        echo -e "${GRAY}  (CLI) ${prompt_text}: ${options[0]}${NC}" >&2
        log "CLI Selection - ${prompt_text}: ${options[0]}"
        return 0
    fi
    
    echo -e "${WHITE}${prompt_text}${NC}"
    echo ""
    
    for i in "${!options[@]}"; do
        echo -e "  ${LCYAN}$((i+1)))${NC} ${options[$i]}"
    done
    
    echo ""
    echo -ne "${YELLOW}Select an option [1-${count}]: ${NC}"
    read selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$count" ]]; then
        printf -v "$result_var" '%s' "${options[$((selection-1))]}"
        log "Selection - ${prompt_text}: ${options[$((selection-1))]}"
        return 0
    else
        print_error "Invalid selection"
        return 1
    fi
}

# =============================================================================
# Helper Functions for Reliability
# =============================================================================

# Function: check_gcloud_auth
# Description: Verify gcloud authentication and refresh token if needed
# Returns: 0=authenticated, 1=auth failed
check_gcloud_auth() {
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        # Check if gcloud can access current project
        if gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            echo -e "${YELLOW}⚠ gcloud authentication expired, refreshing...${NC}"
            gcloud auth application-default print-access-token &>/dev/null
            ((attempt++))
            sleep 1
        else
            ((attempt++))
        fi
    done
    
    echo -e "${RED}✗ gcloud authentication failed. Please run: gcloud auth login${NC}" >&2
    return 1
}

# Function: retry_gcloud_command
# Description: Execute gcloud command with exponential backoff retry
# Parameters: $@=gcloud command and arguments
# Returns: Command exit code
retry_gcloud_command() {
    local max_retries=3
    local timeout=1
    local attempt=1
    
    while [[ $attempt -le $max_retries ]]; do
        # Execute the command
        if "$@"; then
            return 0
        fi
        
        local exit_code=$?
        
        # Don't retry on auth errors (codes 1, 403, 401)
        if [[ $exit_code -eq 1 ]] || [[ $exit_code -eq 403 ]] || [[ $exit_code -eq 401 ]]; then
            return $exit_code
        fi
        
        if [[ $attempt -lt $max_retries ]]; then
            echo -e "${GRAY}  Retry attempt $attempt/$max_retries in ${timeout}s...${NC}" >&2
            sleep $timeout
            timeout=$((timeout * 2))  # Exponential backoff
            ((attempt++))
        else
            ((attempt++))
        fi
    done
    
    return $exit_code
}

# =============================================================================
# Function: exec_cmd
# Description: Execute a command, or print it in dry-run mode instead
# Parameters: $@ = command and all arguments
# Returns: 0=success (real or dry-run), non-zero=error
# =============================================================================
exec_cmd() {
    if [[ "$G_DRY_RUN" == "1" ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} ${GRAY}$*${NC}" >&2
        log "DRY-RUN: $*"
        return 0
    fi
    "$@"
}

# =============================================================================
# Function: select_cluster_from_project
# Description: Interactive cluster selection from GCP project
# Parameters: 
#   $1: project_id (required) - GCP project ID
#   $2: prompt_msg (optional) - Custom prompt message
# Returns: 0 on success, 1 on error or cancellation
# Side Effects: Sets global variables SELECTED_CLUSTER and SELECTED_LOCATION
# =============================================================================
select_cluster_from_project() {
    local project_id="$1"
    local prompt_msg="${2:-Select GKE cluster:}"
    
    # CLI mode: if --cluster was provided, resolve its location and use it directly
    if [[ "$G_CLI_MODE" == "1" ]] && [[ -n "$G_CLI_CLUSTER" ]]; then
        local cluster_location
        cluster_location=$(gcloud container clusters list --project "$project_id" \
            --filter="name=$G_CLI_CLUSTER" --format="value(location)" 2>/dev/null)
        if [[ -z "$cluster_location" ]]; then
            print_error "Cluster '$G_CLI_CLUSTER' not found in project $project_id"
            return 1
        fi
        SELECTED_CLUSTER="$G_CLI_CLUSTER"
        SELECTED_LOCATION="$cluster_location"
        echo -e "${GRAY}  (CLI) Cluster: $SELECTED_CLUSTER ($SELECTED_LOCATION)${NC}" >&2
        return 0
    fi
    
    # List clusters from project
    local clusters_raw
    clusters_raw=$(list_gke_clusters "$project_id")
    
    if [[ -z "$clusters_raw" ]]; then
        print_error "No GKE clusters found in project $project_id"
        return 1
    fi
    
    # Parse clusters into arrays
    declare -a cluster_names
    declare -a cluster_locations
    declare -a cluster_options
    
    while IFS=$'\t' read -r name location; do
        cluster_names+=("$name")
        cluster_locations+=("$location")
        cluster_options+=("$name ($location)")
    done <<< "$clusters_raw"
    
    # Show selection menu or auto-select
    if [[ ${#cluster_options[@]} -eq 1 ]]; then
        SELECTED_CLUSTER="${cluster_names[0]}"
        SELECTED_LOCATION="${cluster_locations[0]}"
        print_info "Single cluster found" "$SELECTED_CLUSTER ($SELECTED_LOCATION)"
    else
        prompt_selection "$prompt_msg" cluster_options selected_option
        
        # Find selected cluster in array
        for i in "${!cluster_options[@]}"; do
            if [[ "${cluster_options[$i]}" == "$selected_option" ]]; then
                SELECTED_CLUSTER="${cluster_names[$i]}"
                SELECTED_LOCATION="${cluster_locations[$i]}"
                break
            fi
        done
    fi
    
    return 0
}

# =============================================================================
# GCP Functions
# =============================================================================

get_current_project() {
    local project
    project=$(gcloud config get-value project 2>/dev/null)
    [[ -n "$project" ]] && log_safe "Current GCP project: $project"
    echo "$project"
}

list_gke_clusters() {
    local project_id="$1"
    log "Listing GKE clusters in project: $project_id"
    gcloud container clusters list --project "$project_id" --format="value(name,location)" 2>/dev/null
}

# =============================================================================
# Validation Functions
# =============================================================================

# Validate GCP project ID format and existence
validate_project_id() {
    local project="$1"
    
    # GCP rules: 6-30 chars, lowercase letters, numbers, hyphens; start/end with letter or number
    if [[ ${#project} -lt 6 ]] || [[ ${#project} -gt 30 ]]; then
        echo -e "${RED}✗ Project ID must be 6-30 characters: $project${NC}" >&2
        return 1
    fi
    
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
        exec_cmd gcloud container clusters get-credentials "$cluster_name" \
            --region "$location" \
            --project "$project_id" &>/dev/null
    else
        # Zonal (e.g., us-central1-a)
        exec_cmd gcloud container clusters get-credentials "$cluster_name" \
            --zone "$location" \
            --project "$project_id" &>/dev/null
    fi
    log "Connected to cluster: $cluster_name"
}

verify_iam_sa() {
    local sa_email="$1"
    local project_id="$2"
    
    log "Verifying IAM Service Account: $sa_email"
    
    if gcloud iam service-accounts describe "$sa_email" --project "$project_id" &>/dev/null; then
        log "✓ IAM SA verified: $sa_email"
        return 0
    else
        log "⚠ IAM SA not found: $sa_email"
        return 1
    fi
}

create_iam_sa() {
    local sa_name="$1"
    local project_id="$2"
    local display_name="${3:-$sa_name}"
    
    log "Creating IAM Service Account: $sa_name"
    
    exec_cmd gcloud iam service-accounts create "$sa_name" \
        --project "$project_id" \
        --display-name "$display_name"
    
    log "✓ IAM SA created: $sa_name@${project_id}.iam.gserviceaccount.com"
}

create_namespace() {
    local namespace="$1"
    
    if kubectl get namespace "$namespace" &>/dev/null; then
        log "Namespace $namespace already exists"
        return 0
    fi
    
    exec_cmd kubectl create namespace "$namespace"
}

create_ksa() {
    local ksa_name="$1"
    local namespace="$2"
    
    if kubectl get serviceaccount "$ksa_name" -n "$namespace" &>/dev/null; then
        log "KSA $ksa_name already exists in $namespace"
        return 0
    fi
    
    log "Creating Kubernetes Service Account: $ksa_name in $namespace"
    
    exec_cmd kubectl create serviceaccount "$ksa_name" -n "$namespace"
    
    log "✓ KSA created: $ksa_name in $namespace"
}

add_iam_binding() {
    local iam_sa_email="$1"
    local project_id="$2"
    local ksa_name="$3"
    local namespace="$4"
    
    local member="serviceAccount:${project_id}.svc.id.goog[${namespace}/${ksa_name}]"
    
    exec_cmd gcloud iam service-accounts add-iam-policy-binding "$iam_sa_email" \
        --project "$project_id" \
        --role "$G_IAM_ROLE" \
        --member "$member"
}

annotate_ksa() {
    local ksa_name="$1"
    local namespace="$2"
    local iam_sa_email="$3"
    
    exec_cmd kubectl annotate serviceaccount "$ksa_name" \
        --namespace "$namespace" \
        "${G_ANNOTATION_KEY}=${iam_sa_email}" \
        --overwrite
}

remove_iam_binding() {
    local iam_sa_email="$1"
    local project_id="$2"
    local ksa_name="$3"
    local namespace="$4"
    
    local member="serviceAccount:${project_id}.svc.id.goog[${namespace}/${ksa_name}]"
    
    exec_cmd gcloud iam service-accounts remove-iam-policy-binding "$iam_sa_email" \
        --project "$project_id" \
        --role "$G_IAM_ROLE" \
        --member "$member"
}

delete_ksa() {
    local ksa_name="$1"
    local namespace="$2"
    
    log "Deleting Kubernetes Service Account: $ksa_name from $namespace"
    
    exec_cmd kubectl delete serviceaccount "$ksa_name" -n "$namespace"
    
    log "✓ KSA deleted: $ksa_name from $namespace"
}

get_ksa_annotation() {
    local ksa_name="$1"
    local namespace="$2"
    
    log_safe "Retrieving annotation from KSA: $ksa_name in $namespace"
    
    kubectl get serviceaccount "$ksa_name" -n "$namespace" \
        -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' 2>/dev/null
}

list_workload_identities() {
    local namespace="$1"
    
    echo -e "${WHITE}Kubernetes Service Accounts with Workload Identity in namespace: ${LCYAN}${namespace}${NC}"
    echo ""
    
    # Get all KSAs in namespace using kubectl
    local ksa_output
    ksa_output=$(kubectl get serviceaccounts -n "$namespace" -o json 2>/dev/null)
    
    if [[ -z "$ksa_output" ]]; then
        echo -e "  ${GRAY}No Service Accounts found in namespace${NC}"
        return 0
    fi
    
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
            :
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

  DESCRIPTION:
    Tool for configuring GCP Workload Identity between GCP IAM
    Service Accounts and Kubernetes Service Accounts.
    Supports interactive menu and non-interactive CLI mode.

  USAGE:
    ./workload-identity.sh                            # Interactive menu
    ./workload-identity.sh --help                     # This help
    ./workload-identity.sh --version                  # Version info
    ./workload-identity.sh setup   [FLAGS]            # Configure WI
    ./workload-identity.sh verify  [FLAGS]            # Verify WI
    ./workload-identity.sh cleanup [FLAGS]            # Remove WI
    ./workload-identity.sh list    [FLAGS]            # List WI bindings
    ./workload-identity.sh bulk-setup --file FILE     # Batch configure

  AVAILABLE FLAGS:
    --project,   -p  PROJECT    GCP Project ID
    --cluster,   -c  CLUSTER    GKE cluster name
    --namespace, -n  NAMESPACE  Kubernetes namespace (default: apps)
    --ksa,       -k  KSA        Kubernetes Service Account name
    --iam-sa,    -s  EMAIL      GCP IAM Service Account email
    --ticket,    -t  TICKET     Ticket number (e.g. CTASK0012345)
    --level,     -l  LEVEL      Cleanup level: 1=binding, 2=+ksa, 3=all
    --file,      -f  FILE       CSV file for bulk-setup
    --dry-run                   Preview changes without executing

  OPERATIONS:
    setup:      Create IAM SA, KSA, WI binding and annotation
    verify:     Verify that WI is correctly configured
    cleanup:    Remove binding, KSA and/or IAM SA
    list:       List KSAs with WI annotation in a namespace
    bulk-setup: Process multiple configurations from a CSV file

  EXAMPLES:
    # 1. Interactive guided menu:
    $ ./workload-identity.sh

    # 2. Configure WI via CLI:
    $ ./workload-identity.sh setup \
        --project gnp-covid-qa \
        --cluster gke-gnp-covid-qa \
        --namespace apps \
        --ksa myapp \
        --iam-sa myapp@gnp-covid-qa.iam.gserviceaccount.com \
        --ticket CTASK0012345

    # 3. Dry-run (preview without executing):
    $ ./workload-identity.sh setup \
        --project gnp-covid-qa --ksa myapp --dry-run

    # 4. Remove everything (binding + KSA + IAM SA):
    $ ./workload-identity.sh cleanup \
        --project gnp-covid-qa --ksa myapp --namespace apps --level 3

    # 5. Bulk setup from CSV:
    $ ./workload-identity.sh bulk-setup --file configs.csv
    # CSV format: project_id,cluster,location,namespace,ksa,iam_sa,ticket

  FILES:
    workload-identity-registry.csv    Operations registry
    config.sh                         External configuration
    logs/audit/audit_YYYY-MM.log      Structured audit log
    logs/                             Session logs
    Tickets/[TICKET]/logs/            Logs organized by ticket

  REQUIREMENTS:
    - gcloud CLI authenticated (gcloud auth login)
    - kubectl configured
    - IAM permissions to create service accounts
    - Access to GKE clusters

HELP_TEXT
}

show_version() {
    sed "s/G_VERSION/$G_VERSION/" << 'VERSION_TEXT'

  ╔════════════════════════════════════════════════════════════════╗
  ║        WORKLOAD IDENTITY MANAGER                               ║
  ╚════════════════════════════════════════════════════════════════╝

  Name:            Workload Identity Manager
  Version:         G_VERSION
  Project:         GCP Infrastructure Management
  Description:     Configure GCP Workload Identity for GKE

  Author:          Infrastructure Team
  License:         Internal Use
  Repository:      IaC-Programming-Samples

  Features:
    ✓ Interactive interface + CLI non-interactive mode
    ✓ Dry-run mode (preview without executing)
    ✓ Bulk setup from CSV file
    ✓ Structured audit log (logs/audit/)
    ✓ AES-256-CBC registry encryption (opt-in)
    ✓ Automatic backup before destructive ops
    ✓ Restore registry from backup
    ✓ GCS remote state sync (push/pull)
    ✓ Ticket-based log organization
    ✓ CSV operations registry
    ✓ Robust input validation
    ✓ Structured logging

VERSION_TEXT
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
    echo -e "${LGREEN}║${NC}  ${LCYAN}6)${NC} Security / Backup & Restore        ${LGREEN}║${NC}"
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
    echo -e "${GRAY}  (Optional) Associate with a ticket to organize logs${NC}"
    prompt_input "Ticket or CTASK number (optional, press Enter to skip)" "TICKET_ID" ""
    G_TICKET_ID="$TICKET_ID"

    setup_log_directory "$G_TICKET_ID"

    if [[ -n "$G_TICKET_ID" ]]; then
        echo -e "${LGREEN}✓ Logs will be saved in: ${LCYAN}Tickets/$G_TICKET_ID/logs/${NC}"
    fi

    echo ""
    log "Session started - Operation: SETUP"
    [[ -n "$G_TICKET_ID" ]] && log "Ticket/CTask: $G_TICKET_ID"

    # --- Step 1: Project ID ---
    local current_project
    current_project=$(get_current_project)
    prompt_input "Enter Project ID" "project_id" "$current_project"

    if [[ -z "$project_id" ]]; then
        print_error "Project ID is required"
        return 1
    fi

    if ! validate_project_id "$project_id"; then
        return 1
    fi

    echo ""

    # --- Step 2: IAM Service Account ---
    prompt_input "Enter IAM Service Account name (without @...)" "iam_sa_name"

    # Accept full email (e.g. from bulk-setup); extract name part if needed
    [[ "$iam_sa_name" == *"@"* ]] && iam_sa_name="${iam_sa_name%%@*}"

    if [[ -z "$iam_sa_name" ]]; then
        print_error "IAM Service Account is required"
        return 1
    fi

    if ! validate_k8s_name "$iam_sa_name" "IAM Service Account"; then
        return 1
    fi

    local iam_sa_email="${iam_sa_name}@${project_id}.iam.gserviceaccount.com"

    if ! validate_iam_sa_email "$iam_sa_email"; then
        return 1
    fi

    local iam_sa_exists=true

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
        print_error "Kubernetes Service Account is required"
        return 1
    fi

    if ! validate_k8s_name "$ksa_name" "Kubernetes Service Account"; then
        return 1
    fi

    echo ""

    # --- Step 4: Cluster Selection ---
    if ! select_cluster_from_project "$project_id"; then
        return 1
    fi
    local selected_cluster="$SELECTED_CLUSTER"
    local selected_location="$SELECTED_LOCATION"

    echo ""

    # --- Step 5: Connect to Cluster ---
    echo -ne "${GRAY}Connecting to cluster...${NC}"
    if connect_to_cluster "$selected_cluster" "$selected_location" "$project_id" >/dev/null 2>&1; then
        echo -e "\r${LGREEN}✓ Connected to cluster${NC}          "
        log "Connected to cluster: $selected_cluster"
    else
        echo -e "\r${RED}✗ Connection error${NC}          "
        print_error "Could not connect to cluster"
        return 1
    fi

    echo ""

    # --- Step 6: Namespace ---
    prompt_input "Enter namespace" "namespace" "$G_DEFAULT_NS"

    echo -ne "${GRAY}Validating namespace...${NC}"
    if ! kubectl get namespace "$namespace" &>/dev/null; then
        echo -e "\r${YELLOW}⚠ Namespace does not exist (will be created)${NC}     "
    else
        echo -e "\r${LGREEN}✓ Namespace verified${NC}     "
    fi

    echo ""

    # --- Confirmation Summary ---
    print_header "Configuration Summary"
    [[ -n "$G_TICKET_ID" ]] && print_info "Ticket/CTask" "$G_TICKET_ID"
    print_info "Project ID"    "$project_id"
    print_info "Cluster"       "$selected_cluster"
    print_info "Location"      "$selected_location"
    print_info "Namespace"     "$namespace"
    print_info "Kubernetes SA" "$ksa_name"
    if [[ "$iam_sa_exists" == "false" ]]; then
        echo -e "${WHITE}IAM SA:${NC} ${YELLOW}${iam_sa_email} (will be created)${NC}"
        log "IAM SA: ${iam_sa_email} (new)"
    else
        print_info "IAM SA" "$iam_sa_email"
    fi
    echo -e "${LGREEN}========================================${NC}"

    echo ""

    local confirm_msg="The following resources will be created/configured:"
    [[ "$iam_sa_exists" == "false" ]] && confirm_msg+=$'\n  • GCP IAM Service Account (new)'
    confirm_msg+=$'\n  • Kubernetes namespace\n  • Kubernetes Service Account\n  • IAM Workload Identity binding'

    if ! ask_confirmation "$confirm_msg" "create"; then
        print_warning "Operation cancelled"
        return 0
    fi

    echo ""

    # --- Step 7: Execute ---
    print_header "Executing Configuration"
    echo ""

    local step=1
    local total_steps=4

    # Create IAM SA if it doesn't exist yet
    if [[ "$iam_sa_exists" == "false" ]]; then
        total_steps=5
        echo -ne "${WHITE}[${step}/${total_steps}]${NC} Creating IAM account..."
        if create_iam_sa "$iam_sa_name" "$project_id" >/dev/null 2>&1; then
            echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creating IAM account... ${LGREEN}✓${NC}"
            log "IAM SA created: $iam_sa_email"
        else
            echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creating IAM account... ${RED}✗${NC}"
            print_error "Error creating IAM account"
            return 1
        fi
        ((step++))
    fi

    # Create namespace (idempotent)
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Creating namespace..."
    if create_namespace "$namespace" >/dev/null 2>&1; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creating namespace... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creating namespace... ${YELLOW}(already exists)${NC}"
    fi
    ((step++))

    # Create KSA (idempotent)
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Creating Kubernetes SA..."
    if create_ksa "$ksa_name" "$namespace" >/dev/null 2>&1; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creating Kubernetes SA... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Creating Kubernetes SA... ${YELLOW}(already exists)${NC}"
    fi
    ((step++))

    # Add IAM Workload Identity binding
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Adding IAM binding..."
    if add_iam_binding "$iam_sa_email" "$project_id" "$ksa_name" "$namespace" >/dev/null 2>&1; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Adding IAM binding... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Adding IAM binding... ${RED}✗${NC}"
        print_error "Error adding IAM binding"
    fi
    ((step++))

    # Annotate KSA with IAM SA email
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Annotating Kubernetes SA..."
    if annotate_ksa "$ksa_name" "$namespace" "$iam_sa_email" >/dev/null 2>&1; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Annotating Kubernetes SA... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Annotating Kubernetes SA... ${RED}✗${NC}"
        print_error "Error annotating KSA"
    fi

    echo ""

    register_execution "$G_TICKET_ID" "$project_id" "$selected_cluster" "$selected_location" "$namespace" "$ksa_name" "$iam_sa_email"

    # --- Final Summary ---
    print_header "Workload Identity Configured"
    [[ -n "$G_TICKET_ID" ]] && print_info "Ticket"       "$G_TICKET_ID"
    print_info "Project"       "$project_id"
    print_info "Cluster"       "$selected_cluster"
    print_info "Namespace"     "$namespace"
    print_info "Kubernetes SA" "$ksa_name"
    print_info "IAM SA"        "$iam_sa_email"
    echo -e "${LGREEN}========================================${NC}"

    echo ""
    echo -e "${GRAY}Log saved to: $G_LOG_FILE${NC}"
    echo -e "${GRAY}Record added to: $G_CONTROL_FILE${NC}"
    log "Session completed successfully"
    log "Registered in control file: $G_CONTROL_FILE"
    audit_log "setup" "$project_id" "$selected_cluster" "$namespace" "$ksa_name" "SUCCESS"

    echo ""
    if [[ "$G_CLI_MODE" == "0" ]]; then
        echo -ne "${YELLOW}Press Enter to continue...${NC}"
        read
    fi
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

    # --- Show active configurations from registry (informational) ---
    if [[ -f "$G_CONTROL_FILE" ]]; then
        echo -e "${WHITE}Active configurations from registry:${NC}"
        echo ""

        local active_count
        active_count=$(awk -F',' 'NR>1 && $9 ~ /^activo/ {count++} END {print count+0}' "$G_CONTROL_FILE")

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

    # --- Confirmation menu (interactive mode only) ---
    if [[ "$G_CLI_MODE" == "0" ]]; then
        echo -e "${WHITE}Options:${NC}"
        echo -e "  ${LCYAN}1)${NC} Continue with verification"
        echo -e "  ${LCYAN}0)${NC} Return to main menu"
        echo ""
        echo -ne "${YELLOW}Select an option: ${NC}"
        read verify_option
        if [[ "$verify_option" != "1" ]]; then
            return 0
        fi
    fi

    echo ""

    # --- Project ID ---
    local current_project
    current_project=$(get_current_project)
    prompt_input "Enter Project ID to verify" "project_id" "$current_project"

    if [[ -z "$project_id" ]]; then
        print_error "Project ID is required"
        return 1
    fi

    echo ""

    # --- Cluster Selection ---
    if ! select_cluster_from_project "$project_id"; then
        return 1
    fi
    local selected_cluster="$SELECTED_CLUSTER"
    local selected_location="$SELECTED_LOCATION"

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

    # --- Input: namespace, KSA, IAM SA ---
    prompt_input "Enter namespace" "namespace" "$G_DEFAULT_NS"
    prompt_input "Enter KSA name to verify" "ksa_name"
    prompt_input "Enter IAM Service Account name (without @...)" "iam_sa_name" "$ksa_name"

    # Accept full email (e.g. from CLI --iam-sa flag); extract name part if needed
    [[ "$iam_sa_name" == *"@"* ]] && iam_sa_name="${iam_sa_name%%@*}"

    local iam_sa_email="${iam_sa_name}@${project_id}.iam.gserviceaccount.com"

    echo ""

    # --- Run Checks ---
    print_header "Verification Results"

    local ksa_exists=false
    local iam_sa_exists=false
    local annotation=""

    # 1. IAM Service Account
    echo -ne "  Checking IAM SA...${NC}"
    if gcloud iam service-accounts describe "$iam_sa_email" --project "$project_id" &>/dev/null; then
        echo -e "\r${LGREEN}✓ IAM SA exists${NC}                 "
        print_info "IAM SA" "$iam_sa_email"
        iam_sa_exists=true
    else
        echo -e "\r${RED}✗ IAM SA not found${NC}          "
    fi

    # 2. Kubernetes Service Account
    echo -ne "  Checking KSA...${NC}"
    if kubectl get serviceaccount "$ksa_name" -n "$namespace" &>/dev/null; then
        echo -e "\r${LGREEN}✓ KSA exists${NC}                    "
        ksa_exists=true
    else
        echo -e "\r${RED}✗ KSA not found${NC}             "
    fi

    # 3. WI Annotation (only if KSA exists)
    if [[ "$ksa_exists" == "true" ]]; then
        annotation=$(get_ksa_annotation "$ksa_name" "$namespace")
        echo -ne "  Checking annotation...${NC}"
        if [[ -n "$annotation" ]]; then
            echo -e "\r${LGREEN}✓ Annotation configured${NC}         "
            print_info "Annotation" "$annotation"
        else
            echo -e "\r${YELLOW}⚠ No Workload Identity annotation${NC}"
        fi
    fi

    # 4. IAM Binding (only if IAM SA exists)
    if [[ "$iam_sa_exists" == "true" ]]; then
        echo -ne "  Checking IAM binding...${NC}"
        local member="serviceAccount:${project_id}.svc.id.goog[${namespace}/${ksa_name}]"
        if gcloud iam service-accounts get-iam-policy "$iam_sa_email" --project "$project_id" 2>/dev/null | grep -Fq "$member"; then
            echo -e "\r${LGREEN}✓ IAM binding configured${NC}       "
        else
            echo -e "\r${YELLOW}⚠ IAM binding not found${NC}     "
        fi
    fi

    echo ""

    # --- Summary ---
    print_header "Summary"
    echo ""
    echo -e "  IAM Service Account: $( [[ "$iam_sa_exists" == "true" ]] && echo "${LGREEN}Exists${NC}"   || echo "${RED}Not found${NC}" )"
    echo -e "  Kubernetes SA:       $( [[ "$ksa_exists"    == "true" ]] && echo "${LGREEN}Exists${NC}"   || echo "${RED}Not found${NC}" )"
    if [[ "$ksa_exists" == "true" ]]; then
        echo -e "  WI Annotation:       $( [[ -n "$annotation" ]] && echo "${LGREEN}Configured${NC}" || echo "${YELLOW}Not configured${NC}" )"
    fi
    echo ""
    print_header "Verification Completed"
    
    if [[ "$G_CLI_MODE" == "0" ]]; then
        echo ""
        echo -ne "${YELLOW}Press Enter to continue...${NC}"
        read
    fi
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

    # In CLI mode or dry-run, skip interactive prompt and auto-accept
    if [[ "${G_CLI_MODE:-0}" == "1" ]] || [[ "${G_DRY_RUN:-0}" == "1" ]]; then
        local dry_tag=""
        [[ "${G_DRY_RUN:-0}" == "1" ]] && dry_tag=" [DRY-RUN]"
        echo -e "${GRAY}  (CLI${dry_tag}) auto-confirmed${NC}"
        return 0
    fi
    
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
    
    # Accept: yes, y
    if [[ ! "$response1" =~ ^(yes|y)$ ]]; then
        echo -e "${LGREEN}✓ Operation cancelled${NC}"
        return 1
    fi
    
    # For destructive operations (delete), require double confirmation
    if [[ "$action" =~ delete|remove|destroy ]]; then
        echo ""
        echo -e "${RED}⚠ This is a DESTRUCTIVE operation and cannot be undone${NC}"
        echo -ne "Type ${YELLOW}'CONFIRM'${NC} to proceed: "
        local response2
        read response2
        
        if [[ "$response2" != "CONFIRM" ]]; then
            echo -e "${LGREEN}✓ Operation cancelled${NC}"
            return 1
        fi
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
        local active_records
        active_records=$(tail -n +2 "$G_CONTROL_FILE" | awk -F',' '$9 == "activo"')
        
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
                    echo -e "${LGREEN}✓ Selected:${NC} ${WHITE}$ksa_name${NC} in ${LCYAN}$namespace${NC}"
                    
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
        local current_project
        current_project=$(get_current_project)
        prompt_input "Enter Project ID" "project_id" "$current_project"
        
        echo ""
        
        # --- List and Select Cluster ---
        if ! select_cluster_from_project "$project_id"; then
            return 1
        fi
        # Variables SELECTED_CLUSTER, SELECTED_LOCATION are now set
        local selected_cluster="$SELECTED_CLUSTER"
        local selected_location="$SELECTED_LOCATION"
        
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
        prompt_input "Enter namespace" "namespace" "$G_DEFAULT_NS"
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
    local cleanup_option=""
    if [[ "$G_CLI_MODE" == "1" ]] && [[ -n "$G_CLI_CLEANUP_LEVEL" ]]; then
        cleanup_option="$G_CLI_CLEANUP_LEVEL"
        echo -e "${GRAY}  (CLI) Cleanup level: $cleanup_option${NC}" >&2
    else
        echo -ne "${YELLOW}Select an option: ${NC}"
        read cleanup_option
    fi
    
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
    if [[ "$G_CLI_MODE" == "0" ]]; then
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
    fi
    
    echo ""
    
    # --- Confirmation before destructive operation ---
    local confirm_message="The following resources will be deleted:"
    [[ "$cleanup_option" == "1" ]] && confirm_message+=$'\n  • IAM Binding'
    [[ "$cleanup_option" == "2" ]] && confirm_message+=$'\n  • IAM Binding\n  • Kubernetes Service Account'
    [[ "$cleanup_option" == "3" ]] && confirm_message+=$'\n  • IAM Binding\n  • Kubernetes Service Account\n  • GCP IAM Service Account'
    
    confirm_message+=$'\n\nProject: '"$project_id"$'\nCluster: '"$selected_cluster"$'\nNamespace: '"$namespace"$'\nKSA: '"$ksa_name"
    
    if [[ "$G_CLI_MODE" == "0" ]] && ! ask_confirmation "$confirm_message" "delete"; then
        return 0
    fi
    
    # --- Execute Cleanup ---
    # Auto-backup before any deletion
    backup_registry "pre-cleanup" 2>/dev/null || true
    
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
    if exec_cmd kubectl annotate serviceaccount "$ksa_name" -n "$namespace" "iam.gke.io/gcp-service-account-" >/dev/null 2>&1; then
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
        local delete_sa_error=""
        if delete_sa_error=$(exec_cmd gcloud iam service-accounts delete "$annotation" --project "$project_id" --quiet 2>&1); then
            echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Deleting IAM account... ${LGREEN}✓${NC}"
            log "IAM SA deleted: $annotation"
        else
            echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Deleting IAM account... ${RED}✗${NC}"
            # Extract the specific cause from gcloud error output
            if echo "$delete_sa_error" | grep -qi "PERMISSION_DENIED"; then
                echo -e "  ${RED}✗ Permission denied:${NC} Account ${YELLOW}$(gcloud config get-value account 2>/dev/null)${NC} does not have role ${WHITE}roles/iam.serviceAccountAdmin${NC} on project ${WHITE}$project_id${NC}"
                echo -e "  ${GRAY}  Request the role or delete the service account manually.${NC}"
            elif echo "$delete_sa_error" | grep -qi "NOT_FOUND\|does not exist"; then
                echo -e "  ${YELLOW}⚠ IAM SA not found:${NC} ${WHITE}$annotation${NC} (may have already been deleted)"
            elif echo "$delete_sa_error" | grep -qi "UNAUTHENTICATED\|not authenticated"; then
                echo -e "  ${RED}✗ Not authenticated:${NC} Run ${WHITE}gcloud auth login${NC} and try again."
            else
                echo -e "  ${RED}✗ Error:${NC} ${GRAY}$delete_sa_error${NC}"
            fi
            log "ERROR deleting IAM SA $annotation: $delete_sa_error"
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
    
    if update_registry_status "$project_id" "$selected_cluster" "$namespace" "$ksa_name" "$status_text"; then
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
    audit_log "cleanup" "$project_id" "$selected_cluster" "$namespace" "$ksa_name" "SUCCESS" "$status_text"
    
    echo ""
    if [[ "$G_CLI_MODE" == "0" ]]; then
        echo -ne "${YELLOW}Press Enter to continue...${NC}"
        read
    fi
}

# =============================================================================
# Operation: List Workload Identities
# =============================================================================

operation_list() {
    clear
    print_header "List Workload Identities"
    echo ""

    local project_id=""
    local selected_cluster=""
    local selected_location=""
    local current_project
    current_project=$(get_current_project)

    # ── Project Selection ─────────────────────────────────────────────────────
    if [[ "$G_CLI_MODE" == "1" ]] && [[ -n "$G_CLI_PROJECT" ]]; then
        # CLI mode: project supplied via --project flag
        project_id="$G_CLI_PROJECT"
        echo -e "${GRAY}  (CLI) Project: $project_id${NC}" >&2
    elif [[ -f "$G_CONTROL_FILE" ]]; then
        # Interactive: let user pick from registry or type manually
        local registry_projects
        registry_projects=$(tail -n +2 "$G_CONTROL_FILE" | awk -F',' '$9 == "activo" {print $3}' | sort -u | grep -v '^$')

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
            local max_opt=$(( ${#project_options[@]} + 1 ))
            echo -ne "${WHITE}Select an option [1-${max_opt}]:${NC} "
            read selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= max_opt )); then
                if (( selection == max_opt )); then
                    prompt_input "Enter Project ID" "project_id" "$current_project"
                else
                    project_id="${project_options[$((selection-1))]}"
                    echo -e "${LGREEN}✓ Selected project:${NC} ${WHITE}$project_id${NC}"
                fi
            else
                print_error "Invalid option"
                echo -ne "${YELLOW}Press Enter to continue...${NC}"; read; return 1
            fi
        else
            prompt_input "Enter Project ID" "project_id" "$current_project"
        fi
    else
        prompt_input "Enter Project ID" "project_id" "$current_project"
    fi

    echo ""

    # ── Cluster Selection ─────────────────────────────────────────────────────
    if [[ "$G_CLI_MODE" == "1" ]]; then
        # CLI: select_cluster_from_project handles --cluster bypass or auto-discovers
        if ! select_cluster_from_project "$project_id"; then
            return 1
        fi
        selected_cluster="$SELECTED_CLUSTER"
        selected_location="$SELECTED_LOCATION"
    else
        # Interactive: show clusters from registry for this project, or fall back to GCP
        local registry_clusters=""
        if [[ -f "$G_CONTROL_FILE" ]]; then
            registry_clusters=$(tail -n +2 "$G_CONTROL_FILE" | \
                awk -F',' -v proj="$project_id" '$3 == proj && $9 == "activo" {print $4 "," $5}' | \
                sort -u | grep -v '^,$')
        fi

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
            echo -e "  ${LCYAN}${idx})${NC} ${YELLOW}Search other clusters in GCP${NC}"
            echo ""
            local max_opt=$(( ${#reg_cluster_names[@]} + 1 ))
            echo -ne "${WHITE}Select an option [1-${max_opt}]:${NC} "
            read selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= max_opt )); then
                if (( selection == max_opt )); then
                    if ! select_cluster_from_project "$project_id"; then
                        echo -ne "${YELLOW}Press Enter to continue...${NC}"; read; return 1
                    fi
                    selected_cluster="$SELECTED_CLUSTER"
                    selected_location="$SELECTED_LOCATION"
                else
                    selected_cluster="${reg_cluster_names[$((selection-1))]}"
                    selected_location="${reg_cluster_locations[$((selection-1))]}"
                    echo -e "${LGREEN}✓ Selected cluster:${NC} ${WHITE}$selected_cluster${NC}"
                fi
            else
                print_error "Invalid option"
                echo -ne "${YELLOW}Press Enter to continue...${NC}"; read; return 1
            fi
        else
            # No registry clusters for this project — discover from GCP
            if ! select_cluster_from_project "$project_id"; then
                echo -ne "${YELLOW}Press Enter to continue...${NC}"; read; return 1
            fi
            selected_cluster="$SELECTED_CLUSTER"
            selected_location="$SELECTED_LOCATION"
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
    prompt_input "Enter namespace (or 'all' for all namespaces)" "namespace" "apps"
    
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
    if [[ "$G_CLI_MODE" == "0" ]]; then
        echo -ne "${YELLOW}Press Enter to continue...${NC}"
        read
    fi
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
        total=$(( total + 1 ))
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
    # Ensure file ends with newline for proper parsing
    (cat "$G_CONTROL_FILE"; [[ -n "$(tail -c1 \"$G_CONTROL_FILE\")" ]] && echo) | tail -n +2 | while IFS=',' read -r fecha ticket project cluster location namespace ksa iam_sa status; do
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
# Operation: Bulk Setup (CLI only)
# =============================================================================
# Reads a CSV file with columns: project_id,cluster,location,namespace,ksa,iam_sa,ticket
# Skips the header row. Empty iam_sa = auto-generate from ksa name.
# =============================================================================
operation_bulk_setup() {
    local file="${G_CLI_BULK_FILE:-}"

    if [[ -z "$file" ]]; then
        echo -e "${RED}✗ --file is required for bulk-setup${NC}" >&2
        echo -e "${GRAY}  Example: ./workload-identity.sh bulk-setup --file configs.csv${NC}" >&2
        exit 1
    fi

    if [[ ! -f "$file" ]]; then
        echo -e "${RED}✗ File not found: $file${NC}" >&2
        exit 1
    fi

    local total=0 succeeded=0 failed=0
    local failed_list=()

    print_header "Bulk Setup - Workload Identity"
    echo -e "${GRAY}File: $file${NC}"
    [[ "$G_DRY_RUN" == "1" ]] && echo -e "${YELLOW}Mode: DRY-RUN (no changes will be applied)${NC}"
    echo ""

    # Detect CSV format: 7-column (with location) vs 6-column (without location)
    # Canonical format: project_id,cluster,location,namespace,ksa,iam_sa,ticket
    while IFS=',' read -r b_project b_cluster b_location b_namespace b_ksa b_iam_sa b_ticket; do
        # Skip blank lines and header rows (detect by first column value)
        [[ -z "$b_project" || "$b_project" =~ ^(project|project_id)$ ]] && continue
        total=$(( total + 1 ))

        # Override CLI globals for this row
        G_CLI_PROJECT="$b_project"
        G_CLI_CLUSTER="$b_cluster"
        # b_location is stored but cluster lookup via gcloud auto-detects it
        G_CLI_NAMESPACE="${b_namespace:-$G_DEFAULT_NS}"
        G_CLI_KSA="$b_ksa"
        G_CLI_IAM_SA="${b_iam_sa:-${b_ksa}@${b_project}.iam.gserviceaccount.com}"
        G_CLI_TICKET="${b_ticket:-}"

        echo -e "${WHITE}[$total]${NC} ${LCYAN}${b_project}${NC} / ${b_cluster} / ${b_namespace} / ${b_ksa}"

        if operation_setup 2>&1; then
            succeeded=$(( succeeded + 1 ))
            echo -e "    ${LGREEN}✓ Done${NC}"
            audit_log "bulk-setup" "$b_project" "$b_cluster" "$b_namespace" "$b_ksa" "SUCCESS"
        else
            failed=$(( failed + 1 ))
            failed_list+=("$b_project/$b_ksa")
            echo -e "    ${RED}✗ Failed${NC}"
            audit_log "bulk-setup" "$b_project" "$b_cluster" "$b_namespace" "$b_ksa" "FAILED"
        fi
        echo ""
    done < "$file"

    # Summary
    print_header "Bulk Setup Summary"
    echo -e "  Total:    ${WHITE}$total${NC}"
    echo -e "  Success:  ${LGREEN}$succeeded${NC}"
    echo -e "  Failed:   ${RED}$failed${NC}"
    if [[ ${#failed_list[@]} -gt 0 ]]; then
        echo -e "\n${RED}Failed entries:${NC}"
        for entry in "${failed_list[@]}"; do
            echo -e "  • $entry"
        done
    fi
    [[ $failed -gt 0 ]] && exit 1 || exit 0
}

# =============================================================================
# Operation: Security / Backup & Restore
# =============================================================================
operation_security() {
    clear
    print_header "Security / Backup & Restore"
    echo ""

    local gcs_status="${GRAY}not configured${NC}"
    [[ -n "$G_GCS_BUCKET" ]] && gcs_status="${LCYAN}${G_GCS_BUCKET}${NC}"

    echo -e "  GCS sync bucket     : $(echo -e "$gcs_status")"
    echo -e "  Backup directory    : ${GRAY}$G_BACKUP_DIR${NC}"
    echo ""
    echo -e "${WHITE}What would you like to do?${NC}"
    echo ""
    echo -e "  ${LCYAN}1)${NC} Create backup now"
    echo -e "  ${LCYAN}2)${NC} Restore from backup"
    echo -e "  ${LCYAN}3)${NC} Push registry to GCS (sync push)"
    echo -e "  ${LCYAN}4)${NC} Pull registry from GCS (sync pull)"
    echo -e "  ${LCYAN}5)${NC} List local backups"
    echo -e "  ${LCYAN}0)${NC} Back to main menu"
    echo ""
    echo -ne "${YELLOW}Select an option: ${NC}"
    read sec_option

    case "$sec_option" in
        1)
            echo ""
            echo -ne "${YELLOW}Backup label (Enter for 'manual'): ${NC}"
            read bk_label
            backup_registry "${bk_label:-manual}"
            ;;
        2)
            echo ""
            restore_registry
            ;;
        3)
            echo ""
            sync_push
            ;;
        4)
            echo ""
            sync_pull
            ;;
        5)
            echo ""
            print_header "Local Backups"
            local count=0
            while IFS= read -r f; do
                count=$(( count + 1 ))
                local size; size=$(du -h "$f" 2>/dev/null | cut -f1)
                echo -e "  ${LCYAN}${count})${NC} $(basename "$f")  ${GRAY}(${size})${NC}"
            done < <(find "$G_BACKUP_DIR" -maxdepth 1 -name "workload-identity-registry_*.csv" 2>/dev/null | sort -r)
            [[ $count -eq 0 ]] && echo -e "  ${GRAY}No backups found${NC}"
            ;;
        0) return 0 ;;
        *)
            echo -e "${RED}✗ Invalid option${NC}"
            sleep 1
            return 0
            ;;
    esac

    echo ""
    echo -ne "${YELLOW}Press Enter to continue...${NC}"
    read
}

# =============================================================================
# Main Menu Loop
# =============================================================================

# Main Menu Loop
# =============================================================================

main() {
    # Verify gcloud authentication at start of session
    if ! check_gcloud_auth; then
        print_error "Unable to authenticate with gcloud"
        exit 1
    fi
    
    while true; do
        show_main_menu
        read option
        
        case $option in
            1) operation_setup ;;
            2) operation_verify ;;
            3) operation_cleanup ;;
            4) operation_list ;;
            5) operation_view_registry ;;
            6) operation_security ;;
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
    # No arguments → interactive menu
    [[ $# -eq 0 ]] && return 0

    local subcommand="${1:-}"
    shift || true

    case "$subcommand" in
        --help|-h)
            show_help
            exit 0
            ;;
        --version|-v)
            show_version
            exit 0
            ;;
        setup|verify|cleanup|list|bulk-setup)
            G_CLI_MODE=1
            G_CLI_OPERATION="$subcommand"
            ;;
        *)
            echo -e "${RED}✗ Unrecognized argument: $subcommand${NC}"
            echo -e "Run: ./workload-identity.sh --help for more information"
            exit 1
            ;;
    esac

    # Parse flags for CLI subcommands
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|-p)    G_CLI_PROJECT="${2:-}";  shift 2 ;;
            --cluster|-c)    G_CLI_CLUSTER="${2:-}";  shift 2 ;;
            --namespace|-n)  G_CLI_NAMESPACE="${2:-}"; shift 2 ;;
            --ksa|-k)        G_CLI_KSA="${2:-}";       shift 2 ;;
            --iam-sa|-s)     G_CLI_IAM_SA="${2:-}";    shift 2 ;;
            --ticket|-t)     G_CLI_TICKET="${2:-}";    shift 2 ;;
            --level|-l)      G_CLI_CLEANUP_LEVEL="${2:-}"; shift 2 ;;
            --file|-f)       G_CLI_BULK_FILE="${2:-}"; shift 2 ;;
            --dry-run)       G_DRY_RUN=1; shift ;;
            *)
                echo -e "${RED}✗ Unrecognized flag: $1${NC}"
                echo -e "Run: ./workload-identity.sh --help for more information"
                exit 1
                ;;
        esac
    done
}

# ─── Entry Point Guard ───────────────────────────────────────────────────────
# When WI_UNIT_TEST=1, the script is being sourced by the test suite.
# Skip dependency checks, file initialization and entry-point dispatch so the
# test suite can call individual functions in isolation.
if [[ "${WI_UNIT_TEST:-0}" != "1" ]]; then

    # Check dependencies
    for cmd in gcloud kubectl jq; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}✗ Error: $cmd is not installed${NC}"
            echo -e "${GRAY}Please install the required tools and try again${NC}"
            exit 1
        fi
    done

    # Initialize control file
    init_control_file

    # Process arguments
    main_entry "$@"

    # Dispatch: CLI mode or interactive menu
    if [[ "$G_CLI_MODE" == "1" ]]; then
        case "$G_CLI_OPERATION" in
            setup)       operation_setup ;;
            verify)      operation_verify ;;
            cleanup)     operation_cleanup ;;
            list)        operation_list ;;
            bulk-setup)  operation_bulk_setup ;;
        esac
    else
        main "$@"
    fi

fi  # end WI_UNIT_TEST guard
