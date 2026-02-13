#!/bin/bash
# File name      : create-subnet.sh
# Description    : Script principal para crear subnets en Shared VPC de GCP
# Author         : Erick Alvarado
# Date           : 20251113
# Version        : 1.0.0
# Usage          : ./create-subnet.sh [--config <file>]
# Bash_version   : 5.1.16(1)-release

set -euo pipefail

# --- Directorio del Script ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Cargar Librerías ---
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/validators.sh"

# --- Variables Globales ---
HOST_PROJECT=""
VPC_NETWORK=""
SUBNET_NAME=""
REGION=""
IP_CIDR_RANGE=""
ENABLE_PRIVATE_GOOGLE_ACCESS="false"
ENABLE_FLOW_LOGS="false"
POD_SECONDARY_RANGE=""
POD_SECONDARY_RANGE_NAME=""
SERVICE_SECONDARY_RANGE=""
SERVICE_SECONDARY_RANGE_NAME=""
CONFIG_FILE=""
START_TIME=$(date +%s)

# --- Función: Mostrar Ayuda ---
function show_help() {
    cat << EOF
Uso: $0 [OPCIONES]

Crea una subnet en una Shared VPC existente de Google Cloud Platform.

OPCIONES:
    -h, --help              Mostrar esta ayuda
    -c, --config FILE       Usar archivo de configuración
    -i, --interactive       Modo interactivo (default)

EJEMPLOS:
    # Modo interactivo
    $0

    # Usando archivo de configuración
    $0 --config configs/my-subnet.conf

    # Ver ayuda
    $0 --help

CONFIGURACIÓN REQUERIDA:
    - Host Project ID       : Proyecto que contiene la Shared VPC
    - VPC Network Name      : Nombre de la VPC compartida
    - Subnet Name           : Nombre de la subnet a crear
    - Region                : Región de GCP (ej: us-central1)
    - IP CIDR Range         : Rango IP principal (ej: 10.0.0.0/24)

CONFIGURACIÓN OPCIONAL:
    - Private Google Access : Habilitar acceso privado a APIs (true/false)
    - Flow Logs             : Habilitar logs de flujo (true/false)
    - Secondary Ranges      : Rangos IP secundarios para GKE

Para más información, consultar README.md
EOF
}

# --- Función: Cargar Configuración desde Archivo ---
function load_config_file() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        print_error "Archivo de configuración no encontrado: $config_file"
        exit 1
    fi
    
    print_info "Cargando configuración desde: $config_file"
    source "$config_file"
    
    print_success "Configuración cargada correctamente"
}

# --- Función: Modo Interactivo ---
function interactive_mode() {
    show_banner
    
    print_info "Iniciando modo interactivo para crear subnet en Shared VPC"
    echo ""
    
    # Solicitar Host Project
    prompt_input "Host Project ID" "" "HOST_PROJECT"
    validate_gcp_project "$HOST_PROJECT" || exit 1
    
    # Solicitar VPC Network
    prompt_input "VPC Network Name" "default" "VPC_NETWORK"
    validate_vpc "$HOST_PROJECT" "$VPC_NETWORK" || exit 1
    
    # Verificar si es Shared VPC
    validate_shared_vpc "$HOST_PROJECT"
    
    # Solicitar Región
    prompt_input "Region" "us-central1" "REGION"
    validate_region "$REGION" "$HOST_PROJECT" || exit 1
    
    # Solicitar Nombre de Subnet
    prompt_input "Subnet Name" "subnet-shared-vpc" "SUBNET_NAME"
    validate_name "$SUBNET_NAME" "subnet" || exit 1
    
    # Solicitar Rango IP Principal
    prompt_input "IP CIDR Range (Primary)" "10.0.0.0/24" "IP_CIDR_RANGE"
    validate_cidr "$IP_CIDR_RANGE" || exit 1
    
    echo ""
    print_info "¿Desea configurar rangos secundarios para GKE? (Pods y Services)"
    echo -ne "${YELLOW}Configurar rangos secundarios (Y/N): ${NC}"
    read configure_secondary
    
    if [[ $configure_secondary =~ ^[Yy]$ ]]; then
        prompt_input "Secondary Range Name (Pods)" "pods" "POD_SECONDARY_RANGE_NAME"
        prompt_input "IP CIDR Range (Pods)" "10.4.0.0/16" "POD_SECONDARY_RANGE"
        validate_cidr "$POD_SECONDARY_RANGE" || exit 1
        
        prompt_input "Secondary Range Name (Services)" "services" "SERVICE_SECONDARY_RANGE_NAME"
        prompt_input "IP CIDR Range (Services)" "10.5.0.0/20" "SERVICE_SECONDARY_RANGE"
        validate_cidr "$SERVICE_SECONDARY_RANGE" || exit 1
    fi
    
    echo ""
    print_info "Configuración adicional"
    
    echo -ne "${YELLOW}Habilitar Private Google Access (Y/N): ${NC}"
    read private_access
    if [[ $private_access =~ ^[Yy]$ ]]; then
        ENABLE_PRIVATE_GOOGLE_ACCESS="true"
    fi
    
    echo -ne "${YELLOW}Habilitar Flow Logs (Y/N): ${NC}"
    read flow_logs
    if [[ $flow_logs =~ ^[Yy]$ ]]; then
        ENABLE_FLOW_LOGS="true"
    fi
}

# --- Función: Mostrar Configuración ---
function display_configuration() {
    show_config_summary
    
    show_config_item "Host Project ID" "$HOST_PROJECT"
    show_config_item "VPC Network" "$VPC_NETWORK"
    show_config_item "Subnet Name" "$SUBNET_NAME"
    show_config_item "Region" "$REGION"
    show_config_item "IP CIDR Range" "$IP_CIDR_RANGE"
    
    if [[ -n "$POD_SECONDARY_RANGE" ]]; then
        echo ""
        show_config_item "Pod Range Name" "$POD_SECONDARY_RANGE_NAME"
        show_config_item "Pod CIDR Range" "$POD_SECONDARY_RANGE"
        show_config_item "Service Range Name" "$SERVICE_SECONDARY_RANGE_NAME"
        show_config_item "Service CIDR Range" "$SERVICE_SECONDARY_RANGE"
    fi
    
    echo ""
    show_config_item "Private Google Access" "$ENABLE_PRIVATE_GOOGLE_ACCESS"
    show_config_item "Flow Logs" "$ENABLE_FLOW_LOGS"
    
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}

# --- Función: Crear Subnet ---
function create_subnet() {
    print_info "Iniciando creación de subnet: $SUBNET_NAME"
    
    local cmd="gcloud compute networks subnets create \"$SUBNET_NAME\""
    cmd+=" --project=\"$HOST_PROJECT\""
    cmd+=" --network=\"$VPC_NETWORK\""
    cmd+=" --region=\"$REGION\""
    cmd+=" --range=\"$IP_CIDR_RANGE\""
    
    # Rangos secundarios
    if [[ -n "$POD_SECONDARY_RANGE" ]]; then
        cmd+=" --secondary-range=\"$POD_SECONDARY_RANGE_NAME=$POD_SECONDARY_RANGE\""
    fi
    
    if [[ -n "$SERVICE_SECONDARY_RANGE" ]]; then
        cmd+=" --secondary-range=\"$SERVICE_SECONDARY_RANGE_NAME=$SERVICE_SECONDARY_RANGE\""
    fi
    
    # Private Google Access
    if [[ "$ENABLE_PRIVATE_GOOGLE_ACCESS" == "true" ]]; then
        cmd+=" --enable-private-ip-google-access"
    fi
    
    # Flow Logs
    if [[ "$ENABLE_FLOW_LOGS" == "true" ]]; then
        cmd+=" --enable-flow-logs"
    fi
    
    print_info "Ejecutando comando de creación..."
    log_message "COMMAND" "$cmd"
    
    if eval "$cmd"; then
        print_success "Subnet creada exitosamente: $SUBNET_NAME"
        return 0
    else
        print_error "Error al crear la subnet"
        return 1
    fi
}

# --- Función: Verificar Subnet Creada ---
function verify_subnet() {
    print_info "Verificando subnet creada..."
    
    local subnet_info=$(gcloud compute networks subnets describe "$SUBNET_NAME" \
        --region="$REGION" \
        --project="$HOST_PROJECT" \
        --format="yaml" 2>/dev/null)
    
    if [[ -n "$subnet_info" ]]; then
        print_success "Subnet verificada correctamente"
        echo ""
        echo -e "${LCYAN}Información de la subnet:${NC}"
        echo "$subnet_info" | grep -E "^(name|region|ipCidrRange|privateIpGoogleAccess|enableFlowLogs|secondaryIpRanges)" || true
        return 0
    else
        print_error "No se pudo verificar la subnet"
        return 1
    fi
}

# --- Función: Generar Resumen Final ---
function generate_summary() {
    local execution_time=$(get_execution_time "$START_TIME")
    
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                   ${LGREEN}CREACIÓN COMPLETADA${NC}                     ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    show_config_item "Subnet Name" "$SUBNET_NAME"
    show_config_item "Region" "$REGION"
    show_config_item "Project" "$HOST_PROJECT"
    show_config_item "VPC Network" "$VPC_NETWORK"
    show_config_item "IP Range" "$IP_CIDR_RANGE"
    show_config_item "Tiempo de Ejecución" "$execution_time"
    
    echo ""
    print_success "Log guardado en: $LOG_FILE"
    echo ""
    
    print_info "Comando para listar subnets en esta VPC:"
    echo -e "${LCYAN}gcloud compute networks subnets list --network=$VPC_NETWORK --project=$HOST_PROJECT${NC}"
    echo ""
    
    print_info "Comando para describir esta subnet:"
    echo -e "${LCYAN}gcloud compute networks subnets describe $SUBNET_NAME --region=$REGION --project=$HOST_PROJECT${NC}"
    echo ""
}

# --- Función Principal ---
function main() {
    # Parsear argumentos
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -i|--interactive)
                shift
                ;;
            *)
                print_error "Argumento desconocido: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Inicializar log
    init_log
    
    # Verificar gcloud
    check_gcloud
    
    # Cargar configuración o modo interactivo
    if [[ -n "$CONFIG_FILE" ]]; then
        load_config_file "$CONFIG_FILE"
    else
        interactive_mode
    fi
    
    # Mostrar configuración
    display_configuration
    
    # Pre-flight check
    preflight_check "$HOST_PROJECT" "$VPC_NETWORK" "$REGION" "$SUBNET_NAME" "$IP_CIDR_RANGE"
    
    # Confirmación final
    ask "¿Proceder con la creación de la subnet?"
    
    # Crear subnet
    if create_subnet; then
        verify_subnet
        generate_summary
        exit 0
    else
        print_error "La creación de la subnet falló"
        exit 1
    fi
}

# --- Trap para errores ---
trap 'print_error "Script interrumpido en línea $LINENO"' ERR

# --- Ejecutar Main ---
main "$@"
