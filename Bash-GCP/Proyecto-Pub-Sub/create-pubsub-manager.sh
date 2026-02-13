#!/bin/bash

################################################################################
# create-pubsub-manager.sh - Gestor Idempotente y Seguro de Pub/Sub
# 
# Uso: ./create-pubsub-manager.sh [config-file]
#
# Características:
# - Idempotente: No falla si los recursos ya existen
# - Seguro: Validaciones en cada paso
# - Simple: Modular con librerías básicas
# - Auditado: Logs detallados de todas las operaciones
################################################################################

set -uo pipefail

# Directorio del script
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Importar librerías
source "${SCRIPT_ROOT}/lib/common.sh"
source "${SCRIPT_ROOT}/lib/gcp-operations.sh"

################################################################################
# FUNCIONES PRINCIPALES
################################################################################

# Procesar archivo de configuración y crear recursos
process_config_file() {
    local config_file=$1
    local project=$2
    
    if [[ ! -f "$config_file" ]]; then
        die "Archivo de configuración no existe: $config_file"
    fi
    
    print_info "Procesando: $config_file"
    
    # Validar que el proyecto en el archivo coincide
    local file_project
    file_project=$(yq eval '.project' "$config_file" 2>/dev/null || echo "")
    
    if [[ -z "$file_project" ]]; then
        die "El archivo debe incluir 'project: <project-id>'"
    fi
    
    if [[ "$file_project" != "$project" ]]; then
        print_warn "Proyecto en archivo: $file_project"
        print_warn "Proyecto ingresado: $project"
        print_info "Se usará '$project' como proyecto base para suscripciones"
        print_info "Los recursos pueden especificar 'topic_project' para usar proyectos diferentes"
    fi
    
    local created=0
    local failed=0
    
    # Obtener cantidad de recursos
    local resource_count
    resource_count=$(yq eval '.resources | length' "$config_file")
    
    if [[ $resource_count -eq 0 ]]; then
        die "No hay recursos en el archivo"
    fi
    
    print_info "Encontrados $resource_count recursos"
    
    # Procesar cada recurso
    for ((i=0; i<resource_count; i++)); do
        local resource_type
        resource_type=$(yq eval ".resources[$i].type" "$config_file")
        
        case "$resource_type" in
            topic)
                if process_topic_resource "$config_file" "$project" "$i"; then
                    ((created++)) || true
                else
                    ((failed++)) || true
                fi
                ;;
            subscription)
                if process_subscription_resource "$config_file" "$project" "$i"; then
                    ((created++)) || true
                else
                    ((failed++)) || true
                fi
                ;;
            *)
                print_error "Tipo desconocido: $resource_type"
                ((failed++)) || true
                ;;
        esac
    done
    
    echo ""
    print_success "Completado: $created creados, $failed errores"
    
    return $([[ $failed -eq 0 ]] && echo 0 || echo 1)
}

# Procesar recurso de tipo topic
process_topic_resource() {
    local config_file=$1
    local project=$2
    local index=$3
    
    local topic
    topic=$(yq eval ".resources[$index].name" "$config_file")
    
    local retention_days
    retention_days=$(yq eval ".resources[$index].retention_days // 7" "$config_file")
    
    local topic_project
    topic_project=$(yq eval ".resources[$index].topic_project // \"$project\"" "$config_file")
    
    if [[ "$topic_project" != "$project" ]]; then
        print_info "Topic: $topic (en proyecto: $topic_project)"
    else
        print_info "Topic: $topic"
    fi
    
    if create_topic "$topic_project" "$topic" "$retention_days"; then
        return 0
    else
        return 1
    fi
}

# Procesar recurso de tipo subscription
process_subscription_resource() {
    local config_file=$1
    local project=$2
    local index=$3
    
    local subscription
    subscription=$(yq eval ".resources[$index].name" "$config_file")
    
    local topic
    topic=$(yq eval ".resources[$index].topic" "$config_file")
    
    local ack_deadline
    ack_deadline=$(yq eval ".resources[$index].ack_deadline // 600" "$config_file")
    
    local retention_days
    retention_days=$(yq eval ".resources[$index].retention_days // 7" "$config_file")
    
    local topic_project
    topic_project=$(yq eval ".resources[$index].topic_project // \"$project\"" "$config_file")
    
    print_info "Subscription: $subscription -> $topic"
    
    # Validar que el topic existe
    if ! topic_exists "$topic_project" "$topic"; then
        print_error "Topic '$topic' no existe en proyecto '$topic_project'"
        return 1
    fi
    
    # Crear suscripción
    if create_subscription "$project" "$subscription" "$topic" "$ack_deadline" "$retention_days"; then
        return 0
    else
        return 1
    fi
}



################################################################################
# MAIN
################################################################################

main() {
    # 0. Pedir ticket
    local ticket
    ticket=$(ask_for_ticket)
    export TICKET_ID="$ticket"
    
    setup_logs
    
    print_info "Pub/Sub Manager"
    
    # 1. Validar dependencias
    if ! check_dependencies; then
        die "Instala: gcloud, jq, yq"
    fi
    
    # 2. Validar autenticación
    if ! check_gcloud_auth; then
        die "Ejecuta: gcloud auth login"
    fi
    
    # 3. Pedir proyecto
    local project
    project=$(ask_for_project)
    
    if ! check_project_exists "$project"; then
        die "Proyecto no existe: $project"
    fi
    
    if ! pubsub_enabled "$project"; then
        print_warn "Habilitando Pub/Sub..."
        if ! gcloud services enable pubsub.googleapis.com --project="$project"; then
            die "Error habilitando Pub/Sub"
        fi
    fi
    
    print_success "Proyecto validado: $project"
    
    # 4. Pedir archivo de configuración
    echo ""
    read -rp "Archivo de configuración: " config_file
    config_file=$(echo "$config_file" | xargs)
    
    if [[ -z "$config_file" ]]; then
        die "Debes especificar un archivo"
    fi
    
    # Construir la ruta completa al archivo de configuración
    local full_config_path="${SCRIPT_ROOT}/configs/${config_file}"

    # 5. Procesar
    process_config_file "$full_config_path" "$project"
}

# Ejecutar si no está siendo sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
