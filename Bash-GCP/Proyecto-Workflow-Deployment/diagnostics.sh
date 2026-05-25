#!/bin/bash

################################################################################
# Workflow Deployment Diagnostics
################################################################################
# Script de diagnóstico para identificar problemas en el despliegue
#
# Uso:
#   chmod +x diagnostics.sh
#   ./diagnostics.sh
#
# Autor: GNP Infrastructure Team
################################################################################

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly GRAY='\033[0;90m'
readonly LGREEN='\033[1;32m'
readonly LCYAN='\033[1;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

print_header() {
    echo -e "${LCYAN}════════════════════════════════════════${NC}"
    echo -e "${LCYAN}║${NC} $1"
    echo -e "${LCYAN}════════════════════════════════════════${NC}\n"
}

print_check() {
    echo -e "${LGREEN}✓${NC} $1"
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# ============================================================================
# Test 1: gcloud Authentication
# ============================================================================
test_gcloud_auth() {
    print_header "Test 1: Autenticación gcloud"
    
    if ! command -v gcloud &> /dev/null; then
        print_fail "gcloud CLI no está instalado"
        return 1
    fi
    print_check "gcloud CLI instalado"
    
    # Verificar cuenta autenticada
    if gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
        local account
        account=$(gcloud config get-value account 2>/dev/null)
        print_check "Cuenta autenticada: $account"
    else
        print_fail "No hay cuenta autenticada"
        print_warn "Ejecuta: gcloud auth login"
        return 1
    fi
    
    # Verificar proyecto por defecto
    if gcloud config get-value project &>/dev/null; then
        local project
        project=$(gcloud config get-value project 2>/dev/null)
        print_info "Proyecto por defecto: $project"
    else
        print_warn "No hay proyecto por defecto configurado"
    fi
    
    # Probar credenciales de aplicación
    if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
        if [[ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
            print_check "Service Account: $GOOGLE_APPLICATION_CREDENTIALS"
        else
            print_fail "Archivo de Service Account no encontrado: $GOOGLE_APPLICATION_CREDENTIALS"
        fi
    fi
    
    return 0
}

# ============================================================================
# Test 2: GitLab Token
# ============================================================================
test_gitlab_token() {
    print_header "Test 2: Token de GitLab"
    
    local token_file="${1:-PersonalGitLabToken}"
    
    if [[ ! -f "$token_file" ]]; then
        print_fail "Token file no encontrado: $token_file"
        return 1
    fi
    
    local token
    token=$(cat "$token_file")
    
    if [[ -z "$token" ]]; then
        print_fail "Token vacío en $token_file"
        return 1
    fi
    
    # Verificar longitud (tokens típicos tienen >20 caracteres)
    if [[ ${#token} -lt 20 ]]; then
        print_warn "Token parece muy corto (${#token} caracteres)"
    else
        print_check "Token tiene ${#token} caracteres"
    fi
    
    # Verificar autenticación
    print_info "Verificando token con GitLab API..."
    
    if curl -s -H "PRIVATE-TOKEN: $token" \
        https://gitlab.com/api/v4/user 2>/dev/null | grep -q "username"; then
        print_check "Token válido y autenticado"
        return 0
    else
        print_fail "Token inválido o expirado"
        return 1
    fi
}

# ============================================================================
# Test 3: Verify File in GitLab
# ============================================================================
test_gitlab_file() {
    print_header "Test 3: Archivo en GitLab"
    
    local project="${1:-gitnp/cotizadores/gke-gnp-danios-config-back-end}"
    local branch="${2:-main}"
    local file="${3:-gnp-danios-wf/GoogleWF/workflow-emision-danios.yml}"
    local token_file="${4:-PersonalGitLabToken}"
    
    if [[ ! -f "$token_file" ]]; then
        print_fail "Token file no encontrado"
        return 1
    fi
    
    local token
    token=$(cat "$token_file")
    
    print_info "Proyecto: $project"
    print_info "Rama: $branch"
    print_info "Archivo: $file"
    echo ""
    
    # URL encode project path (reemplazar / con %2F)
    local encoded_project="${project//\//%2F}"
    local encoded_file="${file//\//%2F}"
    
    local url="https://gitlab.com/api/v4/projects/${encoded_project}/repository/files/${encoded_file}/raw"
    local response_code
    
    response_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "PRIVATE-TOKEN: $token" \
        "$url?ref=$branch")
    
    case "$response_code" in
        200)
            print_check "Archivo encontrado (HTTP 200)"
            return 0
            ;;
        404)
            print_fail "Archivo NO encontrado (HTTP 404)"
            print_info "Verificar:"
            print_info "  - Ruta correcta del archivo"
            print_info "  - Rama contiene el archivo"
            print_info "  - Acceso a repositorio"
            return 1
            ;;
        401)
            print_fail "No autorizado (HTTP 401) - Token inválido"
            return 1
            ;;
        *)
            print_fail "Error inesperado (HTTP $response_code)"
            return 1
            ;;
    esac
}

# ============================================================================
# Test 4: GCP Workflows Permission
# ============================================================================
test_gcp_workflows_permission() {
    print_header "Test 4: Permisos GCP Workflows"
    
    local project="${1:-gnp-wf-danios-qa}"
    
    print_info "Proyecto: $project"
    echo ""
    
    if ! gcloud workflows list --project="$project" &>/dev/null; then
        print_fail "Sin permisos para listar workflows en $project"
        return 1
    fi
    
    print_check "Permisos de lectura: ✓"
    
    # Listar workflows
    local count
    count=$(gcloud workflows list --project="$project" --format=json 2>/dev/null | grep -c "name" || echo "0")
    
    if [[ $count -eq 0 ]]; then
        print_warn "No hay workflows desplegados aún"
    else
        print_info "Workflows desplegados: $count"
        gcloud workflows list --project="$project" --format="table(name,location)" 2>/dev/null || true
    fi
}

# ============================================================================
# Test 5: Script Integrity
# ============================================================================
test_script_integrity() {
    print_header "Test 5: Integridad de scripts"
    
    # Verificar script bash
    if [[ -f "workflow-deploy-interactive.sh" ]]; then
        if bash -n workflow-deploy-interactive.sh 2>/dev/null; then
            print_check "workflow-deploy-interactive.sh: Sintaxis OK"
        else
            print_fail "workflow-deploy-interactive.sh: Error de sintaxis"
            bash -n workflow-deploy-interactive.sh 2>&1 | head -5
        fi
    else
        print_warn "workflow-deploy-interactive.sh no encontrado"
    fi
    
    # Verificar script Python
    if [[ -f "workflow-deploy.py" ]]; then
        if python3 -m py_compile workflow-deploy.py 2>/dev/null; then
            print_check "workflow-deploy.py: Sintaxis OK"
        else
            print_fail "workflow-deploy.py: Error de sintaxis"
        fi
    else
        print_warn "workflow-deploy.py no encontrado"
    fi
    
    # Verificar archivos de configuración
    if [[ -f ".env.local" ]]; then
        print_check ".env.local: Encontrado"
        grep -v "^#" .env.local | grep . || true
    else
        print_warn ".env.local: No encontrado (es opcional)"
    fi
}

# ============================================================================
# Test 6: Network Connectivity
# ============================================================================
test_network_connectivity() {
    print_header "Test 6: Conectividad de red"
    
    # Test GitLab
    if curl -s -m 5 https://gitlab.com 2>/dev/null | grep -q "gitlab"; then
        print_check "gitlab.com: Accesible"
    else
        print_fail "gitlab.com: No accesible"
    fi
    
    # Test Google Cloud
    if curl -s -m 5 https://www.googleapis.com 2>/dev/null | head -1 | grep -q "<!DOCTYPE"; then
        print_check "googleapis.com: Accesible"
    else
        print_fail "googleapis.com: No accesible"
    fi
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo -e "\n${LCYAN}╔$(printf '═%.0s' {1..62})╗${NC}"
    echo -e "${LCYAN}║${NC} ${WHITE}Workflow Deployment - Diagnostics${NC}$(printf ' %.0s' {1..23})${LCYAN}║${NC}"
    echo -e "${LCYAN}╚$(printf '═%.0s' {1..62})╝${NC}\n"
    
    local failed=0
    
    test_gcloud_auth || ((failed++))
    echo ""
    
    test_gitlab_token || ((failed++))
    echo ""
    
    test_gitlab_file "gitnp/cotizadores/gke-gnp-danios-config-back-end" "main" \
        "gnp-danios-wf/GoogleWF/workflow-emision-danios.yml" || ((failed++))
    echo ""
    
    test_gcp_workflows_permission "gnp-wf-danios-qa" || ((failed++))
    echo ""
    
    test_script_integrity || ((failed++))
    echo ""
    
    test_network_connectivity || ((failed++))
    echo ""
    
    # Resumen
    print_header "Resumen de Diagnóstico"
    
    if [[ $failed -eq 0 ]]; then
        print_check "Todos los tests pasaron ✓"
        echo -e "${LGREEN}El sistema está listo para despliegue${NC}\n"
        return 0
    else
        print_fail "$failed test(s) fallaron"
        echo -e "${YELLOW}Corregir los problemas anteriores antes de continuar${NC}\n"
        return 1
    fi
}

main "$@"
