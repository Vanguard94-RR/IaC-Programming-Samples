#!/bin/bash

################################################################################
# PubSub Subscriptions Verify Script
# Objetivo: Verificar cuáles suscripciones existen en proyecto destino
################################################################################

set -euo pipefail

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Variables
TARGET_PROJECT=""
SOURCE_FILE=""
OUTPUT_DIR="./subscriptions-exports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
EXIST_FILE=""
MISSING_FILE=""

################################################################################
# Funciones Auxiliares
################################################################################

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }
print_found() { echo -e "${GREEN}  ✓ $1${NC}"; }
print_missing() { echo -e "${RED}  ✗ $1${NC}"; }

check_tools() {
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud no está instalado"
        exit 1
    fi
    if ! command -v jq &> /dev/null; then
        print_error "jq no está instalado"
        exit 1
    fi
    print_success "Herramientas verificadas"
}

check_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        print_error "No hay autenticación activa"
        exit 1
    fi
    print_success "Autenticación verificada"
}

check_project() {
    if ! gcloud projects describe "$TARGET_PROJECT" &> /dev/null; then
        print_error "Proyecto '$TARGET_PROJECT' no encontrado"
        exit 1
    fi
    print_success "Proyecto '$TARGET_PROJECT' verificado"
}

check_source_file() {
    if [[ ! -f "$SOURCE_FILE" ]]; then
        print_error "Archivo fuente no encontrado: $SOURCE_FILE"
        exit 1
    fi
    if ! jq empty "$SOURCE_FILE" 2>/dev/null; then
        print_error "Archivo fuente no es JSON válido"
        exit 1
    fi
    print_success "Archivo fuente validado"
}

setup_output() {
    mkdir -p "$OUTPUT_DIR"
    local base_name=$(basename "$SOURCE_FILE" .json)
    EXIST_FILE="$OUTPUT_DIR/${base_name}-EXIST-${TARGET_PROJECT}-${TIMESTAMP}.json"
    MISSING_FILE="$OUTPUT_DIR/${base_name}-MISSING-${TARGET_PROJECT}-${TIMESTAMP}.json"
}

################################################################################
# Verificación de Suscripciones
################################################################################

verify_subscriptions() {
    print_header "Verificando Suscripciones en Proyecto Destino"
    
    local source_count=$(jq 'length' "$SOURCE_FILE")
    print_info "Suscripciones en archivo fuente: $source_count"
    
    # Obtener suscripciones existentes en proyecto destino
    local target_subs
    target_subs=$(gcloud pubsub subscriptions list \
        --project="$TARGET_PROJECT" \
        --format='value(name)' 2>/dev/null || echo "")
    
    local existing_array=()
    local missing_array=()
    
    # Comparar
    jq -c '.[]' "$SOURCE_FILE" | while read -r sub_source; do
        local sub_name=$(echo "$sub_source" | jq -r '.name' | xargs basename)
        
        # Buscar si existe en proyecto destino
        if echo "$target_subs" | grep -q "/$sub_name\$"; then
            print_found "$sub_name"
            existing_array+=("$sub_source")
        else
            print_missing "$sub_name"
            missing_array+=("$sub_source")
        fi
    done
    
    # Guardar resultados en variables globales (usando files temporales por el subshell)
    echo "$SOURCE_FILE" | xargs jq -c '.[] | select(.name | split("/") | .[-1] as $name | . as $sub | true)' | while read -r sub; do
        local sub_name=$(echo "$sub" | jq -r '.name' | xargs basename)
        if echo "$target_subs" | grep -q "/$sub_name\$"; then
            echo "$sub"
        fi
    done | jq -s '.' > "$EXIST_FILE"
    
    echo "$SOURCE_FILE" | xargs jq -c '.[] | select(.name | split("/") | .[-1] as $name | . as $sub | true)' | while read -r sub; do
        local sub_name=$(echo "$sub" | jq -r '.name' | xargs basename)
        if ! echo "$target_subs" | grep -q "/$sub_name\$"; then
            echo "$sub"
        fi
    done | jq -s '.' > "$MISSING_FILE"
    
    local exist_count=$(jq 'length' "$EXIST_FILE")
    local missing_count=$(jq 'length' "$MISSING_FILE")
    
    print_header "Resultados de Verificación"
    echo ""
    echo -e "${GREEN}Suscripciones que YA existen: $exist_count${NC}"
    echo -e "${RED}Suscripciones que FALTAN: $missing_count${NC}"
    echo ""
}

generate_report() {
    print_header "Generando Reporte"
    
    local exist_count=$(jq 'length' "$EXIST_FILE")
    local missing_count=$(jq 'length' "$MISSING_FILE")
    
    cat > "$OUTPUT_DIR/VERIFY-REPORT-${TARGET_PROJECT}-${TIMESTAMP}.txt" << EOF
========================================
PubSub Subscriptions Verification Report
========================================

Proyecto Destino: $TARGET_PROJECT
Timestamp: $(date)
Archivo Fuente: $(basename $SOURCE_FILE)

Resumen:
--------
Suscripciones en archivo fuente: $(jq 'length' "$SOURCE_FILE")
Suscripciones que YA existen: $exist_count
Suscripciones que FALTAN: $missing_count

Archivos Generados:
-------------------
1. $EXIST_FILE
   Suscripciones que ya existen en el proyecto destino

2. $MISSING_FILE
   Suscripciones que necesitan ser replicadas

Próximo Paso:
--------------
Si hay suscripciones que faltan ($missing_count), ejecuta:

  ./SubscriptionsReplicate.sh \
    --source-file $MISSING_FILE \
    --target-project $TARGET_PROJECT

Esto replicará SOLO las suscripciones faltantes.

EOF
    
    print_success "Reporte creado"
}

show_usage() {
    cat << EOF
Uso: $0 [OPCIONES]

Verifica cuáles suscripciones ya existen en un proyecto destino.

Opciones:
    -p, --project PROJECT_ID    ID del proyecto destino (requerido)
    -s, --source-file FILE      Archivo JSON de subscriptions discovery (requerido)
    -o, --output DIR            Directorio de salida
    -h, --help                  Mostrar esta ayuda

Ejemplos:
    $0 -p mi-proyecto-destino -s subscriptions-export.json
    $0 --project target-project --source-file ./subscriptions-exports/subscriptions-*.json

EOF
}

################################################################################
# Main
################################################################################

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                TARGET_PROJECT="$2"
                shift 2
                ;;
            -s|--source-file)
                SOURCE_FILE="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Opción desconocida: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$TARGET_PROJECT" ]] || [[ -z "$SOURCE_FILE" ]]; then
        print_error "Se requieren los argumentos --project y --source-file"
        show_usage
        exit 1
    fi
    
    print_header "PubSub Subscriptions Verify"
    
    check_tools
    check_auth
    check_project
    check_source_file
    setup_output
    
    verify_subscriptions
    generate_report
    
    print_header "Verificación Completada"
    echo ""
    echo "Archivos generados:"
    echo "  • $EXIST_FILE (suscripciones existentes)"
    echo "  • $MISSING_FILE (suscripciones faltantes)"
    echo "  • $OUTPUT_DIR/VERIFY-REPORT-${TARGET_PROJECT}-${TIMESTAMP}.txt (reporte)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
