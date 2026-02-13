#!/bin/bash

################################################################################
# PubSub Replicate Interactive Script
# Objetivo: Replicar temas y sus suscripciones con selección interactiva
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
SOURCE_FILE=""
TARGET_PROJECT=""
DRY_RUN=false
SELECTED_TOPICS=()
CREATED_TOPICS=0
CREATED_SUBSCRIPTIONS=0
FAILED_TOPICS=0
FAILED_SUBSCRIPTIONS=0

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

# Validaciones previas
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

check_source_file() {
    if [[ ! -f "$SOURCE_FILE" ]]; then
        print_error "Archivo fuente no encontrado: $SOURCE_FILE"
        exit 1
    fi
    
    if ! jq empty "$SOURCE_FILE" 2>/dev/null; then
        print_error "Archivo fuente no es un JSON válido"
        exit 1
    fi
    print_success "Archivo fuente validado"
}

check_target_project() {
    if ! gcloud projects describe "$TARGET_PROJECT" &> /dev/null; then
        print_error "Proyecto destino '$TARGET_PROJECT' no encontrado"
        exit 1
    fi
    print_success "Proyecto destino '$TARGET_PROJECT' verificado"
}

################################################################################
# Funciones de Selección Interactiva
################################################################################

# Obtener lista de temas con sus suscripciones
get_topics_with_subs() {
    jq '.topics[] | {
        name: .name,
        topic_name: (.name | split("/") | .[-1]),
        subscriptions: [
            getpath(["subscriptions"]) as $subs |
            ($subs[] | select(.topic == .name) | .name | split("/") | .[-1])
        ]
    }' "$SOURCE_FILE" 2>/dev/null | jq -s '.'
}

# Mostrar menú interactivo de temas
show_topics_menu() {
    print_header "Seleccionar Temas para Replicar"
    
    local topics_json
    topics_json=$(jq '.topics | map({name: .name, topic_name: (.name | split("/") | .[-1])})' "$SOURCE_FILE")
    
    local total_topics
    total_topics=$(echo "$topics_json" | jq 'length')
    
    if [[ $total_topics -eq 0 ]]; then
        print_error "No hay temas disponibles"
        exit 1
    fi
    
    # Array de índices y nombres
    local -a indices
    local -a topic_names
    local -a topic_full_names
    local idx=1
    
    echo ""
    echo "$topics_json" | jq -c '.[]' | while read -r topic_obj; do
        local topic_name=$(echo "$topic_obj" | jq -r '.topic_name')
        local topic_full_name=$(echo "$topic_obj" | jq -r '.name')
        
        # Contar suscripciones asociadas
        local sub_count=$(jq "[.subscriptions[] | select(.topic == \"$topic_full_name\")] | length" "$SOURCE_FILE")
        
        echo "  [$idx] $topic_name ($sub_count suscripciones)"
        indices+=($idx)
        topic_names+=("$topic_name")
        topic_full_names+=("$topic_full_name")
        ((idx++))
    done
    
    echo ""
    echo "  [A] Seleccionar TODOS"
    echo "  [N] NINGUNO (cancelar)"
    echo ""
}

# Obtener suscripciones de un tema
get_subscriptions_for_topic() {
    local topic_full_name=$1
    jq ".subscriptions[] | select(.topic == \"$topic_full_name\")" "$SOURCE_FILE"
}

# Mostrar detalles de un tema
show_topic_details() {
    local topic_full_name=$1
    local topic_name=$(basename "$topic_full_name")
    
    echo ""
    print_highlight "Detalles del tema: $topic_name"
    
    local subs
    subs=$(jq "[.subscriptions[] | select(.topic == \"$topic_full_name\") | .name | split(\"/\") | .[-1]]" "$SOURCE_FILE")
    
    local sub_count
    sub_count=$(echo "$subs" | jq 'length')
    
    echo "  Topic Name: $topic_name"
    echo "  Full Name: $topic_full_name"
    echo "  Suscripciones asociadas: $sub_count"
    
    if [[ $sub_count -gt 0 ]]; then
        echo "  Listado:"
        echo "$subs" | jq -r '.[]' | while read -r sub; do
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
# Funciones de Replicación
################################################################################

create_topic() {
    local topic_name=$1
    local labels=${2:-'{}'}
    
    print_info "Creando tema: $topic_name"
    
    local cmd="gcloud pubsub topics create $topic_name --project=$TARGET_PROJECT"
    
    if [[ "$labels" != '{}' ]] && [[ "$labels" != '' ]]; then
        local label_args=$(echo "$labels" | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")' 2>/dev/null || echo "")
        if [[ -n "$label_args" ]]; then
            cmd="$cmd --labels=$label_args"
        fi
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] $cmd"
        return 0
    fi
    
    if eval "$cmd" 2>/dev/null; then
        print_success "Tema creado: $topic_name"
        ((CREATED_TOPICS++))
        return 0
    else
        print_warning "No se pudo crear tema: $topic_name (puede que ya exista)"
        ((FAILED_TOPICS++))
        return 1
    fi
}

create_subscription() {
    local subscription_name=$1
    local topic_name=$2
    local config=$3
    
    print_info "Creando suscripción: $subscription_name"
    
    local cmd="gcloud pubsub subscriptions create $subscription_name \
        --topic=$topic_name \
        --project=$TARGET_PROJECT"
    
    local ack_deadline=$(echo "$config" | jq -r '.ackDeadlineSeconds // empty' 2>/dev/null)
    
    if [[ -n "$ack_deadline" ]]; then
        cmd="$cmd --ack-deadline=$ack_deadline"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] $cmd"
        return 0
    fi
    
    if eval "$cmd" 2>/dev/null; then
        print_success "Suscripción creada: $subscription_name"
        ((CREATED_SUBSCRIPTIONS++))
        return 0
    else
        print_warning "No se pudo crear suscripción: $subscription_name (puede que ya exista)"
        ((FAILED_SUBSCRIPTIONS++))
        return 1
    fi
}

replicate_selected_topics() {
    if [[ ${#SELECTED_TOPICS[@]} -eq 0 ]]; then
        print_error "No hay temas seleccionados"
        return 1
    fi
    
    print_header "Replicando Temas Seleccionados"
    
    for topic_full_name in "${SELECTED_TOPICS[@]}"; do
        local topic_name=$(basename "$topic_full_name")
        
        # Obtener información del tema
        local topic_obj=$(jq ".topics[] | select(.name == \"$topic_full_name\")" "$SOURCE_FILE")
        local labels=$(echo "$topic_obj" | jq -c '.labels // {}')
        
        # Crear tema
        create_topic "$topic_name" "$labels"
        
        # Crear suscripciones asociadas
        print_header "Suscripciones para: $topic_name"
        
        jq ".subscriptions[] | select(.topic == \"$topic_full_name\")" "$SOURCE_FILE" | while read -r sub_obj; do
            local sub_full_name=$(echo "$sub_obj" | jq -r '.name')
            local sub_name=$(basename "$sub_full_name")
            
            create_subscription "$sub_name" "$topic_name" "$sub_obj"
        done
    done
}

show_summary() {
    print_header "Resumen de Replicación"
    
    echo ""
    echo "Temas creados: $CREATED_TOPICS"
    echo "Temas fallidos: $FAILED_TOPICS"
    echo ""
    echo "Suscripciones creadas: $CREATED_SUBSCRIPTIONS"
    echo "Suscripciones fallidas: $FAILED_SUBSCRIPTIONS"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        print_warning "Modo DRY-RUN: No se realizaron cambios reales"
    fi
}

show_usage() {
    cat << EOF
Uso: $0 [OPCIONES]

Opciones:
    -s, --source-file FILE      Archivo JSON de discovery (requerido)
    -t, --target-project PROJECT_ID
                                ID del proyecto destino (requerido)
    -d, --dry-run               Modo simulación (no realiza cambios)
    -h, --help                  Mostrar esta ayuda

Ejemplos:
    $0 --source-file pubsub-export.json --target-project mi-proyecto-destino
    $0 -s pubsub-export.json -t mi-proyecto-destino --dry-run

EOF
}

################################################################################
# Main
################################################################################

main() {
    # Parsear argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--source-file)
                SOURCE_FILE="$2"
                shift 2
                ;;
            -t|--target-project)
                TARGET_PROJECT="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
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
    
    # Validar argumentos requeridos
    if [[ -z "$SOURCE_FILE" ]] || [[ -z "$TARGET_PROJECT" ]]; then
        print_error "Se requieren los argumentos --source-file y --target-project"
        show_usage
        exit 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_header "PubSub Replicate Interactive [DRY-RUN MODE]"
    else
        print_header "PubSub Replicate Interactive"
    fi
    
    # Validaciones previas
    check_gcloud
    check_jq
    check_gcp_auth
    check_source_file
    check_target_project
    
    # Mostrar menú y obtener selección
    show_topics_menu
    
    # Leer entrada del usuario
    read -p "Selecciona temas (ej: 1 2 3, A para todos, N para cancelar): " selection
    
    case "$selection" in
        [Nn])
            print_warning "Operación cancelada"
            exit 0
            ;;
        [Aa])
            # Seleccionar todos
            while IFS= read -r topic_full_name; do
                SELECTED_TOPICS+=("$topic_full_name")
            done < <(jq -r '.topics[] | .name' "$SOURCE_FILE")
            print_success "Todos los temas seleccionados (${#SELECTED_TOPICS[@]} temas)"
            ;;
        *)
            # Procesar selección múltiple
            for num in $selection; do
                if [[ "$num" =~ ^[0-9]+$ ]]; then
                    local topic_full_name=$(jq -r ".topics[][$((num - 1))] | .name" "$SOURCE_FILE" 2>/dev/null)
                    if [[ -n "$topic_full_name" ]] && [[ "$topic_full_name" != "null" ]]; then
                        SELECTED_TOPICS+=("$topic_full_name")
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
    for i in "${!SELECTED_TOPICS[@]}"; do
        local topic_full_name="${SELECTED_TOPICS[$i]}"
        show_topic_details "$topic_full_name"
    done
    
    # Confirmación final
    if ! confirm_action "¿Proceder a replicar ${#SELECTED_TOPICS[@]} tema(s)?"; then
        print_warning "Operación cancelada"
        exit 0
    fi
    
    # Ejecutar replicación
    replicate_selected_topics
    
    # Mostrar resumen
    show_summary
    
    if [[ "$DRY_RUN" == false ]] && [[ $FAILED_TOPICS -eq 0 ]] && [[ $FAILED_SUBSCRIPTIONS -eq 0 ]]; then
        print_success "Replicación completada exitosamente"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
