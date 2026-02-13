#!/bin/bash

################################################################################
# PubSub Discovery Interactive Script
# Objetivo: Descubrir temas seleccionados interactivamente y sus suscripciones
################################################################################

set -euo pipefail

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Variables globales
PROJECT_ID=""
OUTPUT_DIR="./pubsub-exports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE=""
TOPICS_FILE=""
SUBSCRIPTIONS_FILE=""
DETAILED_FILE=""
SELECTED_TOPICS=()
ALL_TOPICS=()

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

print_highlight() {
    echo -e "${CYAN}→ $1${NC}"
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
# Funciones de Selección Interactiva
################################################################################

# Obtener lista de todos los temas
get_all_topics() {
    print_info "Obteniendo lista de temas del proyecto..."
    
    local topics_json
    topics_json=$(gcloud pubsub topics list \
        --project="$PROJECT_ID" \
        --format=json 2>/dev/null || echo "[]")
    
    # Convertir JSON a array (evita subshell)
    while IFS= read -r topic; do
        if [[ -n "$topic" ]]; then
            ALL_TOPICS+=("$topic")
        fi
    done < <(echo "$topics_json" | jq -r '.[] | .name // empty')
    
    if [[ ${#ALL_TOPICS[@]} -eq 0 ]]; then
        print_warning "No se encontraron temas en el proyecto '$PROJECT_ID'"
        print_info "Verifica que:"
        print_info "  1. El proyecto tiene temas de Pub/Sub creados"
        print_info "  2. Tienes permisos para listar temas"
        print_info "  3. El API de Pub/Sub está habilitado"
        exit 1
    fi
}

# Mostrar menú interactivo de temas
show_topics_menu() {
    print_header "Seleccionar Temas para Discovery"
    
    local total_topics=${#ALL_TOPICS[@]}
    
    echo ""
    print_info "Temas disponibles en el proyecto: $total_topics"
    echo ""
    
    local idx=1
    for topic_full_name in "${ALL_TOPICS[@]}"; do
        local topic_name=$(basename "$topic_full_name")
        
        # Obtener número de suscripciones
        local sub_count=$(gcloud pubsub subscriptions list \
            --project="$PROJECT_ID" \
            --filter="topic:$topic_name" \
            --format=json 2>/dev/null | jq 'length')
        
        echo "  [$idx] $topic_name ($sub_count suscripciones)"
        ((idx++))
    done
    
    echo ""
    echo "  [A] Seleccionar TODOS"
    echo "  [N] NINGUNO (cancelar)"
    echo ""
}

# Obtener suscripciones para un tema
get_subscriptions_for_topic() {
    local topic_name=$1
    
    gcloud pubsub subscriptions list \
        --project="$PROJECT_ID" \
        --filter="topic:$topic_name" \
        --format=json 2>/dev/null || echo "[]"
}

# Mostrar detalles de un tema
show_topic_details() {
    local topic_full_name=$1
    local topic_name=$(basename "$topic_full_name")
    
    echo ""
    print_highlight "Detalles del tema: $topic_name"
    
    local subs
    subs=$(get_subscriptions_for_topic "$topic_name")
    
    local sub_count
    sub_count=$(echo "$subs" | jq 'length')
    
    echo "  Topic Name: $topic_name"
    echo "  Suscripciones asociadas: $sub_count"
    
    if [[ $sub_count -gt 0 ]]; then
        echo "  Listado:"
        echo "$subs" | jq -r '.[].name | split("/") | .[-1]' | while read -r sub; do
            echo "    • $sub"
        done
    fi
    echo ""
}

# Menu de confirmación
confirm_action() {
    local message=$1
    echo ""
    print_warning "$message"
    read -p "¿Continuar? (s/n): " -r response
    
    if [[ "$response" =~ ^[Ss]$ ]]; then
        return 0
    else
        return 1
    fi
}

################################################################################
# Funciones de Discovery
################################################################################

discover_topics() {
    print_header "Descubriendo Temas Seleccionados"
    
    if [[ ${#SELECTED_TOPICS[@]} -eq 0 ]]; then
        print_error "No hay temas seleccionados"
        exit 1
    fi
    
    local topics_array=()
    
    for topic_full_name in "${SELECTED_TOPICS[@]}"; do
        local topic_name=$(basename "$topic_full_name")
        print_info "Obteniendo información del tema: $topic_name"
        
        local topic_json
        topic_json=$(gcloud pubsub topics describe "$topic_full_name" \
            --project="$PROJECT_ID" \
            --format=json 2>/dev/null || echo "{}")
        
        topics_array+=("$topic_json")
    done
    
    # Crear array JSON
    printf '%s\n' "${topics_array[@]}" | jq -s '.' > "$TOPICS_FILE"
    
    local count=${#SELECTED_TOPICS[@]}
    print_success "Se descubrieron $count tema(s)"
    
    # Mostrar lista de temas descubiertos
    jq -r '.[] | .name' "$TOPICS_FILE" 2>/dev/null | sed 's|.*/||g' | while read -r topic; do
        echo "  • $topic"
    done
}

discover_subscriptions() {
    print_header "Descubriendo Suscripciones"
    
    local subscriptions_array=()
    
    for topic_full_name in "${SELECTED_TOPICS[@]}"; do
        local topic_name=$(basename "$topic_full_name")
        
        # Obtener suscripciones para este tema
        local subs_json
        subs_json=$(gcloud pubsub subscriptions list \
            --project="$PROJECT_ID" \
            --filter="topic:$topic_name" \
            --format=json 2>/dev/null || echo "[]")
        
        # Agregar cada suscripción al array
        echo "$subs_json" | jq -c '.[]' | while read -r sub_json; do
            subscriptions_array+=("$sub_json")
        done
    done
    
    # Crear archivo de suscripciones
    if [[ ${#subscriptions_array[@]} -gt 0 ]]; then
        printf '%s\n' "${subscriptions_array[@]}" | jq -s '.' > "$SUBSCRIPTIONS_FILE"
        local count=$(jq 'length' "$SUBSCRIPTIONS_FILE")
        print_success "Se encontraron $count suscripción(es)"
        
        # Mostrar lista
        jq -r '.[] | .name' "$SUBSCRIPTIONS_FILE" 2>/dev/null | sed 's|.*/||g' | while read -r sub; do
            echo "  • $sub"
        done
    else
        echo "[]" > "$SUBSCRIPTIONS_FILE"
        print_warning "No se encontraron suscripciones"
    fi
}

discover_detailed() {
    print_header "Compilando Información Detallada"
    
    local topics_json subscriptions_json
    topics_json=$(cat "$TOPICS_FILE" 2>/dev/null || echo "[]")
    subscriptions_json=$(cat "$SUBSCRIPTIONS_FILE" 2>/dev/null || echo "[]")
    
    local detailed='{
        "project_id": "'$PROJECT_ID'",
        "discovery_timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",
        "discovery_type": "selective",
        "topics_count": '$((${#SELECTED_TOPICS[@]}))',
        "subscriptions_count": '$(echo "$subscriptions_json" | jq 'length')',
        "topics": '$topics_json',
        "subscriptions": '$subscriptions_json'
    }'
    
    echo "$detailed" | jq '.' > "$DETAILED_FILE"
    print_success "Archivo detallado creado: $DETAILED_FILE"
}

create_summary() {
    print_header "Resumen de Discovery"
    
    local topics_count=$(jq 'length' "$TOPICS_FILE" 2>/dev/null || echo 0)
    local subscriptions_count=$(jq 'length' "$SUBSCRIPTIONS_FILE" 2>/dev/null || echo 0)
    
    cat > "$OUTPUT_DIR/SUMMARY-${PROJECT_ID}-${TIMESTAMP}.txt" << EOF
========================================
PubSub Discovery Summary (Selective)
========================================

Proyecto: $PROJECT_ID
Timestamp: $(date)
Directorio: $OUTPUT_DIR
Tipo Discovery: Selectivo (por tema)

Resumen:
--------
Total de Temas: $topics_count
Total de Suscripciones: $subscriptions_count
Temas seleccionados: ${#SELECTED_TOPICS[@]}

Temas Descubiertos:
-------------------
EOF
    
    for topic_full_name in "${SELECTED_TOPICS[@]}"; do
        local topic_name=$(basename "$topic_full_name")
        echo "  • $topic_name" >> "$OUTPUT_DIR/SUMMARY-${PROJECT_ID}-${TIMESTAMP}.txt"
    done
    
    cat >> "$OUTPUT_DIR/SUMMARY-${PROJECT_ID}-${TIMESTAMP}.txt" << EOF

Archivos Generados:
-------------------
1. $TOPICS_FILE
   - Listado de los temas descubiertos en formato JSON

2. $SUBSCRIPTIONS_FILE
   - Listado de las suscripciones en formato JSON

3. $DETAILED_FILE
   - Información detallada de temas y suscripciones

Para replicar estos recursos en otro proyecto, usa:
- PubSubReplicateInteractive.sh (replicación selectiva)
- PubSubReplicate.sh (replicación automática)

Comandos útiles:
----------------
# Ver todos los temas descubiertos
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
# Funciones de Validación
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
    
    print_header "PubSub Discovery Interactive - $PROJECT_ID"
    
    # Validaciones previas
    check_gcloud
    check_jq || true
    check_gcp_auth
    check_project_exists
    setup_output_dir
    
    # Obtener lista de temas y mostrar menú
    get_all_topics
    show_topics_menu
    
    # Leer entrada del usuario
    read -p "Selecciona temas (ej: 1 2 3, A para todos, N para cancelar): " selection
    
    case "$selection" in
        [Nn])
            print_warning "Discovery cancelado"
            exit 0
            ;;
        [Aa])
            # Seleccionar todos
            SELECTED_TOPICS=("${ALL_TOPICS[@]}")
            print_success "Todos los temas seleccionados (${#SELECTED_TOPICS[@]} temas)"
            ;;
        *)
            # Procesar selección múltiple
            for num in $selection; do
                if [[ "$num" =~ ^[0-9]+$ ]]; then
                    if [[ $num -gt 0 ]] && [[ $num -le ${#ALL_TOPICS[@]} ]]; then
                        SELECTED_TOPICS+=("${ALL_TOPICS[$((num - 1))]}")
                    else
                        print_warning "Tema #$num no encontrado"
                    fi
                fi
            done
            ;;
    esac
    
    if [[ ${#SELECTED_TOPICS[@]} -eq 0 ]]; then
        print_error "No se seleccionaron temas válidos"
        exit 1
    fi
    
    # Mostrar resumen de selección
    print_header "Resumen de Selección"
    echo ""
    for topic_full_name in "${SELECTED_TOPICS[@]}"; do
        show_topic_details "$topic_full_name"
    done
    
    # Confirmación final
    if ! confirm_action "¿Proceder con discovery de ${#SELECTED_TOPICS[@]} tema(s)?"; then
        print_warning "Discovery cancelado"
        exit 0
    fi
    
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
    ls -lah "$OUTPUT_DIR"/pubsub-detailed-*.json
    ls -lah "$OUTPUT_DIR"/SUMMARY-*.txt
    echo ""
    echo "Para replicar los recursos seleccionados, ejecuta:"
    echo "  ./PubSubReplicateInteractive.sh --source-file $DETAILED_FILE --target-project TARGET_PROJECT_ID"
}

# Ejecutar main si el script es ejecutado directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
