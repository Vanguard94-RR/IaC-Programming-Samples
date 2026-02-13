#!/bin/bash

################################################################################
# PubSub Discovery Script
# Objetivo: Descubrir temas y suscripciones de PubSub en un proyecto GCP
#           y guardarlos en un archivo para posterior replicación
################################################################################

set -euo pipefail

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables globales
PROJECT_ID=""
OUTPUT_DIR="./pubsub-exports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE=""
TOPICS_FILE=""
SUBSCRIPTIONS_FILE=""
DETAILED_FILE=""

################################################################################
# Funciones Auxiliares
################################################################################

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Validar que gcloud esté instalado
check_gcloud() {
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud no está instalado"
        exit 1
    fi
    print_success "gcloud encontrado"
}

# Validar que jq esté instalado
check_jq() {
    if ! command -v jq &> /dev/null; then
        print_warning "jq no está instalado. Algunos comandos pueden no funcionar óptimamente"
        return 1
    fi
    print_success "jq encontrado"
    return 0
}

# Validar autenticación con GCP
check_gcp_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        print_error "No hay autenticación activa en gcloud"
        echo "Ejecuta: gcloud auth login"
        exit 1
    fi
    print_success "Autenticación GCP verificada"
}

# Verificar que el proyecto existe
check_project_exists() {
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        print_error "Proyecto '$PROJECT_ID' no encontrado o no tienes acceso"
        exit 1
    fi
    print_success "Proyecto '$PROJECT_ID' verificado"
}

# Crear directorio de salida
setup_output_dir() {
    mkdir -p "$OUTPUT_DIR"
    OUTPUT_FILE="$OUTPUT_DIR/pubsub-${PROJECT_ID}-${TIMESTAMP}.json"
    TOPICS_FILE="$OUTPUT_DIR/topics-${PROJECT_ID}-${TIMESTAMP}.json"
    SUBSCRIPTIONS_FILE="$OUTPUT_DIR/subscriptions-${PROJECT_ID}-${TIMESTAMP}.json"
    DETAILED_FILE="$OUTPUT_DIR/pubsub-detailed-${PROJECT_ID}-${TIMESTAMP}.json"
    
    print_info "Directorio de salida: $OUTPUT_DIR"
    print_info "Archivos serán guardados con timestamp: $TIMESTAMP"
}

################################################################################
# Funciones de Discovery
################################################################################

discover_topics() {
    print_header "Descubriendo Temas"
    
    local topics_json
    topics_json=$(gcloud pubsub topics list \
        --project="$PROJECT_ID" \
        --format=json 2>/dev/null)
    
    if [[ -z "$topics_json" ]]; then
        print_warning "No se encontraron temas en el proyecto"
        echo "[]" > "$TOPICS_FILE"
        return
    fi
    
    echo "$topics_json" > "$TOPICS_FILE"
    
    local count
    count=$(echo "$topics_json" | jq 'length' 2>/dev/null || echo "?")
    print_success "Se encontraron $count temas"
    
    # Mostrar lista de temas
    echo "$topics_json" | jq -r '.[] | .name' 2>/dev/null | sed 's|.*/||g' | while read -r topic; do
        echo "  • $topic"
    done
}

discover_subscriptions() {
    print_header "Descubriendo Suscripciones"
    
    local subs_json
    subs_json=$(gcloud pubsub subscriptions list \
        --project="$PROJECT_ID" \
        --format=json 2>/dev/null)
    
    if [[ -z "$subs_json" ]]; then
        print_warning "No se encontraron suscripciones en el proyecto"
        echo "[]" > "$SUBSCRIPTIONS_FILE"
        return
    fi
    
    echo "$subs_json" > "$SUBSCRIPTIONS_FILE"
    
    local count
    count=$(echo "$subs_json" | jq 'length' 2>/dev/null || echo "?")
    print_success "Se encontraron $count suscripciones"
    
    # Mostrar lista de suscripciones
    echo "$subs_json" | jq -r '.[] | .name' 2>/dev/null | sed 's|.*/||g' | while read -r sub; do
        echo "  • $sub"
    done
}

get_topic_details() {
    local topic_name=$1
    
    gcloud pubsub topics describe "$topic_name" \
        --project="$PROJECT_ID" \
        --format=json 2>/dev/null || echo "{}"
}

get_subscription_details() {
    local subscription_name=$1
    
    gcloud pubsub subscriptions describe "$subscription_name" \
        --project="$PROJECT_ID" \
        --format=json 2>/dev/null || echo "{}"
}

discover_detailed() {
    print_header "Recopilando Detalles"
    
    local topics_json subscriptions_json
    topics_json=$(cat "$TOPICS_FILE" 2>/dev/null || echo "[]")
    subscriptions_json=$(cat "$SUBSCRIPTIONS_FILE" 2>/dev/null || echo "[]")
    
    local detailed='{
        "project_id": "'$PROJECT_ID'",
        "discovery_timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",
        "topics": [],
        "subscriptions": []
    }'
    
    # Procesar temas
    print_info "Procesando detalles de temas..."
    detailed=$(echo "$topics_json" | jq --arg proj "$PROJECT_ID" '
        reduce .[] as $topic (
            {
                "project_id": $proj,
                "discovery_timestamp": now | todateiso8601,
                "topics": [],
                "subscriptions": []
            };
            .topics += [$topic]
        )
    ' 2>/dev/null || echo "$detailed")
    
    # Procesar suscripciones
    print_info "Procesando detalles de suscripciones..."
    detailed=$(echo "$detailed" | jq --argjson subs "$subscriptions_json" '
        .subscriptions = $subs
    ' 2>/dev/null || echo "$detailed")
    
    echo "$detailed" > "$DETAILED_FILE"
    print_success "Archivo detallado creado: $DETAILED_FILE"
}

create_summary() {
    print_header "Resumen de Discovery"
    
    local topics_count subscriptions_count
    topics_count=$(jq 'length' "$TOPICS_FILE" 2>/dev/null || echo 0)
    subscriptions_count=$(jq 'length' "$SUBSCRIPTIONS_FILE" 2>/dev/null || echo 0)
    
    cat > "$OUTPUT_DIR/SUMMARY-${PROJECT_ID}-${TIMESTAMP}.txt" << EOF
========================================
PubSub Discovery Summary
========================================

Proyecto: $PROJECT_ID
Timestamp: $(date)
Directorio: $OUTPUT_DIR

Resumen:
--------
Total de Temas: $topics_count
Total de Suscripciones: $subscriptions_count

Archivos Generados:
-------------------
1. $TOPICS_FILE
   - Listado de todos los temas en formato JSON

2. $SUBSCRIPTIONS_FILE
   - Listado de todas las suscripciones en formato JSON

3. $DETAILED_FILE
   - Información detallada de temas y suscripciones

Para replicar estos recursos en otro proyecto, usa:
- PubSubReplicate.sh (script de replicación)

Comandos útiles:
----------------
# Ver todos los temas
jq '.[] | .name' $TOPICS_FILE

# Ver todas las suscripciones
jq '.[] | .name' $SUBSCRIPTIONS_FILE

# Contar recursos
echo "Temas: $(jq 'length' $TOPICS_FILE)"
echo "Suscripciones: $(jq 'length' $SUBSCRIPTIONS_FILE)"

EOF
    
    print_success "Resumen creado: $OUTPUT_DIR/SUMMARY-${PROJECT_ID}-${TIMESTAMP}.txt"
}

################################################################################
# Funciones de Validación y Utilidad
################################################################################

validate_and_export() {
    print_header "Validación Final"
    
    if [[ ! -f "$TOPICS_FILE" ]] || [[ ! -f "$SUBSCRIPTIONS_FILE" ]]; then
        print_error "Los archivos de discovery no fueron creados correctamente"
        exit 1
    fi
    
    print_success "Validación completada"
    print_success "Todos los archivos fueron creados exitosamente"
}

show_usage() {
    cat << EOF
Uso: $0 [OPCIONES]

Opciones:
    -p, --project PROJECT_ID    ID del proyecto GCP (requerido)
    -o, --output DIR            Directorio de salida (default: ./pubsub-exports)
    -h, --help                  Mostrar esta ayuda

Ejemplos:
    $0 --project mi-proyecto-gcp
    $0 -p mi-proyecto-gcp -o ./exports

EOF
}

################################################################################
# Main
################################################################################

main() {
    # Parsear argumentos
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
    
    # Validar que se proporcione el proyecto
    if [[ -z "$PROJECT_ID" ]]; then
        print_error "Se requiere especificar el ID del proyecto con -p o --project"
        show_usage
        exit 1
    fi
    
    print_header "PubSub Discovery - $PROJECT_ID"
    
    # Validaciones previas
    check_gcloud
    check_jq || true
    check_gcp_auth
    check_project_exists
    setup_output_dir
    
    # Ejecutar discovery
    discover_topics
    discover_subscriptions
    discover_detailed
    create_summary
    validate_and_export
    
    # Resumen final
    print_header "Discovery Completado"
    echo ""
    echo -e "${GREEN}✓ Discovery finalizado exitosamente${NC}"
    echo ""
    echo "Archivos generados en: $OUTPUT_DIR"
    echo ""
    ls -lah "$OUTPUT_DIR"/
    echo ""
    echo "Para replicar los recursos, ejecuta:"
    echo "  ./PubSubReplicate.sh --source-file $DETAILED_FILE --target-project TARGET_PROJECT_ID"
}

# Ejecutar main si el script es ejecutado directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
