#!/bin/bash
# =============================================================================
# Workload Identity Manager — UI Library
# Display, prompts, menus, interactive operation wrappers
# Calls: do_bind, do_setup, do_verify, do_cleanup (from lib/core.sh)
# =============================================================================

# --- Colors for terminal output ---
LGREEN='\033[1;32m'
LCYAN='\033[1;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
RED='\033[0;31m'
GRAY='\033[0;37m'
NC='\033[0m'

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
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
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

    if [[ -n "$default_value" ]]; then
        echo -ne "${YELLOW}${prompt_text} [${default_value}]: ${NC}"
    else
        echo -ne "${YELLOW}${prompt_text}: ${NC}"
    fi

    local input_value
    read -r input_value
    # Trim leading/trailing whitespace (handles copy-paste with accidental spaces)
    input_value="${input_value#"${input_value%%[![:space:]]*}"}"
    input_value="${input_value%"${input_value##*[![:space:]]}"}"

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

    echo -e "${WHITE}${prompt_text}${NC}"
    echo ""

    for i in "${!options[@]}"; do
        echo -e "  ${LCYAN}$((i+1)))${NC} ${options[$i]}"
    done

    echo ""
    echo -ne "${YELLOW}Select an option [1-${count}]: ${NC}"
    local selection
    read -r selection

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
    Fully interactive guided menu interface.

  USAGE:
    ./workload-identity.sh [subcommand] [flags]
    ./workload-identity.sh                              # interactive menu
    ./workload-identity.sh --help | --version

  SUBCOMMANDS:
    bind    --project P --cluster C --ksa K --iam-sa E [--namespace N]
            [--location L] [--ticket T] [--dry-run] [--yes] [--file F]
    setup   Same flags as bind. Creates IAM SA and KSA if absent.
    verify  --project P --cluster C --ksa K --iam-sa E [--namespace N]
    cleanup --project P --cluster C --ksa K --iam-sa E [--namespace N]
            [--level 1|2|3] [--dry-run] [--yes]
    list    --project P --cluster C [--namespace N]

  EXAMPLE (ticket-driven, non-interactive):
    ./workload-identity.sh bind \
      --project gnp-gmmeot-pro \
      --cluster gke-gnp-gmmeot-pro \
      --ksa ksa-gmmeot-secret \
      --iam-sa gae-gmmeot-rechazos@gnp-gmmeot-pro.iam.gserviceaccount.com \
      --ticket CTASK0365432 --yes

  OPERATIONS (via interactive menu):
    setup:      Create IAM SA, KSA, WI binding and annotation
    verify:     Verify that WI is correctly configured
    cleanup:    Remove binding, KSA and/or IAM SA
    list:       List KSAs with WI annotation in a namespace

  FILES:
    workload-identity-registry.csv    Operations registry
    config.sh                         External configuration
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
    cat << 'VERSION_TEXT'

  ╔════════════════════════════════════════════════════════════════╗
  ║        WORKLOAD IDENTITY MANAGER                               ║
  ╚════════════════════════════════════════════════════════════════╝

  Name:        Workload Identity Manager
  Version:     4.5.0
  Description: Configure GCP Workload Identity for GKE

  Features:
    ✓ Non-interactive CLI mode (bind/setup/verify/cleanup/list)
    ✓ JSON file input (--file ticket.json)
    ✓ Interactive guided menu (backward compatible)
    ✓ Working --dry-run (all destructive calls gated by exec_or_dry)
    ✓ Registry deduplication (upsert replaces always-append)
    ✓ GCS auto-sync (optional via WI_GCS_BUCKET)
VERSION_TEXT
}

# =============================================================================
# Menu Functions
# =============================================================================

show_main_menu() {
    clear
    echo -e "${LGREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${LGREEN}║${NC}   ${WHITE}Workload Identity Manager v5.0.0${NC}  ${LGREEN}║${NC}"
    echo -e "${LGREEN}╠════════════════════════════════════════╣${NC}"
    echo -e "${LGREEN}║${NC}                                        ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}1)${NC} Bind (cuentas existentes)          ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}2)${NC} Setup completo (crear + vincular)   ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}3)${NC} Verify Configuration               ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}4)${NC} Delete Workload Identity           ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}5)${NC} List Bindings in Namespace         ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}6)${NC} View Operations Registry           ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}                                        ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}  ${LCYAN}0)${NC} Exit                               ${LGREEN}║${NC}"
    echo -e "${LGREEN}║${NC}                                        ${LGREEN}║${NC}"
    echo -e "${LGREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -ne "${YELLOW}Select an option: ${NC}"
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

    # Skip interactive prompt in interactive mode and auto-accept
    echo -e "${GRAY}─────────────────────────────────────${NC}"
    echo ""

    # First question - accept Y/y/N/n or yes/no
    echo -ne "Are you sure you want to ${action}? ${LCYAN}(Y/N)${NC}: "
    local response1
    read -r response1

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
        read -r response2

        if [[ "$response2" != "CONFIRM" ]]; then
            echo -e "${LGREEN}✓ Operation cancelled${NC}"
            return 1
        fi
    fi

    return 0
}

# =============================================================================
# Interactive Operation: Bind Workload Identity
# =============================================================================

interactive_bind() {
    clear
    print_header "Bind Workload Identity (cuentas existentes)"
    echo ""

    echo -e "${GRAY}  Bind two existing accounts: IAM SA + KSA annotation.${NC}"
    echo ""

    prompt_input "Ticket or CTASK (optional)" "TICKET_ID" ""
    setup_log_directory "$TICKET_ID"
    log "Session started - Operation: BIND"

    local current_project
    current_project=$(get_current_project)
    prompt_input "Project ID" "project_id" "$current_project"
    [[ -z "$project_id" ]] && { print_error "Project ID required"; return 1; }

    prompt_input "IAM SA email (full, e.g. sa@project.iam.gserviceaccount.com)" "iam_sa"
    [[ -z "$iam_sa" ]] && { print_error "IAM SA email required"; return 1; }

    prompt_input "KSA name" "ksa_name"
    [[ -z "$ksa_name" ]] && { print_error "KSA name required"; return 1; }

    prompt_input "Namespace" "namespace" "$G_DEFAULT_NS"

    if ! select_cluster_from_project "$project_id"; then return 1; fi
    local selected_cluster="$SELECTED_CLUSTER"
    local selected_location="$SELECTED_LOCATION"

    echo ""
    print_header "Bind Summary"
    [[ -n "$TICKET_ID" ]] && print_info "Ticket" "$TICKET_ID"
    print_info "Project"   "$project_id"
    print_info "Cluster"   "$selected_cluster ($selected_location)"
    print_info "Namespace" "$namespace"
    print_info "KSA"       "$ksa_name"
    print_info "IAM SA"    "$iam_sa"
    echo ""

    if ! ask_confirmation "Create IAM binding and KSA annotation?" "bind"; then
        print_warning "Operation cancelled"
        return 0
    fi

    echo ""
    if do_bind "$project_id" "$selected_cluster" "$selected_location" \
               "$namespace" "$ksa_name" "$iam_sa" "$TICKET_ID" "0"; then
        print_success "Workload Identity bound successfully"
    else
        print_error "Bind operation failed"
        return 1
    fi

    echo ""
    echo -ne "${YELLOW}Press Enter to continue...${NC}"; read -r
}

# =============================================================================
# Interactive Operation: Setup Workload Identity
# =============================================================================

interactive_setup() {
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

    echo -e "${GRAY}Namespace: $namespace (will be created if missing)${NC}"

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

    # Add IAM Workload Identity binding — auto-enables WI if pool missing, then retries
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Adding IAM binding..."
    local bind_out bind_rc=0
    bind_out=$(add_iam_binding "$iam_sa_email" "$project_id" "$ksa_name" "$namespace" 2>&1) || bind_rc=$?
    if [[ $bind_rc -ne 0 ]] && echo "$bind_out" | grep -q "Identity Pool does not exist"; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Adding IAM binding... ${YELLOW}(WI not enabled)${NC}"
        if ensure_workload_identity_enabled "$project_id" "$selected_cluster" "$selected_location"; then
            echo -ne "${WHITE}[${step}/${total_steps}]${NC} Adding IAM binding (retry)..."
            if add_iam_binding "$iam_sa_email" "$project_id" "$ksa_name" "$namespace" >/dev/null 2>&1; then
                echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Adding IAM binding... ${LGREEN}✓${NC}"
                bind_rc=0
            else
                echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Adding IAM binding... ${RED}✗${NC}"
                print_error "Error adding IAM binding after WI enable"
            fi
        fi
    elif [[ $bind_rc -eq 0 ]]; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Adding IAM binding... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Adding IAM binding... ${RED}✗${NC}"
        print_error "Error adding IAM binding"
    fi
    ((step++))

    # Annotate KSA with IAM SA email
    echo -ne "${WHITE}[${step}/${total_steps}]${NC} Annotating Kubernetes SA..."
    local ann_out ann_rc=0
    ann_out=$(annotate_ksa "$ksa_name" "$namespace" "$iam_sa_email" 2>&1) || ann_rc=$?
    if [[ $ann_rc -eq 0 ]]; then
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Annotating Kubernetes SA... ${LGREEN}✓${NC}"
    else
        echo -e "\r${WHITE}[${step}/${total_steps}]${NC} Annotating Kubernetes SA... ${RED}✗${NC}"
        print_error "Error annotating KSA: $ann_out"
        log "Annotate error: $ann_out"
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

    # Auto-sync registry to GCS if configured
    sync_registry push

    echo ""
    echo -ne "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# =============================================================================
# Interactive Operation: Verify Workload Identity
# =============================================================================

interactive_verify() {
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
    echo -e "${WHITE}Options:${NC}"
    echo -e "  ${LCYAN}1)${NC} Continue with verification"
    echo -e "  ${LCYAN}0)${NC} Return to main menu"
    echo ""
    echo -ne "${YELLOW}Select an option: ${NC}"
    local verify_option
    read -r verify_option
    if [[ "$verify_option" != "1" ]]; then
        return 0
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
    if kubectl get serviceaccount "$ksa_name" -n "$namespace" --request-timeout=5s &>/dev/null; then
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

    echo ""
    echo -ne "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# =============================================================================
# Interactive Operation: Cleanup Workload Identity
# =============================================================================

interactive_cleanup() {
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
            local selection
            read -r selection

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
                        read -r
                        return 1
                    fi
                fi
            else
                echo -e "${RED}Invalid option${NC}"
                echo -ne "${YELLOW}Press Enter to continue...${NC}"
                read -r
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
        selected_cluster="$SELECTED_CLUSTER"
        selected_location="$SELECTED_LOCATION"

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
        read -r
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
    echo -ne "${YELLOW}Select an option: ${NC}"
    read -r cleanup_option

    if [[ "$cleanup_option" == "0" ]]; then
        print_warning "Operation cancelled"
        echo ""
        echo -ne "${YELLOW}Press Enter to continue...${NC}"
        read -r
        return 0
    fi

    if [[ ! "$cleanup_option" =~ ^[1-3]$ ]]; then
        print_error "Invalid option"
        echo ""
        echo -ne "${YELLOW}Press Enter to continue...${NC}"
        read -r
        return 0
    fi

    echo ""
    echo -e "${RED}⚠ This action cannot be undone${NC}"
    echo -ne "${YELLOW}Are you sure? (Y/N): ${NC}"
    local confirm
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "Operation cancelled"
        echo ""
        echo -ne "${YELLOW}Press Enter to continue...${NC}"
        read -r
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
        local delete_sa_error=""
        if delete_sa_error=$(gcloud iam service-accounts delete "$annotation" --project "$project_id" --quiet 2>&1); then
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

    # Auto-sync registry to GCS if configured
    sync_registry push

    echo ""
    echo -ne "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# =============================================================================
# Interactive Operation: List Workload Identities
# =============================================================================

interactive_list() {
    clear
    print_header "List Workload Identities"
    echo ""

    local project_id=""
    local selected_cluster=""
    local selected_location=""
    local current_project
    current_project=$(get_current_project)

    # ── Project Selection ─────────────────────────────────────────────────────
    if [[ -f "$G_CONTROL_FILE" ]]; then
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
            local selection
            read -r selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= max_opt )); then
                if (( selection == max_opt )); then
                    prompt_input "Enter Project ID" "project_id" "$current_project"
                else
                    project_id="${project_options[$((selection-1))]}"
                    echo -e "${LGREEN}✓ Selected project:${NC} ${WHITE}$project_id${NC}"
                fi
            else
                print_error "Invalid option"
                echo -ne "${YELLOW}Press Enter to continue...${NC}"; read -r; return 1
            fi
        else
            prompt_input "Enter Project ID" "project_id" "$current_project"
        fi
    else
        prompt_input "Enter Project ID" "project_id" "$current_project"
    fi

    echo ""

    # ── Cluster Selection ─────────────────────────────────────────────────────
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
        local selection
        read -r selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= max_opt )); then
            if (( selection == max_opt )); then
                if ! select_cluster_from_project "$project_id"; then
                    echo -ne "${YELLOW}Press Enter to continue...${NC}"; read -r; return 1
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
            echo -ne "${YELLOW}Press Enter to continue...${NC}"; read -r; return 1
        fi
    else
        # No registry clusters for this project — discover from GCP
        if ! select_cluster_from_project "$project_id"; then
            echo -ne "${YELLOW}Press Enter to continue...${NC}"; read -r; return 1
        fi
        selected_cluster="$SELECTED_CLUSTER"
        selected_location="$SELECTED_LOCATION"
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
        read -r
        return 1
    fi

    echo ""

    # --- Namespace ---
    prompt_input "Enter namespace (or 'all' for all namespaces)" "namespace" "apps"

    echo ""
    print_header "Configured Workload Identities"
    echo ""

    if [[ "$namespace" == "all" ]]; then
        local namespaces
        namespaces=$(kubectl get namespaces --request-timeout=5s -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
        for ns in $namespaces; do
            list_workload_identities "$ns"
            echo ""
        done
    else
        list_workload_identities "$namespace"
    fi

    echo ""
    echo -ne "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# =============================================================================
# Interactive Operation: View Registry
# =============================================================================

interactive_registry() {
    clear
    print_header "Operations Registry"
    echo ""

    if [[ ! -f "$G_CONTROL_FILE" ]]; then
        print_warning "No records available"
        echo ""
        echo -ne "${YELLOW}Press Enter to continue...${NC}"
        read -r
        return 0
    fi

    # Count records (handle missing trailing newline)
    local total
    total=$(tail -n +2 "$G_CONTROL_FILE" | wc -l)
    # If last line doesn't end with newline, add 1
    if [[ $(tail -c 1 "$G_CONTROL_FILE" | wc -l) -eq 0 ]]; then
        total=$(( total + 1 ))
    fi

    # Count active records
    local active
    active=$(tail -n +2 "$G_CONTROL_FILE" | awk -F',' '{status=$NF; gsub(/^[[:space:]]+|[[:space:]]+$/, "", status); if (status == "activo") count++} END {print count+0}')
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
    (cat "$G_CONTROL_FILE"; [[ -n "$(tail -c1 "$G_CONTROL_FILE")" ]] && echo) | tail -n +2 | while IFS=',' read -r fecha ticket project cluster location namespace ksa iam_sa status; do
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
    read -r
}
