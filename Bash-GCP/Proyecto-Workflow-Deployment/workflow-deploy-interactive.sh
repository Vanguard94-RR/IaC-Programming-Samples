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
    
    eval "$var_name='$input_value'"
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

################################################################################
# Deployment Execution
################################################################################

build_command() {
    local cmd="python3 workflow-deploy.py"
    
    if [[ -n "${GITLAB_URL:-}" ]]; then
        cmd="$cmd --url '$GITLAB_URL'"
    else
        cmd="$cmd --gitlab-project '$GITLAB_PROJECT'"
        cmd="$cmd --branch '$GITLAB_BRANCH'"
        cmd="$cmd --path '$GITLAB_FILE'"
    fi
    
    cmd="$cmd --name '$WORKFLOW_NAME'"
    cmd="$cmd --project '$GCP_PROJECT'"
    cmd="$cmd --location '$GCP_LOCATION'"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        cmd="$cmd --dry-run"
    fi
    
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        cmd="$cmd --skip-validation"
    fi
    
    echo "$cmd"
}

execute_deployment() {
    clear_screen
    print_header "Ejecutando Despliegue"
    
    local cmd
    cmd=$(build_command)
    
    echo -e "${GRAY}Comando:${NC}"
    echo -e "  ${cmd}\n"
    echo -e "${GRAY}$(printf '═%.0s' {1..70})${NC}\n"
    
    cd "$SCRIPT_DIR"
    
    if eval "$cmd"; then
        echo -e "\n${GRAY}$(printf '═%.0s' {1..70})${NC}\n"
        print_success "Despliegue completado exitosamente"
        save_to_history "$WORKFLOW_NAME" "$GCP_PROJECT"
        return 0
    else
        echo -e "\n${GRAY}$(printf '═%.0s' {1..70})${NC}\n"
        print_error "El despliegue finalizó con errores"
        return 1
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
