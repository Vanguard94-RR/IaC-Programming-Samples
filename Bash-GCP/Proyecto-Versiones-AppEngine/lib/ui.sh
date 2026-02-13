#!/bin/bash

################################################################################
# lib/ui.sh - Interfaz Simple
################################################################################

# Preguntar ticket ID
ask_for_ticket() {
    echo "" >&2
    echo "╔════════════════════════════════════════════════════════════════╗" >&2
    echo "║          GNP App Engine Version Manager                        ║" >&2
    echo "╚════════════════════════════════════════════════════════════════╝" >&2
    echo "" >&2
    
    read -rp "¿Número de ticket (opcional, presiona Enter para omitir): " ticket
    ticket=$(echo "$ticket" | xargs | tr '[:lower:]' '[:upper:]')
    
    if [[ -z "$ticket" ]]; then
        echo "" >&2
        echo "⚠️  Sin ticket especificado" >&2
        echo "📁 El log se guardará en: /home/admin/Documents/GNP/Proyecto-Versiones-AppEngine/logs/" >&2
        echo "" >&2
        printf "%s" ""
        return 0
    fi
    
    # Validar formato de ticket
    if [[ ! "$ticket" =~ ^(CTASK|TASK|INC|CHG|PRB|REQ)[0-9]{6,8}$ ]]; then
        print_error "Formato inválido. Usa: CTASK1234567, TASK1234567, etc."
        ask_for_ticket
        return
    fi
    
    # Crear carpeta del ticket si no existe
    local ticket_dir="/home/admin/Documents/GNP/Tickets/$ticket"
    if [[ ! -d "$ticket_dir" ]]; then
        print_info "Creando directorio del ticket..."
        mkdir -p "$ticket_dir"/{docs,scripts,backups,logs,configs}
        chmod 700 "$ticket_dir"
        
        # Crear README
        cat > "$ticket_dir/README.md" << READMEEOF
# Ticket: $ticket

## Description
App Engine Version Cleanup Task

## Directory Structure
- \`docs/\` - Documentation
- \`scripts/\` - Scripts used
- \`backups/\` - Backup files
- \`logs/\` - Log files
- \`configs/\` - Configuration files

## Created
- **Date:** $(date +'%Y-%m-%d %H:%M:%S')
- **User:** $(whoami)
READMEEOF
    fi
    
    echo "" >&2
    echo "✅ Ticket: $ticket" >&2
    echo "📁 Logs en: $ticket_dir/logs/" >&2
    echo "" >&2
    
    printf "%s" "$ticket"
}

# Preguntar proyecto (NUNCA asumir)
ask_for_project() {
    local project
    echo "" >&2
    read -rp "Ingresa ID del proyecto GCP: " project
    project=$(printf "%s" "$project" | xargs)  # Limpiar espacios y saltos de línea
    [[ -z "$project" ]] && { print_error "No puede estar vacío"; ask_for_project; return; }
    printf "%s" "$project"
}

# Seleccionar servicio
select_service() {
    local project=$1
    print_info "Obteniendo servicios..." >&2
    local services
    services=$(get_services "$project")
    local count
    count=$(echo "$services" | jq 'length')
    
    [[ $count -eq 0 ]] && { print_error "No hay servicios"; return 1; }
    
    # Si solo hay uno
    if [[ $count -eq 1 ]]; then
        echo "$services" | jq -r '.[0].id' | tr -d '\n' | tr -d ' '
        return 0
    fi
    
    echo "" >&2
    echo "Servicios:" >&2
    echo "$services" | jq -r '.[] | "\(.id)"' | nl >&2
    echo "" >&2
    
    while true; do
        read -rp "Selecciona número o nombre: " selection
        selection=$(printf "%s" "$selection" | xargs)  # Limpiar espacios
        
        if [[ $selection =~ ^[0-9]+$ ]]; then
            local service
            service=$(echo "$services" | jq -r ".[$((selection-1))].id" 2>/dev/null)
            [[ -n "$service" && "$service" != "null" ]] && { printf "%s" "$service"; return 0; }
        else
            echo "$services" | jq -e ".[] | select(.id==\"$selection\")" >/dev/null 2>&1 && { printf "%s" "$selection"; return 0; }
        fi
        
        print_error "Inválido: $selection"
    done
}

# Seleccionar política
select_policy() {
    while true; do
        echo "" >&2
        echo "Política de retención de versiones:" >&2
        echo "" >&2
        echo "  1) recent-10      Mantener 10 recientes, eliminar las antiguas" >&2
        echo "  2) recent-5       Mantener 5 recientes, eliminar las antiguas" >&2
        echo "  3) monthly-3      Una versión por mes (últimos 3 meses)" >&2
        echo "  4) monthly-6      Una versión por mes (últimos 6 meses)" >&2
        echo "  5) monthly-9      Una versión por mes (últimos 9 meses)" >&2
        echo "  6) Personalizado  Mantener N recientes, eliminar las antiguas" >&2
        echo "" >&2
        
        read -rp "¿Cuál prefieres? (escribe 1, 2, 3, 4, 5 o 6): " choice
        choice=$(echo "$choice" | xargs)  # Limpiar espacios
        
        case $choice in
            1) printf "%s" "recent-10"; return 0 ;;
            2) printf "%s" "recent-5"; return 0 ;;
            3) printf "%s" "monthly-3"; return 0 ;;
            4) printf "%s" "monthly-6"; return 0 ;;
            5) printf "%s" "monthly-9"; return 0 ;;
            6)
                read -rp "¿Cuántas versiones recientes mantener?: " custom
                custom=$(echo "$custom" | xargs)
                if [[ $custom =~ ^[0-9]+$ && $custom -gt 0 ]]; then
                    printf "%s" "recent-$custom"
                    return 0
                else
                    print_error "Ingresa un número válido"
                fi
                ;;
            *) print_error "Opción no válida. Escribe 1, 2, 3, 4, 5 o 6" ;;
        esac
    done
}

# Confirmar eliminación
confirm_deletion() {
    echo ""
    read -rp "Confirma eliminación (escribe 'eliminar'): " response
    response=$(echo "$response" | xargs)  # Limpiar espacios
    [[ "$response" == "eliminar" ]] && return 0 || return 1
}

# Mostrar tabla de versiones
format_versions_table() {
    local versions_json=$1
    local serving_version=$2
    
    echo "VERSION                      FECHA       ESTADO"
    echo "══════════════════════════════════════════════════"
    
    local version_ids
    mapfile -t version_ids < <(echo "$versions_json" | jq -r '.[].id')
    local version_dates
    mapfile -t version_dates < <(echo "$versions_json" | jq -r '.[].version.createTime[0:10]')
    
    for i in "${!version_ids[@]}"; do
        local version="${version_ids[$i]}"
        local date="${version_dates[$i]}"
        
        if [[ "$version" == "$serving_version" ]]; then
            printf "%-30s %s %s\n" "$version" "$date" "🔒 SIRVIENDO"
        else
            printf "%-30s %s\n" "$version" "$date"
        fi
    done
}

# Calcular versiones a eliminar
calculate_versions_to_delete() {
    local versions=$1
    local policy=$2
    local serving_version=$3
    
    case $policy in
        recent-*)
            local keep
            keep=$(echo "$policy" | cut -d'-' -f2)
            get_versions_to_delete_recent "$versions" "$keep" "$serving_version"
            ;;
        monthly-*)
            local months
            months=$(echo "$policy" | cut -d'-' -f2)
            get_versions_to_delete_monthly "$versions" "$months" "$serving_version"
            ;;
        *) echo "[]" ;;
    esac
}
