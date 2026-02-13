#!/bin/bash

################################################################################
# PubSub Replicate Script
# Objetivo: Replicar temas y suscripciones de PubSub en otro proyecto GCP
################################################################################

set -euo pipefail

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables globales
SOURCE_FILE=""
TARGET_PROJECT=""
DRY_RUN=false
BATCH_SIZE=10
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
# Funciones de Replicación
################################################################################

create_topic() {
    local topic_name=$1
    local labels=${2:-'{}'}
    local kms_key=${3:-''}
    
    print_info "Creando tema: $topic_name"
    
    local cmd="gcloud pubsub topics create $topic_name --project=$TARGET_PROJECT"
    
    # Agregar labels si existen
    if [[ "$labels" != '{}' ]] && [[ "$labels" != '' ]]; then
        # Convertir labels JSON a formato gcloud
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
    
    print_info "Creando suscripción: $subscription_name -> $topic_name"
    
    local cmd="gcloud pubsub subscriptions create $subscription_name \
        --topic=$topic_name \
        --project=$TARGET_PROJECT"
    
    # Extraer configuraciones del JSON si existen
    local ack_deadline=$(echo "$config" | jq -r '.ackDeadlineSeconds // empty' 2>/dev/null)
    local retention=$(echo "$config" | jq -r '.messageRetentionDuration // empty' 2>/dev/null)
    
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

replicate_topics() {
    print_header "Replicando Temas"
    
    local topics
    topics=$(jq '.topics // []' "$SOURCE_FILE")
    local total
    total=$(echo "$topics" | jq 'length')
    
    if [[ $total -eq 0 ]]; then
        print_warning "No hay temas para replicar"
        return
    fi
    
    print_info "Total de temas a replicar: $total"
    
    echo "$topics" | jq -c '.[] | {name: .name, labels: .labels // {}}' | while read -r topic_obj; do
        local topic_full_name=$(echo "$topic_obj" | jq -r '.name')
        local topic_name=$(basename "$topic_full_name")
        local labels=$(echo "$topic_obj" | jq -c '.labels')
        
        create_topic "$topic_name" "$labels"
    done
}

replicate_subscriptions() {
    print_header "Replicando Suscripciones"
    
    local subscriptions
    subscriptions=$(jq '.subscriptions // []' "$SOURCE_FILE")
    local total
    total=$(echo "$subscriptions" | jq 'length')
    
    if [[ $total -eq 0 ]]; then
        print_warning "No hay suscripciones para replicar"
        return
    fi
    
    print_info "Total de suscripciones a replicar: $total"
    
    echo "$subscriptions" | jq -c '.[]' | while read -r sub_obj; do
        local sub_full_name=$(echo "$sub_obj" | jq -r '.name')
        local sub_name=$(basename "$sub_full_name")
        local topic_full_name=$(echo "$sub_obj" | jq -r '.topic')
        local topic_name=$(basename "$topic_full_name")
        
        create_subscription "$sub_name" "$topic_name" "$sub_obj"
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
        print_header "PubSub Replicate [DRY-RUN MODE] - $TARGET_PROJECT"
    else
        print_header "PubSub Replicate - $TARGET_PROJECT"
    fi
    
    # Validaciones previas
    check_gcloud
    check_jq
    check_gcp_auth
    check_source_file
    check_target_project
    
    # Ejecutar replicación
    replicate_topics
    replicate_subscriptions
    
    # Mostrar resumen
    show_summary
    
    if [[ "$DRY_RUN" == false ]]; then
        print_success "Replicación completada"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
