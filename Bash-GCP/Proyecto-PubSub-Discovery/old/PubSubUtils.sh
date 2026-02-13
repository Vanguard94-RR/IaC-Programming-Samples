#!/bin/bash

################################################################################
# PubSub Utilities Script
# Funciones útiles para trabajar con Pub/Sub
################################################################################

set -euo pipefail

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

################################################################################
# Funciones Auxiliares
################################################################################

print_info() { echo -e "${BLUE}ℹ $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

################################################################################
# Funciones de Validación
################################################################################

# Validar que un archivo JSON es válido
validate_json() {
    local file=$1
    if ! jq empty "$file" 2>/dev/null; then
        print_error "Archivo no es JSON válido: $file"
        return 1
    fi
    print_success "JSON válido: $file"
    return 0
}

# Validar conexión a proyecto
validate_project() {
    local project=$1
    if ! gcloud projects describe "$project" &>/dev/null; then
        print_error "No se puede acceder al proyecto: $project"
        return 1
    fi
    print_success "Proyecto accesible: $project"
    return 0
}

################################################################################
# Funciones de Estadísticas
################################################################################

# Obtener estadísticas de uso de Pub/Sub
pubsub_stats() {
    local project=$1
    
    print_info "Obteniendo estadísticas de PubSub para: $project"
    
    local topics_count=$(gcloud pubsub topics list --project="$project" --format=json | jq 'length')
    local subs_count=$(gcloud pubsub subscriptions list --project="$project" --format=json | jq 'length')
    
    echo ""
    echo "Estadísticas de PubSub - Proyecto: $project"
    echo "=========================================="
    echo "Total de Temas: $topics_count"
    echo "Total de Suscripciones: $subs_count"
    echo ""
    
    # Temas sin suscripciones
    local orphaned=0
    gcloud pubsub topics list --project="$project" --format=json | jq -r '.[] | .name' | while read -r topic; do
        local topic_name=$(basename "$topic")
        local sub_count=$(gcloud pubsub subscriptions list --project="$project" --filter="topic:$topic_name" --format=json 2>/dev/null | jq 'length')
        if [[ $sub_count -eq 0 ]]; then
            echo "  ⚠ Tema sin suscripciones: $topic_name"
            ((orphaned++))
        fi
    done
}

################################################################################
# Funciones de Comparación
################################################################################

# Comparar recursos entre dos archivos de discovery
compare_discoveries() {
    local file1=$1
    local file2=$2
    
    print_info "Comparando: $file1 vs $file2"
    
    local topics1=$(jq '.topics | length' "$file1")
    local topics2=$(jq '.topics | length' "$file2")
    local subs1=$(jq '.subscriptions | length' "$file1")
    local subs2=$(jq '.subscriptions | length' "$file2")
    
    echo ""
    echo "Comparativa de Discovery"
    echo "======================================"
    echo "Archivo 1: $(basename $file1)"
    echo "  Temas: $topics1"
    echo "  Suscripciones: $subs1"
    echo ""
    echo "Archivo 2: $(basename $file2)"
    echo "  Temas: $topics2"
    echo "  Suscripciones: $subs2"
    echo ""
    
    # Diferencias
    local diff_topics=$((topics2 - topics1))
    local diff_subs=$((subs2 - subs1))
    
    if [[ $diff_topics -gt 0 ]]; then
        print_info "Archivo 2 tiene $diff_topics temas más"
    elif [[ $diff_topics -lt 0 ]]; then
        print_info "Archivo 1 tiene $((-diff_topics)) temas más"
    else
        print_success "Mismo número de temas"
    fi
    
    if [[ $diff_subs -gt 0 ]]; then
        print_info "Archivo 2 tiene $diff_subs suscripciones más"
    elif [[ $diff_subs -lt 0 ]]; then
        print_info "Archivo 1 tiene $((-diff_subs)) suscripciones más"
    else
        print_success "Mismo número de suscripciones"
    fi
}

################################################################################
# Funciones de Limpieza
################################################################################

# Listar temas para eliminar
list_topics_to_delete() {
    local project=$1
    local filter=${2:-''}
    
    print_info "Listando temas en: $project"
    
    gcloud pubsub topics list --project="$project" --format=json | jq -r '.[] | .name' | sed 's|.*/||g' | while read -r topic; do
        if [[ -z "$filter" ]] || [[ "$topic" == *"$filter"* ]]; then
            echo "  • $topic"
        fi
    done
}

# Listar suscripciones para eliminar
list_subscriptions_to_delete() {
    local project=$1
    local filter=${2:-''}
    
    print_info "Listando suscripciones en: $project"
    
    gcloud pubsub subscriptions list --project="$project" --format=json | jq -r '.[] | .name' | sed 's|.*/||g' | while read -r sub; do
        if [[ -z "$filter" ]] || [[ "$sub" == *"$filter"* ]]; then
            echo "  • $sub"
        fi
    done
}

################################################################################
# Funciones de Análisis
################################################################################

# Analizar patrones de naming
analyze_naming_patterns() {
    local file=$1
    
    print_info "Analizando patrones de naming"
    
    echo ""
    echo "Prefijos de Temas:"
    jq -r '.topics[] | .name' "$file" | sed 's|.*/||g' | sed 's|-.*/||g' | sort | uniq -c | sort -rn
    
    echo ""
    echo "Prefijos de Suscripciones:"
    jq -r '.subscriptions[] | .name' "$file" | sed 's|.*/||g' | sed 's|-.*/||g' | sort | uniq -c | sort -rn
}

# Validar convenciones de naming
check_naming_conventions() {
    local file=$1
    local pattern=${2:-'^[a-z0-9]([a-z0-9\-]*[a-z0-9])?$'}
    
    print_info "Validando convenciones de naming contra patrón: $pattern"
    
    local invalid_topics=0
    local invalid_subs=0
    
    echo ""
    echo "Validación de Temas:"
    jq -r '.topics[] | .name' "$file" | sed 's|.*/||g' | while read -r topic; do
        if ! [[ "$topic" =~ $pattern ]]; then
            print_warning "Nombre inválido: $topic"
            ((invalid_topics++))
        fi
    done
    
    echo ""
    echo "Validación de Suscripciones:"
    jq -r '.subscriptions[] | .name' "$file" | sed 's|.*/||g' | while read -r sub; do
        if ! [[ "$sub" =~ $pattern ]]; then
            print_warning "Nombre inválido: $sub"
            ((invalid_subs++))
        fi
    done
}

################################################################################
# Funciones de Reporte
################################################################################

# Generar reporte HTML
generate_html_report() {
    local source_file=$1
    local output_file=${2:-"pubsub-report.html"}
    
    print_info "Generando reporte HTML: $output_file"
    
    local project=$(jq -r '.project_id' "$source_file")
    local timestamp=$(jq -r '.discovery_timestamp' "$source_file")
    local topics_count=$(jq '.topics | length' "$source_file")
    local subs_count=$(jq '.subscriptions | length' "$source_file")
    
    cat > "$output_file" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>PubSub Discovery Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #1f73b7; }
        .stats { background-color: #f0f0f0; padding: 10px; border-radius: 5px; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #1f73b7; color: white; }
    </style>
</head>
<body>
EOF
    
    # Agregar contenido dinámico
    cat >> "$output_file" << EOF
    <h1>PubSub Discovery Report</h1>
    <div class="stats">
        <p><strong>Proyecto:</strong> $project</p>
        <p><strong>Timestamp:</strong> $timestamp</p>
        <p><strong>Total de Temas:</strong> $topics_count</p>
        <p><strong>Total de Suscripciones:</strong> $subs_count</p>
    </div>
EOF
    
    cat >> "$output_file" << 'EOF'
</body>
</html>
EOF
    
    print_success "Reporte generado: $output_file"
}

################################################################################
# Main - Mostrar opciones
################################################################################

show_help() {
    cat << EOF
Funciones Disponibles:
======================

1. validate_json <archivo>
   Validar que un archivo JSON es válido

2. validate_project <project_id>
   Validar que puedes acceder a un proyecto

3. pubsub_stats <project_id>
   Obtener estadísticas de Pub/Sub

4. compare_discoveries <file1> <file2>
   Comparar dos archivos de discovery

5. list_topics_to_delete <project_id> [filter]
   Listar temas para eliminar

6. list_subscriptions_to_delete <project_id> [filter]
   Listar suscripciones para eliminar

7. analyze_naming_patterns <file>
   Analizar patrones de naming

8. check_naming_conventions <file> [pattern]
   Validar convenciones de naming

9. generate_html_report <source_file> [output_file]
   Generar reporte HTML

Ejemplo:
--------
source ./PubSubUtils.sh
validate_json pubsub-exports/topics-*.json

EOF
}

# Si se ejecuta como script, mostrar ayuda
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_help
fi
