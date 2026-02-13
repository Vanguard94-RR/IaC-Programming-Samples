#!/bin/bash

################################################################################
# PubSub Subscriptions Replicate Script
# Objetivo: Replicar suscripciones con todas sus configuraciones
################################################################################

set -eo pipefail

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Variables
SOURCE_FILE=""
TARGET_PROJECT=""
DRY_RUN=false
REPLICATED_COUNT=0
FAILED_COUNT=0

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

################################################################################
# Replicación de Topics
################################################################################

replicate_topics() {
    print_header "Verificando y Replicando Topics"
    
    # Extraer topics necesarios del archivo
    local topics_array=()
    mapfile -t topics_array < <(jq -r '.[] | .topic' "$SOURCE_FILE" | sed 's|.*/topics/||' | sort -u)
    
    local topics_count=${#topics_array[@]}
    
    if [[ $topics_count -eq 0 ]]; then
        print_warning "No se encontraron topics"
        return
    fi
    
    print_info "Topics a procesar: $topics_count"
    echo ""
    
    # Obtener lista de topics existentes en el proyecto destino (UNA SOLA LLAMADA)
    local existing_topics_raw
    existing_topics_raw=$(timeout 30s gcloud pubsub topics list \
        --project="$TARGET_PROJECT" \
        --format="value(name)" 2>&1)
    local list_exit=$?
    
    if [[ $list_exit -eq 124 ]]; then
        print_error "Timeout al listar topics existentes"
        return 1
    fi
    
    # Extraer solo nombres de topics (sin path completo)
    local existing_topics_array=()
    if [[ -n "$existing_topics_raw" ]]; then
        mapfile -t existing_topics_array < <(echo "$existing_topics_raw" | sed 's|.*/topics/||')
    fi
    
    topics_created=0
    topics_skipped=0
    
    # Procesar cada topic necesario
    for i in "${!topics_array[@]}"; do
        local topic_name="${topics_array[$i]}"
        
        if [[ -z "$topic_name" || "$topic_name" == "null" ]]; then
            continue
        fi
        
        local counter=$((i + 1))
        echo -n "  [$counter/$topics_count] $topic_name - "
        
        # Verificar si ya existe (búsqueda en array local, sin llamada API)
        local exists=false
        for existing in "${existing_topics_array[@]}"; do
            if [[ "$existing" == "$topic_name" ]]; then
                exists=true
                break
            fi
        done
        
        if [[ "$exists" == true ]]; then
            echo "Ya existe ✓"
            topics_skipped=$((topics_skipped + 1))
        elif [[ "$DRY_RUN" == true ]]; then
            echo "Se crearía [DRY-RUN]"
            topics_created=$((topics_created + 1))
        else
            # Solo crear si NO existe
            echo -n "Creando... "
            local create_result
            create_result=$(timeout 15s gcloud pubsub topics create "$topic_name" \
                --project="$TARGET_PROJECT" \
                --format=json 2>&1)
            local create_exit=$?
            
            if [[ $create_exit -eq 0 ]]; then
                echo "✓"
                topics_created=$((topics_created + 1))
            elif [[ $create_exit -eq 124 ]]; then
                echo "⚠ Timeout"
            else
                echo "✗ Error"
            fi
        fi
    done
    
    echo ""
    print_success "Topics: Creados=$topics_created | Existentes=$topics_skipped"
    echo ""
}

################################################################################
# Replicación de Suscripciones
################################################################################

replicate_subscription() {
    local sub_obj=$1
    local sub_name=$(echo "$sub_obj" | jq -r '.name' | xargs basename)
    local topic=$(echo "$sub_obj" | jq -r '.topic' | xargs basename)
    
    print_info "Replicando: $sub_name"
    
    # Construir comando como array para evitar problemas de spacing
    local cmd_args=(
        "gcloud" "pubsub" "subscriptions" "create" "$sub_name"
        "--topic=$topic"
        "--project=$TARGET_PROJECT"
        "--format=none"
    )
    
    # Agregar ackDeadlineSeconds si existe
    local ack_deadline=$(echo "$sub_obj" | jq -r '.ackDeadlineSeconds // empty')
    if [[ -n "$ack_deadline" ]]; then
        cmd_args+=("--ack-deadline=$ack_deadline")
    fi
    
    # Agregar message retention duration si existe
    local retention=$(echo "$sub_obj" | jq -r '.messageRetentionDuration // empty')
    if [[ -n "$retention" ]]; then
        # Convertir formato ISO8601 a segundos si es necesario
        if [[ "$retention" == *"s" ]]; then
            local seconds=${retention%s}
            cmd_args+=("--message-retention-duration=${seconds}s")
        fi
    fi
    
    # Agregar filtro si existe
    local filter=$(echo "$sub_obj" | jq -r '.filter // empty')
    if [[ -n "$filter" ]]; then
        cmd_args+=("--message-filter=$filter")
    fi
    
    # Agregar labels si existen
    local labels=$(echo "$sub_obj" | jq -r '.labels // {} | to_entries | map("\(.key)=\(.value)") | join(",") | select(length > 0)')
    if [[ -n "$labels" ]]; then
        cmd_args+=("--labels=$labels")
    fi
    
    # Ejecutar comando
    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY-RUN] ${cmd_args[*]}"
        REPLICATED_COUNT=$((REPLICATED_COUNT + 1))
        return 0
    fi
    
    local output
    local exit_code
    
    # Ejecutar con timeout y capturar exit code de forma segura
    set +e
    output=$(timeout --kill-after=5s 20s "${cmd_args[@]}" 2>&1)
    exit_code=$?
    set -e
    
    if [[ $exit_code -eq 124 ]]; then
        print_warning "⚠ Timeout al crear: $sub_name (20s)"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        return 1
    elif [[ $exit_code -eq 0 ]]; then
        print_success "Suscripción creada: $sub_name"
        REPLICATED_COUNT=$((REPLICATED_COUNT + 1))
        return 0
    elif echo "$output" | grep -qi "already exists"; then
        print_info "Suscripción ya existe: $sub_name (saltando)"
        REPLICATED_COUNT=$((REPLICATED_COUNT + 1))
        return 0
    else
        print_warning "Error al crear: $sub_name"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        return 1
    fi
}

replicate_all() {
    print_header "Replicando Suscripciones"
    
    local sub_count=$(jq 'length' "$SOURCE_FILE")
    
    if [[ $sub_count -eq 0 ]]; then
        print_warning "No hay suscripciones para replicar"
        return
    fi
    
    print_info "Total de suscripciones a replicar: $sub_count"
    echo ""
    
    local counter=0
    
    while IFS= read -r sub_obj; do
        counter=$((counter + 1))
        replicate_subscription "$sub_obj"
        echo ""
    done < <(jq -c '.[]' "$SOURCE_FILE")
}

show_summary() {
    print_header "Resumen de Replicación"
    
    echo ""
    echo -e "${CYAN}Topics:${NC}"
    echo "  Creados: ${topics_created:-0}"
    echo "  Ya existían: ${topics_skipped:-0}"
    echo ""
    echo -e "${CYAN}Suscripciones:${NC}"
    echo "  Replicadas: $REPLICATED_COUNT"
    echo "  Errores: $FAILED_COUNT"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        print_warning "Modo DRY-RUN: No se realizaron cambios reales"
    fi
    
    # Generar reporte
    generate_report
}

generate_report() {
    local timestamp=$(date "+%Y%m%d_%H%M%S")
    local report_dir="./subscriptions-exports"
    local report_file="${report_dir}/REPLICATE-REPORT-${TARGET_PROJECT}-${timestamp}.txt"
    
    # Crear directorio si no existe
    mkdir -p "$report_dir"
    
    # Generar contenido del reporte
    cat > "$report_file" << EOF
========================================
PubSub Subscriptions Replication Report
========================================

Proyecto Destino: ${TARGET_PROJECT}
Timestamp: $(date)
Archivo Fuente: $(basename "$SOURCE_FILE")
Modo: $(if [[ "$DRY_RUN" == true ]]; then echo "DRY-RUN (Simulación)"; else echo "EJECUCIÓN REAL"; fi)

Resumen de Topics:
------------------
Topics creados: ${topics_created:-0}
Topics ya existentes: ${topics_skipped:-0}
Total procesados: $((${topics_created:-0} + ${topics_skipped:-0}))

Resumen de Suscripciones:
-------------------------
Suscripciones creadas: $REPLICATED_COUNT
Suscripciones con error: $FAILED_COUNT
Total procesadas: $((REPLICATED_COUNT + FAILED_COUNT))

Estado Final:
-------------
EOF

    if [[ "$DRY_RUN" == true ]]; then
        cat >> "$report_file" << EOF
⚠ MODO SIMULACIÓN: No se realizaron cambios reales en el proyecto.
  Ejecuta sin --dry-run para aplicar los cambios.
EOF
    elif [[ $FAILED_COUNT -eq 0 ]]; then
        cat >> "$report_file" << EOF
✓ ÉXITO: Todas las suscripciones se replicaron correctamente.
  No se encontraron errores durante la ejecución.
EOF
    else
        cat >> "$report_file" << EOF
⚠ COMPLETADO CON ERRORES: $FAILED_COUNT suscripción(es) fallaron.
  Revisa los logs de ejecución para más detalles.
  Las suscripciones exitosas ($REPLICATED_COUNT) fueron creadas correctamente.
EOF
    fi
    
    echo ""
    echo "Notas:"
    echo "------"
    if [[ ${topics_created:-0} -gt 0 ]]; then
        echo "- Se crearon ${topics_created} topic(s) nuevo(s)"
    fi
    if [[ $REPLICATED_COUNT -gt 0 ]]; then
        echo "- Se replicaron $REPLICATED_COUNT suscripción(es) con todas sus configuraciones"
    fi
    echo "- Topics y suscripciones ya existentes fueron omitidos"
    
    cat >> "$report_file" << EOF

Comando Ejecutado:
------------------
./SubscriptionsReplicate.sh \\
    --source-file $SOURCE_FILE \\
    --target-project $TARGET_PROJECT$(if [[ "$DRY_RUN" == true ]]; then echo " \\"; echo "    --dry-run"; fi)

========================================
Reporte generado: $report_file
========================================
EOF
    
    echo ""
    print_success "Reporte guardado: $report_file"
}

show_usage() {
    cat << EOF
Uso: $0 [OPCIONES]

Replica suscripciones de Pub/Sub a un proyecto destino.

Opciones:
    -s, --source-file FILE      Archivo JSON de suscripciones (requerido)
    -t, --target-project ID     ID del proyecto destino (requerido)
    -d, --dry-run               Modo simulación (no realiza cambios)
    -h, --help                  Mostrar esta ayuda

Ejemplos:
    $0 -s subscriptions-MISSING.json -t mi-proyecto-destino
    $0 --source-file subscriptions-export.json --target-project target --dry-run

EOF
}

################################################################################
# Main
################################################################################

main() {
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
    
    if [[ -z "$SOURCE_FILE" ]] || [[ -z "$TARGET_PROJECT" ]]; then
        print_error "Se requieren los argumentos --source-file y --target-project"
        show_usage
        exit 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        print_header "PubSub Subscriptions Replicate [DRY-RUN MODE]"
    else
        print_header "PubSub Subscriptions Replicate"
    fi
    
    check_tools
    check_auth
    check_project
    check_source_file
    
    # Primero replicar topics
    replicate_topics
    
    # Luego replicar suscripciones
    replicate_all
    show_summary
    
    if [[ "$DRY_RUN" == false ]] && [[ $FAILED_COUNT -eq 0 ]]; then
        print_success "Replicación completada exitosamente"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
