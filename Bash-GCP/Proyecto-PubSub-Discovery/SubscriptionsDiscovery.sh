#!/bin/bash

################################################################################
# PubSub Subscriptions Discovery Script
# Objetivo: Descubrir todas las suscripciones con sus configuraciones completas
################################################################################

set -euo pipefail

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Variables
PROJECT_ID=""
OUTPUT_DIR="./subscriptions-exports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
EXPORT_FILE=""

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

check_gcloud() {
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud no está instalado"
        exit 1
    fi
    print_success "gcloud encontrado"
}

check_jq() {
    if ! command -v jq &> /dev/null; then
        print_error "jq no está instalado (requerido)"
        exit 1
    fi
    print_success "jq encontrado"
}

check_gcp_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        print_error "No hay autenticación activa en gcloud"
        exit 1
    fi
    print_success "Autenticación GCP verificada"
}

check_project() {
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        print_error "Proyecto '$PROJECT_ID' no encontrado o sin acceso"
        exit 1
    fi
    print_success "Proyecto '$PROJECT_ID' verificado"
}

setup_output_dir() {
    mkdir -p "$OUTPUT_DIR"
    EXPORT_FILE="$OUTPUT_DIR/subscriptions-${PROJECT_ID}-${TIMESTAMP}.json"
    print_info "Directorio de salida: $OUTPUT_DIR"
    print_info "Archivo de exportación: $(basename $EXPORT_FILE)"
}

################################################################################
# Descubrimiento de Suscripciones
################################################################################

discover_subscriptions() {
    print_header "Descubriendo Suscripciones"
    
    print_info "Obteniendo configuración completa de suscripciones..."
    print_warning "Esto puede tardar unos segundos..."
    
    # Usar list que es MUY rápido y devuelve TODA la configuración necesaria
    local subs_json
    subs_json=$(gcloud pubsub subscriptions list \
        --project="$PROJECT_ID" \
        --format=json \
        --limit=1000 2>/dev/null || echo "[]")
    
    if [[ -z "$subs_json" ]] || [[ "$subs_json" == "[]" ]]; then
        print_warning "No se encontraron suscripciones en el proyecto"
        echo "[]" > "$EXPORT_FILE"
        return
    fi
    
    # Validar JSON
    if ! echo "$subs_json" | jq empty 2>/dev/null; then
        print_error "Error al obtener suscripciones"
        echo "[]" > "$EXPORT_FILE"
        return 1
    fi
    
    local sub_count
    sub_count=$(echo "$subs_json" | jq 'length')
    
    print_success "Encontradas $sub_count suscripciones con configuración completa"
    
    # Guardar directamente (list ya contiene toda la info necesaria)
    echo "$subs_json" | jq '.' > "$EXPORT_FILE"
    
    # Validar archivo final
    if ! jq empty "$EXPORT_FILE" 2>/dev/null; then
        print_error "Error en archivo de exportación"
        echo "[]" > "$EXPORT_FILE"
        return 1
    fi
    
    print_success "Archivo: $EXPORT_FILE"
    echo ""
    
    # Mostrar resumen
    echo "Configuración exportada incluye:"
    echo "  • Nombre de suscripción"
    echo "  • Tema asociado"
    echo "  • ackDeadlineSeconds"
    echo "  • messageRetentionDuration"
    echo "  • pushConfig (si existe)"
    echo "  • deadLetterPolicy (si existe)"
    echo "  • filter (si existe)"
    echo "  • labels (si existen)"
    echo "  • expirationPolicy"
    echo "  • retryPolicy"
    echo ""
    
    echo "Suscripciones descubiertas:"
    jq -r '.[] | .name' "$EXPORT_FILE" 2>/dev/null | sed 's|.*/||g' | while read -r sub; do
        echo "  • $sub"
    done
}

show_summary() {
    print_header "Resumen de Discovery"
    
    local sub_count=$(jq 'length' "$EXPORT_FILE")
    
    cat > "$OUTPUT_DIR/DISCOVERY-REPORT-${PROJECT_ID}-${TIMESTAMP}.txt" << EOF
========================================
PubSub Subscriptions Discovery Report
========================================

Proyecto: $PROJECT_ID
Timestamp: $(date)
Tipo: Discovery de Suscripciones

Resumen:
--------
Total de suscripciones descubiertas: $sub_count

Archivo de Exportación:
$EXPORT_FILE

Estructura de datos:
- name: Nombre completo de la suscripción
- topic: Tema al que está suscrita
- ackDeadlineSeconds: Tiempo límite de reconocimiento
- messageRetentionDuration: Duración de retención de mensajes
- pushConfig: Configuración de push (si la hay)
- deadLetterPolicy: Política de dead letter
- filter: Filtro de mensajes
- labels: Etiquetas

Pasos Siguientes:
1. Verificar suscripciones existentes en proyecto destino:
   ./SubscriptionsVerify.sh -p TARGET_PROJECT -s $EXPORT_FILE

2. Replicar suscripciones faltantes:
   ./SubscriptionsReplicate.sh -s $EXPORT_FILE -t TARGET_PROJECT

EOF
    
    print_success "Reporte creado: $OUTPUT_DIR/DISCOVERY-REPORT-${PROJECT_ID}-${TIMESTAMP}.txt"
}

show_usage() {
    cat << EOF
Uso: $0 [OPCIONES]

Descubre todas las suscripciones de un proyecto GCP con sus configuraciones completas.

Opciones:
    -p, --project PROJECT_ID    ID del proyecto GCP (requerido)
    -o, --output DIR            Directorio de salida (default: ./subscriptions-exports)
    -h, --help                  Mostrar esta ayuda

Ejemplos:
    $0 --project mi-proyecto-gcp
    $0 -p mi-proyecto-gcp -o ./backups

EOF
}

################################################################################
# Main
################################################################################

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT_ID="$2"
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
    
    if [[ -z "$PROJECT_ID" ]]; then
        print_error "Se requiere especificar el proyecto con -p o --project"
        show_usage
        exit 1
    fi
    
    print_header "PubSub Subscriptions Discovery - $PROJECT_ID"
    
    check_gcloud
    check_jq
    check_gcp_auth
    check_project
    setup_output_dir
    
    discover_subscriptions
    show_summary
    
    print_header "Discovery Completado"
    echo ""
    print_success "Archivo de exportación listo para usar"
    echo ""
    echo "Próximo paso: Verificar suscripciones en proyecto destino"
    echo "  ./SubscriptionsVerify.sh -p TARGET_PROJECT -s $EXPORT_FILE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
