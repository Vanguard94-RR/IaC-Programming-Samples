#!/bin/bash

################################################################################
# Workflow Deployment - Interactive Mode (Bash)
################################################################################
# Script bash interactivo para desplegar workflows de GitLab a GCP
#
# Características:
#   • Interfaz amigable similar a workload-identity.sh
#   • Validación en tiempo real
#   • Preview visual antes de desplegar
#   • Historial de despliegues
#
# Uso:
#   ./workflow-deploy-interactive.sh
#
# Autor: GNP Infrastructure Team
################################################################################

set -euo pipefail

# Cargar variables de ambiente
[ -f .env.local ] && source .env.local

# Cargar token de GitLab si no está disponible
if [ -z "${GITLAB_TOKEN:-}" ]; then
    TOKEN_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../../PersonalGitLabToken"
    if [ -f "$TOKEN_FILE" ]; then
        GITLAB_TOKEN=$(cat "$TOKEN_FILE")
    fi
fi

# Validar que el token esté disponible
if [ -z "${GITLAB_TOKEN:-}" ]; then
    echo "✗ Error: GITLAB_TOKEN no disponible" >&2
    exit 1
fi

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly GRAY='\033[0;90m'
readonly LGREEN='\033[1;32m'
readonly LCYAN='\033[1;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'  # No Color

# Script info
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HISTORY_FILE="$SCRIPT_DIR/deployment_history.log"
readonly LOG_FILE="$SCRIPT_DIR/workflow.log"

################################################################################
# Utility Functions
################################################################################

clear_screen() {
    clear
}

print_header() {
    local title="$1"
    echo -e "${LCYAN}════════════════════════════════════════${NC}"
    echo -e "${LCYAN}║${NC} $title"
    echo -e "${LCYAN}════════════════════════════════════════${NC}"
    echo ""
}

print_info() {
    echo -e "${LCYAN}•${NC} $1"
}

print_success() {
    echo -e "${LGREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

prompt_input() {
    local prompt="$1"
    local var_name="$2"
    local default="${3:-}"
    
    local msg="${YELLOW}${prompt}${NC}"
    if [[ -n "$default" ]]; then
        msg="${msg} [${GRAY}${default}${NC}]"
    fi
    
    echo -ne "${msg}: "
    read -r input_value
    
    if [[ -z "$input_value" ]] && [[ -n "$default" ]]; then
        input_value="$default"
    fi
    
    printf -v "$var_name" '%s' "$input_value"
}

validate_url() {
    [[ "$1" =~ gitlab.com ]] && [[ "$1" =~ /-/blob/ ]]
}

validate_project_id() {
    [[ "$1" =~ ^[a-zA-Z0-9-]+$ ]]
}

validate_workflow_name() {
    [[ "$1" =~ ^[a-zA-Z0-9-]+$ ]]
}

save_to_history() {
    local workflow="$1"
    local project="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "$timestamp | $workflow | $project" >> "$HISTORY_FILE" 2>/dev/null || true
}

################################################################################
# Input Steps
################################################################################

step_1_gitlab_source() {
    clear_screen
    print_header "Paso 1: Fuente de GitLab"
    
    echo -e "${GRAY}¿De dónde descargar el workflow?${NC}\n"
    
    echo -e "  ${LCYAN}1)${NC} Ingresar URL completa de GitLab"
    echo -e "  ${LCYAN}2)${NC} Ingresar detalles por separado"
    echo -e "  ${LCYAN}0)${NC} Cancelar"
    echo ""
    
    echo -ne "${YELLOW}Opción${NC}: "
    read -r choice
    
    case "$choice" in
        1)
            while true; do
                prompt_input "URL de GitLab" "GITLAB_URL"
                if validate_url "$GITLAB_URL"; then
                    echo -e "${LGREEN}✓ URL válida${NC}\n"
                    return 0
                else
                    print_error "URL inválida. Debe contener 'gitlab.com' y '/-/blob/'"
                fi
            done
            ;;
        2)
            prompt_input "Proyecto GitLab (ej: grupo/proyecto)" "GITLAB_PROJECT"
            prompt_input "Rama o tag" "GITLAB_BRANCH" "main"
            prompt_input "Ruta del archivo" "GITLAB_FILE"
            return 0
            ;;
        0)
            return 1
            ;;
        *)
            print_error "Opción inválida"
            step_1_gitlab_source
            ;;
    esac
}

step_2_gcp_target() {
    clear_screen
    print_header "Paso 2: Destino en Google Cloud"
    
    while true; do
        prompt_input "Nombre del workflow en GCP" "WORKFLOW_NAME"
        if validate_workflow_name "$WORKFLOW_NAME"; then
            break
        fi
        print_error "Nombre inválido. Solo alfanuméricos y guiones"
    done
    
    while true; do
        prompt_input "Project ID de GCP" "GCP_PROJECT"
        if validate_project_id "$GCP_PROJECT"; then
            break
        fi
        print_error "Project ID inválido. Solo alfanuméricos y guiones"
    done
    
    prompt_input "Región de GCP" "GCP_LOCATION" "us-central1"
    
    echo ""
}

step_3_options() {
    clear_screen
    print_header "Paso 3: Opciones Adicionales"
    
    echo -e "${GRAY}¿Qué modo de despliegue deseas?${NC}\n"
    
    echo -e "  ${LCYAN}1)${NC} Normal - Desplegar después de validar"
    echo -e "  ${LCYAN}2)${NC} DRY-RUN - Simular sin desplegar"
    echo -e "  ${LCYAN}3)${NC} SKIP-VALIDATION - Omitir validación"
    echo -e "  ${LCYAN}0)${NC} Volver"
    echo ""
    
    echo -ne "${YELLOW}Opción${NC}: "
    read -r choice
    
    DRY_RUN=false
    SKIP_VALIDATION=false
    
    case "$choice" in
        1) ;;
        2) DRY_RUN=true ;;
        3) SKIP_VALIDATION=true ;;
        0) return 1 ;;
        *) 
            print_error "Opción inválida"
            step_3_options
            return $?
            ;;
    esac
    
    echo ""
}

step_4_preview() {
    clear_screen
    print_header "Paso 4: Confirmación"
    
    echo -e "${WHITE}Resumen de la configuración:${NC}\n"
    
    echo -e "${LCYAN}Fuente (GitLab):${NC}"
    if [[ -n "${GITLAB_URL:-}" ]]; then
        echo -e "  ${GRAY}URL:${NC} $GITLAB_URL"
    else
        echo -e "  ${GRAY}Proyecto:${NC} $GITLAB_PROJECT"
        echo -e "  ${GRAY}Rama/Tag:${NC} $GITLAB_BRANCH"
        echo -e "  ${GRAY}Archivo:${NC} $GITLAB_FILE"
    fi
    
    echo -e "\n${LCYAN}Destino (GCP):${NC}"
    echo -e "  ${GRAY}Workflow:${NC} $WORKFLOW_NAME"
    echo -e "  ${GRAY}Proyecto:${NC} $GCP_PROJECT"
    echo -e "  ${GRAY}Región:${NC} $GCP_LOCATION"
    
    echo -e "\n${LCYAN}Opciones:${NC}"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${GRAY}Modo:${NC} ${YELLOW}🔸 DRY-RUN${NC}"
    else
        echo -e "  ${GRAY}Modo:${NC} ${LGREEN}✓ Normal${NC}"
    fi
    
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        echo -e "  ${GRAY}Validación:${NC} ${YELLOW}Omitida${NC}"
    else
        echo -e "  ${GRAY}Validación:${NC} ${LGREEN}Habilitada${NC}"
    fi
    
    echo -e "\n${GRAY}¿Qué deseas hacer?${NC}\n"
    
    echo -e "  ${LCYAN}1)${NC} Continuar con el despliegue"
    echo -e "  ${LCYAN}2)${NC} Volver al paso anterior"
    echo -e "  ${LCYAN}0)${NC} Cancelar todo"
    echo ""
    
    echo -ne "${YELLOW}Opción${NC}: "
    read -r choice
    
    case "$choice" in
        1) return 0 ;;
        2) return 1 ;;
        0) return 2 ;;
        *) 
            print_error "Opción inválida"
            step_4_preview
            return $?
            ;;
    esac
}

step_5_review_content() {
    local yaml_file="$1"

    [[ -s "$yaml_file" ]] || { print_error "Archivo no disponible para revisión"; return 1; }

    clear_screen
    print_header "Paso 5: Revisión del Contenido"

    local total_lines
    total_lines=$(wc -l < "$yaml_file")

    echo -e "${GRAY}Primeras 50 líneas del workflow descargado (${total_lines} líneas totales):${NC}\n"
    printf '%b' "${CYAN}"
    head -n 50 "$yaml_file"
    printf '%b\n' "${NC}"

    echo -e "${GRAY}¿Qué deseas hacer?${NC}\n"
    echo -e "  ${LCYAN}1)${NC} Continuar con el despliegue"
    echo -e "  ${LCYAN}0)${NC} Cancelar"
    echo ""

    while true; do
        echo -ne "${YELLOW}Opción${NC}: "
        read -r choice

        case "$choice" in
            1) return 0 ;;
            0) return 1 ;;
            *)
                print_error "Opción inválida"
                ;;
        esac
    done
}

################################################################################
# Deployment Execution
################################################################################

parse_gitlab_url() {
    local url="$1"
    # Extraer: https://gitlab.com/group/project/-/blob/branch/path/to/file.yml
    
    if [[ ! "$url" =~ gitlab.com ]]; then
        return 1
    fi
    
    # Extraer componentes de la URL
    local project_part="${url#*gitlab.com/}"
    local branch_part="${project_part#*/-/blob/}"
    local branch="${branch_part%%/*}"
    local file_part="${branch_part#*/}"
    local project="${project_part%%/-/blob*}"
    
    echo "$project|$branch|$file_part"
}

download_workflow() {
    local url="$1"
    local output_file="$2"
    
    local parsed
    parsed=$(parse_gitlab_url "$url") || {
        print_error "URL de GitLab inválida"
        return 1
    }
    
    local project branch file_path
    IFS='|' read -r project branch file_path <<< "$parsed"
    
    print_info "Descargando desde GitLab..."
    print_info "Proyecto: $project"
    print_info "Rama: $branch"
    print_info "Archivo: $file_path"
    
    local gitlab_api_url
    gitlab_api_url="https://gitlab.com/api/v4/projects/${project//\//%2F}/repository/files/${file_path//\//%2F}/raw"

    # Write token to a temp curl config file to avoid exposure in process list
    local curl_config
    curl_config=$(mktemp)
    printf 'header = "PRIVATE-TOKEN: %s"\n' "$GITLAB_TOKEN" > "$curl_config"

    local curl_exit=0
    local http_code
    http_code=$(curl -s -K "$curl_config" \
        -o "$output_file" \
        -w "%{http_code}" \
        "$gitlab_api_url?ref=$branch" 2>/dev/null) || curl_exit=$?
    rm -f "$curl_config"

    if [ "$curl_exit" -ne 0 ]; then
        print_error "No se pudo descargar el archivo"
        return 1
    fi

    if [ ! -s "$output_file" ]; then
        print_error "Archivo descargado está vacío"
        return 1
    fi

    if [ "$http_code" != "200" ]; then
        print_error "GitLab respondió HTTP $http_code — verifica rama, ruta y token"
        return 1
    fi
    
    print_success "Archivo descargado"
}

validate_workflow() {
    local yaml_file="$1"
    
    print_info "Validando estructura del workflow..."
    
    # Validar que sea YAML válido (búsqueda simple)
    if ! grep -q "^main:" "$yaml_file"; then
        print_error "El workflow debe tener un entry point 'main:'"
        return 1
    fi
    
    print_success "Validación OK"
}

deploy_workflow() {
    local yaml_file="$1"
    local workflow_name="$2"
    local project_id="$3"
    local region="${4:-us-central1}"
    
    print_info "Desplegando workflow..."
    print_info "Nombre: $workflow_name"
    print_info "Proyecto: $project_id"
    print_info "Región: $region"
    
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI no disponible"
        return 1
    fi
    
    if gcloud workflows deploy "$workflow_name" \
        --source="$yaml_file" \
        --project="$project_id" \
        --location="$region" \
        --quiet 2>&1; then
        print_success "Workflow desplegado exitosamente"
        save_to_history "$workflow_name" "$project_id"
        return 0
    else
        print_error "Falló el despliegue"
        return 1
    fi
}

build_command() {
    local cmd="echo 'Ejecutando despliegue...'"
    echo "$cmd"
}

execute_deployment() {
    clear_screen
    print_header "Ejecutando Despliegue"
    
    local temp_file
    temp_file=$(mktemp /tmp/workflow-XXXXXX.yaml)
    trap 'rm -f "$temp_file"; trap - RETURN' RETURN
    
    echo ""
    
    # Descargar
    if [[ -n "${GITLAB_URL:-}" ]]; then
        download_workflow "$GITLAB_URL" "$temp_file" || return 1
    else
        # Construir URL desde componentes
        local gitlab_url="https://gitlab.com/$GITLAB_PROJECT/-/blob/$GITLAB_BRANCH/$GITLAB_FILE"
        download_workflow "$gitlab_url" "$temp_file" || return 1
    fi
    
    echo ""
    
    # Validar
    if [[ "$SKIP_VALIDATION" != "true" ]]; then
        validate_workflow "$temp_file" || return 1
        echo ""
    fi

    # Revisar contenido antes de deployar
    step_5_review_content "$temp_file" || return 1
    echo ""

    # Desplegar
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY-RUN: Comando no ejecutado"
        echo ""
        echo "Comando que se ejecutaría:"
        echo "  gcloud workflows deploy $WORKFLOW_NAME --source=$temp_file --project=$GCP_PROJECT --location=$GCP_LOCATION --quiet"
        echo ""
        return 0
    else
        deploy_workflow "$temp_file" "$WORKFLOW_NAME" "$GCP_PROJECT" "$GCP_LOCATION" || return 1
    fi
}

################################################################################
# Main Loop
################################################################################

main() {
    clear_screen
    
    echo -e "${LGREEN}╔$(printf '═%.0s' {1..66})╗${NC}"
    echo -e "${LGREEN}║${NC} ${WHITE}Workflow Deployment Manager - Modo Interactivo${NC}$(printf ' %.0s' {1..17})${LGREEN}║${NC}"
    echo -e "${LGREEN}╚$(printf '═%.0s' {1..66})╝${NC}\n"
    
    while true; do
        # Step 1: GitLab Source
        if ! step_1_gitlab_source; then
            print_warning "Despliegue cancelado"
            break
        fi
        
        # Step 2: GCP Target
        step_2_gcp_target
        
        # Step 3: Options
        if ! step_3_options; then
            continue  # Volver al paso 1
        fi
        
        # Step 4: Preview
        step_4_preview
        case $? in
            0)
                # Ejecutar despliegue
                if execute_deployment; then
                    echo ""
                    echo -e "${GRAY}¿Deseas realizar otro despliegue?${NC}\n"
                    echo -e "  ${LCYAN}1)${NC} Sí, nuevo despliegue"
                    echo -e "  ${LCYAN}0)${NC} No, salir"
                    echo ""

                    echo -ne "${YELLOW}Opción${NC}: "
                    read -r choice

                    if [[ "$choice" != "1" ]]; then
                        break
                    fi
                else
                    echo ""
                    echo -ne "${GRAY}Presiona ENTER para continuar...${NC}"
                    read -r
                fi
                ;;
            1)
                # Volver al paso 3
                continue
                ;;
            2)
                # Cancelar todo
                print_warning "Despliegue cancelado"
                break
                ;;
        esac
    done
    
    echo -e "\n${GRAY}¡Hasta luego!${NC}\n"
}

################################################################################
# Trap signals and cleanup
################################################################################

trap 'echo ""; print_warning "Operación cancelada por el usuario"; exit 0' INT TERM

################################################################################
# Execute
################################################################################

main "$@"
