#!/bin/bash
# File name      : utils.sh
# Description    : Utilidades comunes para el proyecto Shared VPC Subnet
# Author         : Erick Alvarado
# Date           : 20251113
# Version        : 1.0.0
# Usage          : source lib/utils.sh
# Bash_version   : 5.1.16(1)-release

# --- Declaraciones de Colores ---
export LGREEN='\033[1;32m'
export LCYAN='\033[1;36m'
export YELLOW='\033[1;33m'
export WHITE='\033[1;37m'
export RED='\033[0;31m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# --- Variables Globales para Logging ---
LOG_DIR="logs"
LOG_FILE=""

# --- Función: Inicializar Log ---
function init_log() {
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/subnet-creation-$(date +%Y%m%d-%H%M%S).log"
    echo "=== Subnet Creation Log ===" > "$LOG_FILE"
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
    echo "==============================" >> "$LOG_FILE"
    echo ""
}

# --- Función: Log Message ---
function log_message() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# --- Función: Print y Log ---
function print_log() {
    local color="$1"
    local level="$2"
    shift 2
    local message="$@"
    
    echo -e "${color}${message}${NC}"
    log_message "$level" "$message"
}

# --- Función: Print Success ---
function print_success() {
    print_log "$LGREEN" "SUCCESS" "✓ $@"
}

# --- Función: Print Info ---
function print_info() {
    print_log "$LCYAN" "INFO" "ℹ $@"
}

# --- Función: Print Warning ---
function print_warning() {
    print_log "$YELLOW" "WARNING" "⚠ $@"
}

# --- Función: Print Error ---
function print_error() {
    print_log "$RED" "ERROR" "✗ $@"
}

# --- Función: Ask Confirmation ---
function ask() {
    local prompt="${1:-¿Desea continuar?}"
    echo -ne "${YELLOW}${prompt} (Y/N): ${NC}"
    read confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_warning "Operación cancelada por el usuario"
        exit 1
    fi
}

# --- Función: Prompt Input ---
function prompt_input() {
    local prompt_text="$1"
    local default_value="$2"
    local variable_name="$3"
    
    echo -ne "${WHITE}>> ${prompt_text}"
    if [[ -n "$default_value" ]]; then
        echo -ne " (Por defecto: ${LCYAN}${default_value}${NC})"
    fi
    echo -ne ": "
    
    read input_value
    eval "$variable_name=\"${input_value:-$default_value}\""
}

# --- Función: Validar Proyecto GCP ---
function validate_gcp_project() {
    local project_id="$1"
    
    print_info "Validando proyecto: $project_id"
    
    if gcloud projects describe "$project_id" &>/dev/null; then
        print_success "Proyecto válido: $project_id"
        return 0
    else
        print_error "Proyecto no encontrado o sin acceso: $project_id"
        return 1
    fi
}

# --- Función: Validar VPC ---
function validate_vpc() {
    local project_id="$1"
    local vpc_name="$2"
    
    print_info "Validando VPC: $vpc_name en proyecto $project_id"
    
    if gcloud compute networks describe "$vpc_name" --project="$project_id" &>/dev/null; then
        print_success "VPC encontrada: $vpc_name"
        return 0
    else
        print_error "VPC no encontrada: $vpc_name"
        return 1
    fi
}

# --- Función: Validar CIDR ---
function validate_cidr() {
    local cidr="$1"
    
    if [[ $cidr =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        return 0
    else
        print_error "Formato CIDR inválido: $cidr"
        return 1
    fi
}

# --- Función: Verificar si subnet existe ---
function subnet_exists() {
    local project_id="$1"
    local region="$2"
    local subnet_name="$3"
    
    if gcloud compute networks subnets describe "$subnet_name" \
        --region="$region" \
        --project="$project_id" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# --- Función: Mostrar Banner ---
function show_banner() {
    clear
    echo -e "${LCYAN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║        CREACIÓN DE SUBNET EN SHARED VPC - GCP             ║"
    echo "║                                                            ║"
    echo "║                    Version 1.0.0                           ║"
    echo "║                                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
}

# --- Función: Mostrar Resumen de Configuración ---
function show_config_summary() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}                  RESUMEN DE CONFIGURACIÓN                 ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}

# --- Función: Mostrar Par Clave-Valor ---
function show_config_item() {
    local key="$1"
    local value="$2"
    printf "${YELLOW}%-25s${NC}: ${LCYAN}%s${NC}\n" "$key" "$value"
}

# --- Función: Export Variables to File ---
function export_config() {
    local config_file="$1"
    shift
    local vars=("$@")
    
    echo "# Subnet Configuration - $(date)" > "$config_file"
    for var in "${vars[@]}"; do
        echo "export $var=\"${!var}\"" >> "$config_file"
    done
    
    print_success "Configuración exportada a: $config_file"
}

# --- Función: Verificar comando gcloud ---
function check_gcloud() {
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud no está instalado. Instalar Google Cloud SDK primero."
        exit 1
    fi
    
    # Verificar autenticación
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        print_error "No hay cuenta activa en gcloud. Ejecutar: gcloud auth login"
        exit 1
    fi
    
    print_success "gcloud CLI disponible y autenticado"
}

# --- Función: Tiempo de Ejecución ---
function get_execution_time() {
    local start_time="$1"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    local hours=$((duration / 3600))
    local minutes=$(((duration % 3600) / 60))
    local seconds=$((duration % 60))
    
    printf "%02d:%02d:%02d" $hours $minutes $seconds
}
