#!/bin/bash

################################################################################
# lib/common.sh - Funciones Comunes
################################################################################

set -uo pipefail

# Colores
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_NC='\033[0m'

# Setup logs
LOGS_DIR="${SCRIPT_ROOT}/logs"
LOG_FILE="${LOGS_DIR}/pubsub-manager.log"

setup_logs() {
    local ticket_id="${TICKET_ID:-}"
    
    if [[ -n "$ticket_id" ]]; then
        local ticket_logs_dir="/home/admin/Documents/GNP/Tickets/$ticket_id/logs"
        if [[ -d "$ticket_logs_dir" ]]; then
            LOGS_DIR="$ticket_logs_dir"
            local timestamp
            timestamp=$(date +'%Y%m%d_%H%M%S')
            LOG_FILE="${LOGS_DIR}/pubsub-manager-${ticket_id}-${timestamp}.log"
        fi
    fi
    
    mkdir -p "${LOGS_DIR}"
    touch "${LOG_FILE}"
}

# Logging
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Print funciones
print_info() {
    echo -e "${COLOR_BLUE}ℹ${COLOR_NC} $*"
    log "INFO" "$*"
}

print_success() {
    echo -e "${COLOR_GREEN}✓${COLOR_NC} $*"
    log "SUCCESS" "$*"
}

print_warn() {
    echo -e "${COLOR_YELLOW}⚠${COLOR_NC} $*"
    log "WARN" "$*"
}

print_error() {
    echo -e "${COLOR_RED}✗${COLOR_NC} $*" >&2
    log "ERROR" "$*"
}

# Validar dependencias
check_dependencies() {
    local missing=()
    
    for cmd in gcloud jq yq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Falta instalar: ${missing[*]}"
        return 1
    fi
    
    return 0
}

# Validar autenticación GCP
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' | grep -q .; then
        print_error "No autenticado en gcloud"
        return 1
    fi
    return 0
}

# Validar proyecto existe
check_project_exists() {
    local project=$1
    
    if ! gcloud projects describe "$project" &>/dev/null; then
        print_error "Proyecto no existe: $project"
        return 1
    fi
    return 0
}

# Morir
die() {
    print_error "$@"
    exit 1
}

# Preguntar ticket ID
ask_for_ticket() {
    echo "" >&2
    echo "╔════════════════════════════════════════════════════════════════╗" >&2
    echo "║         GNP Google Cloud Pub/Sub Manager                       ║" >&2
    echo "╚════════════════════════════════════════════════════════════════╝" >&2
    echo "" >&2
    
    read -rp "Ticket (opcional, Enter para omitir): " ticket
    ticket=$(echo "$ticket" | xargs | tr '[:lower:]' '[:upper:]')
    
    if [[ -z "$ticket" ]]; then
        return 0
    fi
    
    # Validar formato de ticket
    if [[ ! "$ticket" =~ ^(CTASK|TASK|INC|CHG|PRB|REQ)[0-9]{6,8}$ ]]; then
        print_error "Formato inválido"
        ask_for_ticket
        return
    fi
    
    # Crear carpeta del ticket si no existe
    local ticket_dir="/home/admin/Documents/GNP/Tickets/$ticket"
    if [[ ! -d "$ticket_dir" ]]; then
        mkdir -p "$ticket_dir"/{docs,scripts,backups,logs,configs}
        chmod 700 "$ticket_dir"
    fi
    
    printf "%s" "$ticket"
}

# Preguntar proyecto
ask_for_project() {
    echo "" >&2
    read -rp "Proyecto GCP: " project
    project=$(printf "%s" "$project" | xargs)
    [[ -z "$project" ]] && { print_error "No puede estar vacío"; ask_for_project; return; }
    printf "%s" "$project"
}

