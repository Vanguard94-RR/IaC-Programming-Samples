#!/bin/bash

################################################################################
# delete-appengine-versions.sh - Gestor Simple de Versiones App Engine
# Flujo completamente interactivo - NO asume nada
################################################################################

set -uo pipefail

# Directorio del script
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Librerías
source "${SCRIPT_ROOT}/lib/common.sh"
source "${SCRIPT_ROOT}/lib/gcp-operations.sh"
source "${SCRIPT_ROOT}/lib/ui.sh"

################################################################################
# MAIN
################################################################################

main() {
    # 0. PREGUNTAR TICKET (antes de setup_logs)
    ticket=$(ask_for_ticket)
    export TICKET_ID="$ticket"
    
    setup_logs
    
    print_info "Iniciando App Engine Version Manager"
    
    # 1. Validar dependencias
    if ! check_dependencies; then
        die "Instala: gcloud y jq"
    fi
    
    # 2. Validar autenticación
    if ! check_gcloud_auth; then
        die "Ejecuta: gcloud auth login"
    fi
    
    # 3. PREGUNTAR PROYECTO (nunca asumir)
    project=$(ask_for_project)
    
    if ! check_project_exists "$project"; then
        die "Proyecto '$project' no existe"
    fi
    
    if ! check_appengine_enabled "$project"; then
        die "App Engine no está habilitado en '$project'"
    fi
    
    # 4. SELECCIONAR SERVICIO
    service=$(select_service "$project")
    [[ -z "$service" ]] && die "No se seleccionó un servicio"
    
    # 5. VER VERSIONES ACTUALES
    print_info "Obteniendo versiones..." >&2
    versions=$(get_service_versions "$project" "$service") || die "Error al obtener versiones"
    
    # Debug
    [[ -z "$versions" ]] && versions="[]"
    
    serving_version=$(get_serving_version "$project" "$service") || serving_version=""
    
    local version_count
    version_count=$(echo "$versions" | jq 'length' 2>/dev/null || echo 0)
    
    if [[ $version_count -eq 0 ]]; then
        print_error "No hay versiones encontradas para el servicio '$service'"
        die "Verifica que el servicio existe y tiene versiones"
    fi
    
    print_info "Encontradas $version_count versiones" >&2
    echo ""
    echo "=== VERSIONES ACTUALES ==="
    echo ""
    format_versions_table "$versions" "$serving_version" || die "Error al formatear tabla"
    echo ""
    
    # 6. SELECCIONAR POLÍTICA
    policy=$(select_policy)
    
    # 7. CALCULAR VERSIONES A ELIMINAR
    versions_to_delete=$(calculate_versions_to_delete "$versions" "$policy" "$serving_version")
    delete_count=$(echo "$versions_to_delete" | jq 'length')
    
    if [[ $delete_count -eq 0 ]]; then
        print_info "No hay versiones para eliminar"
        exit 0
    fi
    
    # 8. MOSTRAR RESUMEN Y PEDIR CONFIRMACIÓN
    echo ""
    echo "=== RESUMEN ==="
    echo "Proyecto: $project"
    echo "Servicio: $service"
    echo "Política: $policy"
    echo "Versión en servicio: $serving_version (🔒 NO se elimina)"
    echo ""
    echo "ELIMINAR: $delete_count versiones"
    echo ""
    echo "$versions_to_delete" | jq -r '.[] | "  - \(.id) (\(.createTime[0:10]))"'
    echo ""
    
    if ! confirm_deletion; then
        print_warn "Cancelado"
        exit 0
    fi
    
    # 9. EJECUTAR
    print_info "Eliminando..."
    deleted=$(delete_versions "$project" "$service" "$versions_to_delete")
    
    print_success "Completado: $deleted versiones eliminadas"
    log "INFO" "Script terminó exitosamente"
}

main
